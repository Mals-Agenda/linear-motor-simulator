extends Node

## Firing Brain — N-stage coilgun sequencer and charge controller.
##
## Owns: fire switches, boost chargers, cascade logic, voltage profiles.
## Receives bolt state from SafetyBrain (which owns sensors, IR gates, bleeds).
##
## Stage firing is POSITION-BASED: fires stage i when the ferronock enters
## the capture zone (1 coil_half before centre).

@export var stage_count:        int   = 20
@export var firing_timeout_s:   float = 2.0
@export var target_velocity_ms:  float = 50.0  ## muzzle target [m/s]
@export var bolt_mass_kg:        float = 0.030 ## projectile mass [kg]
@export var peak_efficiency:     float = 0.25  ## max cap→KE efficiency at optimal bolt speed
@export var R_coil_ohm:         float = 0.50  ## total circuit resistance (coil + ESR) [Ω]
@export var min_stage_voltage_v: float = 50.0  ## floor — no stage charges below this voltage
@export var max_stage_voltage_v: float = 1000.0 ## ceiling — cap voltage rating; computed voltages rarely exceed this with bell-curve caps
@export var group_size:          int   = 10    ## stages per charge group; mcu_ready fires after group 0 armed
@export var backward_fault_threshold_ms: float = -0.5  ## bolt reversal triggers FAULT [m/s]
@export var velocity_adapt_threshold_ms: float = 3.0   ## recompute voltages if measured error > this [m/s]
@export var auto_calibrate:              bool  = true   ## learn from each shot to improve accuracy

@export_group("Capacitance Profile")
@export var cap_end_f:    float = 0.0015  ## capacitance at barrel ends (S0, S19) [F] — 1.5 mF
@export var cap_center_f: float = 0.0045  ## capacitance at barrel centre [F] — 4.5 mF

signal mcu_stage_charging(stage: int)
signal mcu_stage_armed(stage: int)
signal mcu_stage_fired(stage: int)
signal mcu_stage_drained(stage: int)
signal mcu_stage_safe(stage: int)
signal mcu_fault(stage: int, reason: String)
signal mcu_pre_charged  ## all stages at pre-charge voltage
signal mcu_ready        ## all stages ARMED (topped up)

@export_group("Charging / Power Bus")
@export var pre_charge_voltage_v: float = 50.0   ## base voltage when safety comes off [V]
@export var max_charge_power_w:   float = 600.0  ## total power budget from battery [W]

enum StageState { SAFE, PRE_CHARGING, PRE_CHARGED, TOPPING_UP, ARMED, FIRING, DRAINING, FAULT }

var _pp:    Array = []
var _sol:   Array = []
var _state: Array = []
var _timer: Array = []
var _fired: Array = []   ## true once stage has been triggered this shot

var _sim_ctrl:     Node  = null
var _battery:      Node  = null
var _safety_brain: Node  = null
var _sim_time:     float = 0.0

var _stage_target_v: Array = []  ## pre-computed cap voltage per stage [V]
var _v_profile:      Array = []  ## expected bolt velocity AFTER each stage [m/s]
var _current_vx:     float = 0.0 ## latest bolt velocity supplied by SimCtrl
var _ir_vx:          float = 0.0 ## IR gate velocity measurement (for adaptation only)
var _shot_active:    bool  = false ## true only between fire_request() and all-SAFE
var _group0_ready:   bool  = false ## latched true once mcu_ready has been emitted

## Auto-calibration: per-stage correction factors learned from previous shots.
## η_correction[i] multiplies the predicted η for stage i.
## Starts at 1.0; after each shot, adjusted based on actual vs predicted ΔV.
var _eta_correction: Array = []  ## per-stage multiplier (default 1.0)
var _shot_v_actual:  Array = []  ## actual velocity at each stage's de-energise point

## IR gate positions (needed for velocity adaptation)
var _gate_x:    Array = []
var _gate_t:    Array = []
var _prev_fx:   float = -999.0 ## ferronock position from previous tick (sweep detection)

func _ready() -> void:
	_sim_ctrl     = get_node_or_null("../SimCtrl")
	_battery      = get_node_or_null("../Battery")
	_safety_brain = get_node_or_null("../SafetyBrain")

	for i in range(stage_count):
		var pp:  Node = get_node_or_null("../Segment%d/PowerPack" % i)
		var sol: Node = get_node_or_null("../Segment%d/Solenoid"  % i)
		_pp.append(pp)
		_sol.append(sol)
		_state.append(StageState.SAFE)
		_timer.append(0.0)
		_fired.append(false)
		_eta_correction.append(1.0)
		_shot_v_actual.append(0.0)

		if pp and pp.has_signal("charge_complete"):
			pp.charge_complete.connect(_on_stage_charged.bind(i))

	_apply_cap_profile()

	## Connect to safety brain signals (simulated SPI bus)
	if _safety_brain:
		_safety_brain.bolt_state_updated.connect(_on_bolt_state_from_safety)
		_safety_brain.fault_detected.connect(_on_fault_from_safety)
		_safety_brain.system_kill.connect(_on_system_kill)
		_safety_brain.ir_gate_triggered.connect(_on_ir_gate_from_safety)

	## IR gate position lookup (firing brain needs gate_x for velocity adaptation)
	for i in range(stage_count - 1):
		_gate_t.append(-1.0)
		var gs: Node = get_node_or_null("../IRGateSegment%d" % i)
		_gate_x.append(gs.global_position.x if gs else 0.70 + i * 0.40)

	print("FiringBrain ready  stage_count=%d" % stage_count)

## Distribute capacitance across stages using a smooth bell curve:
## sin(π·t) where t = i/(N-1), peaking at barrel centre.
## C(i) = cap_end_f + (cap_center_f − cap_end_f) · sin(π·t)
func _apply_cap_profile() -> void:
	var n: int = _pp.size()
	if n < 2: return
	var parts: PackedStringArray = []
	for i in range(n):
		var pp: Node = _pp[i]
		if not pp: continue
		var t: float = float(i) / float(n - 1)  ## 0.0 at S0, 1.0 at S19
		var c: float = cap_end_f + (cap_center_f - cap_end_f) * sin(PI * t)
		pp.capacitance_f = c
		if i < 4 or i >= n - 4 or i == n / 2:
			parts.append("S%d=%.1fmF" % [i, c * 1000.0])
	print("MCU: cap profile  %s  (bell %.1f→%.1f→%.1fmF)" \
		% ["  ".join(parts), cap_end_f * 1000.0, cap_center_f * 1000.0, cap_end_f * 1000.0])

## ── Safety brain signal handlers (simulated SPI bus from watchdog MCU) ───────

func _on_bolt_state_from_safety(fx: float, vx: float) -> void:
	_current_vx = vx
	update_ferronock_pos(fx)

func _on_fault_from_safety(stage: int, reason: String) -> void:
	if stage < _state.size() and _state[stage] != StageState.FAULT:
		_state[stage] = StageState.FAULT
		mcu_fault.emit(stage, reason)

func _on_system_kill(_reason: String) -> void:
	_shot_active = false
	for i in range(_state.size()):
		_state[i] = StageState.FAULT

func _on_ir_gate_from_safety(gate_i: int, v_meas: float) -> void:
	## Velocity adaptation — same logic as before but triggered by safety brain
	_ir_vx = v_meas
	var v_exp: float = get_v_profile(gate_i)
	print("FiringBrain: IR[%d]  v_ir=%.2f  v_phys=%.2f  target=%.2f  err=%.2f" \
		% [gate_i, v_meas, _current_vx, v_exp, v_meas - v_exp])
	var next_stage: int = gate_i + 1
	if next_stage < stage_count and absf(v_meas - v_exp) > velocity_adapt_threshold_ms:
		var n_charging: int = 0
		for j in range(next_stage, _pp.size()):
			if _state[j] == StageState.TOPPING_UP: n_charging += 1
		if n_charging > 0:
			print("FiringBrain: adapting S%d–S%d voltages (%d still charging)" \
				% [next_stage, stage_count - 1, n_charging])
			_compute_stage_voltages(next_stage, v_meas)
			for j in range(next_stage, _pp.size()):
				if _pp[j] and j < _stage_target_v.size():
					if _state[j] == StageState.TOPPING_UP:
						_pp[j].target_voltage_v = _stage_target_v[j]

func _physics_process(delta: float) -> void:
	_sim_time += delta

	## ── Power bus: distribute charge power budget across active chargers ──
	_update_charge_bus(delta)

	## Sensor sampling moved to SafetyBrain

	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		match _state[i]:
			StageState.FIRING:
				_timer[i] += delta
				if _timer[i] > firing_timeout_s:
					_trigger_fault(i, "S%d firing timeout" % i)
				elif pp and not pp.is_fire_active():
					_set_state(i, StageState.SAFE)
			StageState.DRAINING:
				if pp and not pp.is_drain_active():
					_set_state(i, StageState.SAFE)

	## Retire skipped ARMED stages: if all _fired[] are true but some stages
	## are still ARMED (never fired, bolt passed them), transition to SAFE
	## so the shot can complete cleanly.
	if _shot_active:
		var all_fired: bool = true
		for f in _fired:
			if not f: all_fired = false; break
		if all_fired:
			for i in range(_state.size()):
				if _state[i] == StageState.ARMED:
					_set_state(i, StageState.SAFE)

	## Clear _shot_active once all stages return to SAFE/FAULT after a shot.
	if _shot_active:
		var shot_done: bool = true
		for s in _state:
			if s != StageState.SAFE and s != StageState.FAULT:
				shot_done = false; break
		if shot_done:
			_shot_active = false
			_calibrate_from_shot()
			if _safety_brain and _safety_brain.has_method("notify_shot_end"):
				_safety_brain.notify_shot_end()

## ── Power bus ────────────────────────────────────────────────────────────────

## Distribute total charge power budget across all actively-charging stages.
## Draws current from the battery and scales each stage's charge rate.
func _update_charge_bus(delta: float) -> void:
	var n_charging: int = 0
	for i in range(_pp.size()):
		if _state[i] in [StageState.PRE_CHARGING, StageState.TOPPING_UP]:
			n_charging += 1
	if n_charging == 0: return

	## Equal share of power budget per active charger
	var per_stage_w: float = max_charge_power_w / float(n_charging)
	var total_current: float = 0.0

	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if not pp: continue
		if _state[i] in [StageState.PRE_CHARGING, StageState.TOPPING_UP]:
			pp.set_charge_power(per_stage_w)
			## Estimate current draw for battery: P = V·I → I = P/V_battery
			total_current += per_stage_w / 42.0  ## rough battery voltage
		else:
			pp.set_charge_power(0.0)

	## Draw from battery
	if _battery and _battery.has_method("draw"):
		_battery.draw(total_current, delta)

## ── Position-based cascade ────────────────────────────────────────────────────

## Compute fire_pos for stage i given bolt velocity vx.
## fire_pos is where the bolt must be for LC current to peak at ξ≈−0.44.
func _get_fire_pos(i: int, vx: float) -> float:
	var pp:   Node  = _pp[i]  if i < _pp.size()  else null
	var sol:  Node  = _sol[i] if i < _sol.size() else null
	var cx:   float = sol.global_position.x if sol else (0.50 + i * 0.40)
	var half: float = 0.15
	if sol and "coil_length" in sol:
		half = sol.coil_length * 0.5
	var L_peak: float = sol.get_inductance(cx - 0.44 * half) \
			if (sol and sol.has_method("get_inductance")) else 0.003
	var C_f:    float = pp.capacitance_f \
			if (pp and "capacitance_f" in pp) else 0.001
	var T_qtr:  float = PI * sqrt(L_peak * C_f) / 4.0
	var dt_half: float = 0.5 / float(Engine.physics_ticks_per_second)
	return maxf(cx - 0.44 * half - absf(vx) * (T_qtr + dt_half), cx - half)

## Return solenoid centre-x for stage i.
func _get_cx(i: int) -> float:
	var sol: Node = _sol[i] if i < _sol.size() else null
	return sol.global_position.x if sol else (0.50 + i * 0.40)

## Called by SimCtrl every physics frame with the ferronock world position.
## Fires stage i so that the LC current peaks at ξ≈−0.44 (peak dL/dx).
##
## Sweep detection: if the bolt crosses fire_pos between [_prev_fx, fx], fire
## even if the bolt is already past centre — SimCtrl's force loop guards
## backward force independently.  A late-fired stage wastes its cap but
## doesn't brake, and the de-energise immediately calls pp.safe().
##
## Pre-fire lookahead: when stage i fires, adjacent stages whose fire_pos
## will be reached within ~2·T_qtr are also fired in the same tick.  This
## handles the case where the force impulse from stage i would push the bolt
## past stage i+1's window before the next tick.
func update_ferronock_pos(fx: float) -> void:
	if not _shot_active: return
	for i in range(_pp.size()):
		if _fired[i]: continue
		if _state[i] != StageState.ARMED: continue
		var cx:       float = _get_cx(i)
		var fire_pos: float = _get_fire_pos(i, _current_vx)
		## Sweep: bolt may have crossed fire_pos in the interval [_prev_fx, fx]
		var swept:     bool = _prev_fx < fire_pos and fx >= fire_pos
		var in_window: bool = fx >= fire_pos and fx < cx
		if swept or in_window:
			_fired[i] = true
			if _current_vx < target_velocity_ms:
				fire_stage(i)
				## Pre-fire lookahead: fire upcoming stages that the bolt will
				## reach during this stage's LC rise time.
				var pp_i:  Node  = _pp[i] if i < _pp.size() else null
				var C_f:   float = pp_i.capacitance_f if (pp_i and "capacitance_f" in pp_i) else 0.001
				var sol_i: Node  = _sol[i] if i < _sol.size() else null
				var half_i: float = 0.15
				if sol_i and "coil_length" in sol_i: half_i = sol_i.coil_length * 0.5
				var L_pk: float = sol_i.get_inductance(cx - 0.44 * half_i) \
						if (sol_i and sol_i.has_method("get_inductance")) else 0.003
				var T_qtr: float = PI * sqrt(L_pk * C_f) / 4.0
				var predicted_fx: float = fx + absf(_current_vx) * T_qtr * 2.0
				for j in range(i + 1, _pp.size()):
					if _fired[j]: continue
					if _state[j] != StageState.ARMED: continue
					if predicted_fx >= _get_fire_pos(j, _current_vx):
						_fired[j] = true
						if _current_vx < target_velocity_ms:
							fire_stage(j)
					else:
						break  ## stages are sequential; stop at first non-reached
		elif fx >= cx:
			_fired[i] = true  ## past centre without firing
			print("MCU: S%d SKIPPED (past cx=%.3f  fx=%.3f  state=%s  vx=%.2f)" \
				% [i, cx, fx, StageState.keys()[_state[i]], _current_vx])
	_prev_fx = fx

## ── Velocity-profile control ──────────────────────────────────────────────────

## Speed-dependent efficiency model.
##
## Efficiency depends on how well the LC discharge timing matches the bolt's
## transit through the coil force zone:
##   T_qtr   = π√(LC)/4           — time for current to peak
##   T_trans = coil_length / v     — bolt transit time through coil
##   τ_ratio = T_qtr / T_trans    — coupling ratio
##
## At τ_ratio ≈ 0.5 (current peaks mid-transit), efficiency is maximum.
## At low speed (τ_ratio << 0.5): current peaks before bolt moves → resistive loss.
## At high speed (τ_ratio >> 0.5): bolt outruns the current pulse → incomplete coupling.
##
## η(v) = peak_efficiency × (1 − R_loss) × coupling(τ_ratio)
##   R_loss    = R / (2·Z)  where Z = √(L/C)  — fraction lost to resistance
##   coupling  = exp(−2·(τ_ratio − 0.5)²)     — Gaussian peaked at optimal ratio
func _stage_efficiency(i: int, v_bolt: float) -> float:
	var pp:   Node  = _pp[i]  if i < _pp.size()  else null
	var sol:  Node  = _sol[i] if i < _sol.size() else null
	var c:    float = pp.capacitance_f if (pp and "capacitance_f" in pp) else 0.001
	var half: float = 0.15
	if sol and "coil_length" in sol: half = sol.coil_length * 0.5
	var coil_len: float = half * 2.0

	## LC parameters at peak-force position
	var cx: float = sol.global_position.x if sol else (0.50 + i * 0.40)
	var L_peak: float = sol.get_inductance(cx - 0.44 * half) \
			if (sol and sol.has_method("get_inductance")) else 0.003
	var T_qtr: float = PI * sqrt(L_peak * c) / 4.0

	## Impedance and resistive loss fraction
	var Z: float = sqrt(L_peak / c)            ## characteristic impedance [Ω]
	var r_loss: float = R_coil_ohm / (2.0 * Z) ## fraction of energy lost to R
	r_loss = clampf(r_loss, 0.0, 0.95)

	## Transit time — bolt speed through coil
	var v_eff:   float = maxf(absf(v_bolt), 0.5) ## floor at 0.5 m/s to avoid div-by-zero
	var T_trans: float = coil_len / v_eff
	var T_half:  float = T_qtr * 2.0

	## Coupling: asymmetric model based on timescale mismatch.
	## Optimal when T_transit ≈ T_half (bolt spends exactly one LC half-cycle in coil).
	## Too slow (T_trans > T_half): bolt absorbs energy over multiple LC oscillations
	##   but most dissipates as I²R → gentle power-law rolloff.
	## Too fast (T_trans < T_half): bolt exits before current peaks → linear drop.
	var coupling: float
	if T_trans >= T_half:
		## Slow bolt: power-law gives ~4-5% efficiency at v≈0 (matches measured data)
		coupling = pow(T_half / T_trans, 0.3)
	else:
		## Fast bolt: linear drop — bolt outruns the current pulse
		coupling = T_trans / T_half

	var eta: float = peak_efficiency * (1.0 - r_loss) * coupling
	## Apply learned correction from previous shots
	var corr: float = _eta_correction[i] if i < _eta_correction.size() else 1.0
	eta *= corr
	return maxf(eta, 0.005)  ## floor at 0.5% to prevent infinite voltage

## Pre-compute per-stage capacitor voltages so each stage delivers the same ΔV,
## producing a linear velocity ramp from from_vx to target_velocity_ms.
## Uses speed-dependent efficiency: each stage's η is computed from its bolt
## entry velocity, LC parameters, and coil geometry.
func _compute_stage_voltages(from_stage: int, from_vx: float) -> void:
	_stage_target_v.resize(stage_count)
	_v_profile.resize(stage_count)
	var n_rem: int   = stage_count - from_stage
	if n_rem <= 0: return
	var v_rem: float = maxf(target_velocity_ms - from_vx, 0.0)
	var dv:    float = v_rem / float(n_rem)          ## constant ΔV per stage
	var eta_parts: PackedStringArray = []
	for i in range(from_stage, stage_count):
		var j:     int   = i - from_stage
		var v_in:  float = from_vx + j * dv
		var v_out: float = from_vx + (j + 1) * dv
		_v_profile[i] = v_out
		var eta:   float = _stage_efficiency(i, v_in)
		var dke:   float = 0.5 * bolt_mass_kg * (v_out * v_out - v_in * v_in)
		var e_cap: float = maxf(dke, 1e-9) / maxf(eta, 0.005)
		var pp:    Node  = _pp[i] if i < _pp.size() else null
		var c:     float = pp.capacitance_f if (pp and "capacitance_f" in pp) else 0.001
		_stage_target_v[i] = clampf(sqrt(2.0 * e_cap / c),
				min_stage_voltage_v, max_stage_voltage_v)
		if i < 4 or i >= stage_count - 4 or i == stage_count / 2:
			eta_parts.append("S%d=%.0f%%@%.0fm/s" % [i, eta * 100.0, v_in])
	var n_clamped: int = 0
	for i in range(from_stage, stage_count):
		if _stage_target_v[i] >= max_stage_voltage_v: n_clamped += 1
	var clamp_str: String = "  (%d stages at cap limit)" % n_clamped if n_clamped > 0 else ""
	print("MCU: velocity profile  V[0]=%.1fV  V[%d]=%.1fV  target=%.0f m/s%s" \
		% [_stage_target_v[from_stage], stage_count - 1,
		   _stage_target_v[stage_count - 1], target_velocity_ms, clamp_str])
	print("MCU: η profile  %s" % "  ".join(eta_parts))

## Bolt state now received via _on_bolt_state_from_safety signal from SafetyBrain.
## Legacy direct call kept for SimCtrl compatibility during transition.
func update_bolt_state(fx: float, vx: float) -> void:
	if not _safety_brain:
		## Fallback if no safety brain: direct update (legacy mode)
		_current_vx = vx
		update_ferronock_pos(fx)

## Highest-indexed stage currently FIRING, or -1 if none active.
func get_firing_stage() -> int:
	for i in range(_pp.size() - 1, -1, -1):
		if _state[i] == StageState.FIRING:
			return i
	return -1

## Expected bolt velocity after stage i exits, from the current profile.
func get_v_profile(i: int) -> float:
	if i < 0 or i >= _v_profile.size(): return target_velocity_ms
	return _v_profile[i]

## ── Calibration ──────────────────────────────────────────────────────────────

## Called by SimCtrl when a stage de-energises, recording actual bolt velocity.
func notify_stage_deenergised(stage: int, vx: float) -> void:
	if stage < _shot_v_actual.size():
		_shot_v_actual[stage] = vx

## Called when shot completes. Compares actual vs predicted per-stage velocity
## and adjusts η correction factors for the next shot.
func _calibrate_from_shot() -> void:
	if not auto_calibrate: return
	if _v_profile.size() != stage_count: return

	## Global muzzle velocity correction: single scalar applied uniformly.
	## Stable and converges in 2-3 shots regardless of per-stage timing quirks.
	var v_muzzle_actual: float = _shot_v_actual[stage_count - 1]
	var v_muzzle_target: float = target_velocity_ms
	if v_muzzle_actual < 0.1 or v_muzzle_target < 0.1: return

	var energy_ratio: float = (v_muzzle_actual * v_muzzle_actual) / \
							  (v_muzzle_target * v_muzzle_target)
	## Apply same correction to ALL stages uniformly
	for i in range(stage_count):
		var new_corr: float = _eta_correction[i] * energy_ratio
		_eta_correction[i] = _eta_correction[i] * 0.3 + new_corr * 0.7
		_eta_correction[i] = clampf(_eta_correction[i], 0.05, 5.0)

	print("FiringBrain: calibration  muzzle=%.1f/%.1f m/s  global_corr=%.3f" \
		% [v_muzzle_actual, v_muzzle_target, _eta_correction[0]])

## ── User interface ────────────────────────────────────────────────────────────

func set_target_velocity(v_ms: float) -> void:
	target_velocity_ms = clampf(v_ms, 10.0, 300.0)

## Phase 1: Safety off → compute voltage profile and pre-charge to 80% of fire voltage.
## This front-loads most of the charge time so trigger-to-ready is fast.
func safety_off() -> void:
	_group0_ready = false
	_compute_stage_voltages(0, 0.0)
	## Tell safety brain the voltage limits so sensors don't false-trigger
	if _safety_brain and _safety_brain.has_method("set_voltage_limits"):
		_safety_brain.set_voltage_limits(_stage_target_v)
	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if not pp: continue
		## Pre-charge to 80% of fire voltage (minimum pre_charge_voltage_v)
		var fire_v: float = _stage_target_v[i] if i < _stage_target_v.size() else pre_charge_voltage_v
		var pre_v:  float = maxf(fire_v * 0.95, pre_charge_voltage_v)
		pp.target_voltage_v = pre_v
		if _state[i] == StageState.SAFE:
			pp.begin_charge()
			_set_state(i, StageState.PRE_CHARGING)
	print("MCU: SAFETY OFF — pre-charging to 95%% of fire voltage (%.0f–%.0fV)" \
		% [_pp[0].target_voltage_v if _pp[0] else 0, _pp[_pp.size()-1].target_voltage_v if _pp.size() > 0 else 0])

## Phase 2: Trigger stage 1 → top-up from 95% to 100% fire voltage.
## Should complete in ~2-3 seconds since only 10% of energy remains.
func top_up_request() -> void:
	print("MCU: TOP-UP — charging final 20%%")
	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if not pp: continue
		if i < _stage_target_v.size():
			pp.target_voltage_v = _stage_target_v[i]
		if _state[i] == StageState.PRE_CHARGED:
			pp.begin_top_up()
			_set_state(i, StageState.TOPPING_UP)

## Phase 3: Trigger stage 2 → fire
func fire_request() -> void:
	if _state[0] != StageState.ARMED: return
	## In sim: auto-reload bolt to breach position before firing
	if _sim_ctrl and _sim_ctrl.has_method("reset_bolt"):
		_sim_ctrl.reset_bolt()
	## In real hardware: check bolt is loaded (remove the auto-reload above)
	#if _sim_ctrl and _sim_ctrl.has_method("is_bolt_loaded"):
	#	if not _sim_ctrl.is_bolt_loaded():
	#		print("FiringBrain: ABORT — no bolt loaded")
	#		return
	_sim_time    = 0.0
	_shot_active = true
	_prev_fx     = -999.0
	for i in range(_gate_t.size()): _gate_t[i] = -1.0
	for i in range(_shot_v_actual.size()): _shot_v_actual[i] = 0.0
	## Notify safety brain that a shot is starting
	if _safety_brain and _safety_brain.has_method("notify_shot_start"):
		_safety_brain.notify_shot_start()
	for i in range(_fired.size()):  _fired[i] = false
	_fired[0] = true   ## stage 0 is being manually triggered right now
	fire_stage(0)

## ── Stage control (also callable directly) ───────────────────────────────────

func arm_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	if _state[i] == StageState.SAFE:
		_pp[i].arm()
		_set_state(i, StageState.ARMED)

func fire_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	if _state[i] == StageState.ARMED:
		_pp[i].fire()
		_timer[i] = 0.0
		_set_state(i, StageState.FIRING)

func drain_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	_pp[i].drain()
	_set_state(i, StageState.DRAINING)

func reset_fault(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	if _state[i] == StageState.FAULT:
		_pp[i].safe()
		_set_state(i, StageState.SAFE)

func get_stage_state_name(i: int) -> String:
	if i >= _state.size(): return "INVALID"
	return StageState.keys()[_state[i]]

## IR gate and fault handling moved to SafetyBrain.
## Firing brain receives processed signals via _on_ir_gate_from_safety
## and _on_fault_from_safety / _on_system_kill.

## ── Internal ─────────────────────────────────────────────────────────────────

func _charge_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	if _state[i] in [StageState.PRE_CHARGING, StageState.TOPPING_UP,
					  StageState.ARMED, StageState.FIRING]: return
	_pp[i].begin_charge()
	_set_state(i, StageState.PRE_CHARGING)

func _on_stage_charged(i: int) -> void:
	## Called when a PowerPack reaches its target_voltage_v.
	## Route to the correct next state based on current state.
	if _state[i] == StageState.PRE_CHARGING:
		_set_state(i, StageState.PRE_CHARGED)
		## Check if ALL stages are pre-charged
		var all_pre: bool = true
		for s in _state:
			if s == StageState.PRE_CHARGING: all_pre = false; break
		if all_pre:
			print("MCU: ALL STAGES PRE-CHARGED at %.0fV" % pre_charge_voltage_v)
			mcu_pre_charged.emit()
	elif _state[i] == StageState.TOPPING_UP:
		_set_state(i, StageState.ARMED)
		if _group0_ready: return
		var g: int = mini(group_size, stage_count)
		for s in range(g):
			if _state[s] != StageState.ARMED: return
		_group0_ready = true
		print("MCU: ALL STAGES ARMED — READY TO FIRE")
		mcu_ready.emit()

func _set_state(i: int, s: StageState) -> void:
	_state[i] = s
	var pp: Node = _pp[i] if i < _pp.size() else null
	match s:
		StageState.PRE_CHARGING:
			print("MCU: S%d PRE_CHARGING" % i)
			mcu_stage_charging.emit(i)
		StageState.PRE_CHARGED:
			print("MCU: S%d PRE_CHARGED  V=%.1f" % [i, pp.get_voltage() if pp else 0.0])
			pass
		StageState.TOPPING_UP:
			print("MCU: S%d TOPPING_UP  →%.1fV" % [i, pp.target_voltage_v if pp else 0.0])
			mcu_stage_charging.emit(i)
		StageState.ARMED:
			print("MCU: S%d ARMED  V=%.1f" % [i, pp.get_voltage() if pp else 0.0])
			mcu_stage_armed.emit(i)
		StageState.FIRING:
			print("MCU: S%d FIRING  V=%.1f" % [i, pp.get_voltage() if pp else 0.0])
			mcu_stage_fired.emit(i)
		StageState.DRAINING:
			print("MCU: S%d DRAINING" % i)
			mcu_stage_drained.emit(i)
		StageState.SAFE:
			print("MCU: S%d SAFE" % i)
			mcu_stage_safe.emit(i)
		StageState.FAULT:
			pass

func _trigger_fault(i: int, reason: String) -> void:
	if _state[i] == StageState.FAULT: return  ## already faulted — don't spam
	print("FiringBrain: *** FAULT S%d *** %s" % [i, reason])
	## Request safety brain to drain (it owns bleed switches)
	if _safety_brain and _safety_brain.has_method("drain_stage"):
		_safety_brain.drain_stage(i)
	elif i < _pp.size() and _pp[i]:
		_pp[i].drain()  ## fallback if no safety brain
	_state[i] = StageState.FAULT
	mcu_fault.emit(i, reason)
