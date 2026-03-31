extends Node

## N-stage coilgun sequencer.
##
## Stage firing is POSITION-BASED, not IR-gate-based.
## SimCtrl calls update_ferronock_pos() each frame; MCU fires stage i
## when the ferronock enters stage i's capture zone (1 coil_half before centre).
##
## This avoids all the geometry problems of using the 0.8m bolt body
## to trigger gates that are spaced only 0.4m apart.

@export var stage_count:        int   = 20
@export var firing_timeout_s:   float = 2.0
@export var target_velocity_ms:  float = 50.0  ## muzzle target [m/s]
@export var bolt_mass_kg:        float = 0.030 ## projectile mass [kg]
@export var stage_efficiency:    float = 0.18  ## cap energy → kinetic energy; measured 15-22% across stages (early stages lower, later stages ~22%)
@export var min_stage_voltage_v: float = 50.0  ## floor — no stage charges below this voltage
@export var group_size:          int   = 10    ## stages per charge group; mcu_ready fires after group 0 armed
@export var backward_fault_threshold_ms: float = -0.5  ## bolt reversal triggers FAULT [m/s]
@export var velocity_adapt_threshold_ms: float = 3.0   ## recompute voltages if measured error > this [m/s]

signal mcu_stage_charging(stage: int)
signal mcu_stage_armed(stage: int)
signal mcu_stage_fired(stage: int)
signal mcu_stage_drained(stage: int)
signal mcu_stage_safe(stage: int)
signal mcu_fault(stage: int, reason: String)
signal mcu_ready   ## all stages ARMED

enum StageState { SAFE, CHARGING, ARMED, FIRING, DRAINING, FAULT }

var _pp:    Array = []
var _sol:   Array = []
var _vs:    Array = []
var _ts:    Array = []
var _state: Array = []
var _timer: Array = []
var _fired: Array = []   ## true once stage has been triggered this shot

var _sim_ctrl: Node  = null
var _sim_time: float = 0.0

var _stage_target_v: Array = []  ## pre-computed cap voltage per stage [V]
var _v_profile:      Array = []  ## expected bolt velocity AFTER each stage [m/s]
var _current_vx:     float = 0.0 ## latest bolt velocity supplied by SimCtrl
var _ir_vx:          float = 0.0 ## IR gate velocity measurement (for adaptation only)
var _shot_active:    bool  = false ## true only between fire_request() and all-SAFE
var _group0_ready:   bool  = false ## latched true once mcu_ready has been emitted

## IR gate velocity measurement and adaptive voltage control
var _gate_x:             Array = []     ## world-X of each inter-stage IR gate
var _gate_t:             Array = []     ## last beam_broken time per gate [s]; -1 = not yet triggered
var _prev_gate_i:        int   = -1    ## index of last triggered gate this shot
var _backward_fault_cnt: int   = 0     ## consecutive backward-velocity frames
var _prev_fx:            float = -999.0 ## ferronock position from previous tick (sweep detection)

## Muzzle velocity (optional physical gates at barrel exit)
var _t_muzzle0: float = 0.0

func _ready() -> void:
	_sim_ctrl = get_node_or_null("../SimCtrl")

	for i in range(stage_count):
		var pp:  Node = get_node_or_null("../Segment%d/PowerPack" % i)
		var sol: Node = get_node_or_null("../Segment%d/Solenoid"  % i)
		_pp.append(pp)
		_sol.append(sol)
		_state.append(StageState.SAFE)
		_timer.append(0.0)
		_fired.append(false)

		if pp and pp.has_signal("charge_complete"):
			pp.charge_complete.connect(_on_stage_charged.bind(i))

		_setup_stage_sensors(i)

	## Inter-stage IR gates: one between each consecutive stage pair
	for i in range(stage_count - 1):
		_gate_t.append(-1.0)
		var gs: Node = get_node_or_null("../IRGateSegment%d" % i)
		_gate_x.append(gs.global_position.x if gs else 0.70 + i * 0.40)
		if gs:
			_connect_ir("../IRGateSegment%d/IRGate" % i,
				_on_ir_gate_triggered.bind(i),
				func(): pass)

	## Optional physical muzzle gates for velocity measurement
	_connect_ir("../IRGateMuzzle0",
		func(): _t_muzzle0 = _sim_time,
		func(): pass)
	_connect_ir("../IRGateMuzzle1",
		func(): _on_muzzle_exit(),
		func(): pass)

	print("MCU ready  stage_count=%d  ir_gates=%d" % [stage_count, _gate_t.size()])

func _setup_stage_sensors(i: int) -> void:
	var pp: Node = _pp[i] if i < _pp.size() else null
	if not pp:
		_vs.append(null); _ts.append(null); return
	var vs = pp.get_node_or_null("VoltageSensor")
	var ts = pp.get_node_or_null("TempSensor")
	_vs.append(vs)
	_ts.append(ts)
	if vs:
		if vs.has_signal("overvoltage"):
			vs.overvoltage.connect( func(v): _trigger_fault(i, "overvoltage %.1fV"  % v))
		if vs.has_signal("undervoltage"):
			vs.undervoltage.connect(func(v): _trigger_fault(i, "undervoltage %.1fV" % v))
	if ts and ts.has_signal("overtemp"):
		ts.overtemp.connect(func(t): _trigger_fault(i, "overtemp %.1f°C" % t))

func _connect_ir(path: String, broken: Callable, restored: Callable) -> void:
	var g: Node = get_node_or_null(path)
	if not g: return
	if g.has_signal("beam_broken"):   g.beam_broken.connect(broken)
	if g.has_signal("beam_restored"): g.beam_restored.connect(restored)

func _physics_process(delta: float) -> void:
	_sim_time += delta

	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if not pp: continue
		if i < _vs.size() and _vs[i]: _vs[i].sample(pp.get_voltage())
		if i < _ts.size() and _ts[i]: _ts[i].sample(pp.get_coil_temp_c())

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

## Pre-compute per-stage capacitor voltages so each stage delivers the same ΔV,
## producing a linear velocity ramp from from_vx to target_velocity_ms.
## Higher stages charge to higher voltages because KE scales with v·ΔV.
func _compute_stage_voltages(from_stage: int, from_vx: float) -> void:
	_stage_target_v.resize(stage_count)
	_v_profile.resize(stage_count)
	var n_rem: int   = stage_count - from_stage
	if n_rem <= 0: return
	var v_rem: float = maxf(target_velocity_ms - from_vx, 0.0)
	var dv:    float = v_rem / float(n_rem)          ## constant ΔV per stage
	for i in range(from_stage, stage_count):
		var j:     int   = i - from_stage
		var v_in:  float = from_vx + j * dv
		var v_out: float = from_vx + (j + 1) * dv
		_v_profile[i] = v_out
		var dke:   float = 0.5 * bolt_mass_kg * (v_out * v_out - v_in * v_in)
		var e_cap: float = maxf(dke, 1e-9) / maxf(stage_efficiency, 0.01)
		var pp:    Node  = _pp[i] if i < _pp.size() else null
		var c:     float = pp.capacitance_f if (pp and "capacitance_f" in pp) else 0.001
		_stage_target_v[i] = maxf(sqrt(2.0 * e_cap / c), min_stage_voltage_v)
	print("MCU: velocity profile  V[0]=%.1fV  V[%d]=%.1fV  target=%.0f m/s" \
		% [_stage_target_v[from_stage], stage_count - 1,
		   _stage_target_v[stage_count - 1], target_velocity_ms])

## Called by SimCtrl every physics frame.
## Stores current velocity for feedback, checks for fault conditions,
## then forwards position to cascade logic.
func update_bolt_state(fx: float, vx: float) -> void:
	_current_vx = vx
	if _shot_active:
		if vx < backward_fault_threshold_ms:
			_backward_fault_cnt += 1
			if _backward_fault_cnt >= 2:  ## 2 consecutive frames ≈ 33 ms
				_trigger_bolt_fault(vx)
				return
		else:
			_backward_fault_cnt = 0
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

## ── User interface ────────────────────────────────────────────────────────────

func arm_request() -> void:
	_group0_ready = false
	_compute_stage_voltages(0, 0.0)
	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if pp and i < _stage_target_v.size():
			pp.target_voltage_v = _stage_target_v[i]
			## Raise overvoltage fault threshold to match computed stage voltage
			if i < _vs.size() and _vs[i] and "max_voltage_v" in _vs[i]:
				_vs[i].max_voltage_v = _stage_target_v[i] * 1.15
		_charge_stage(i)

func fire_request() -> void:
	if _state[0] != StageState.ARMED: return
	if _sim_ctrl and _sim_ctrl.has_method("reset_bolt"):
		_sim_ctrl.reset_bolt()
	_sim_time            = 0.0
	_shot_active         = true
	_prev_fx             = -999.0
	_backward_fault_cnt  = 0
	_prev_gate_i         = -1
	for i in range(_gate_t.size()): _gate_t[i] = -1.0
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

## ── IR gate callbacks ─────────────────────────────────────────────────────────

## Triggered when the bolt breaks the IR beam at gate_i (between stage i and i+1).
## Measures actual inter-gate velocity and recomputes remaining stage voltages if
## the bolt is significantly off the target velocity profile.
func _on_ir_gate_triggered(gate_i: int) -> void:
	if not _shot_active: return
	_gate_t[gate_i] = _sim_time

	if _prev_gate_i >= 0 and _gate_t[_prev_gate_i] > 0.0:
		var dt: float = _sim_time - _gate_t[_prev_gate_i]
		if dt > 0.0005:  ## > 0.5 ms — reject spurious double-triggers
			var dx:     float = _gate_x[gate_i] - _gate_x[_prev_gate_i]
			var v_meas: float = dx / dt

			if v_meas < backward_fault_threshold_ms:
				_trigger_bolt_fault(v_meas)
				return

			_ir_vx = v_meas  ## store for adaptation; cascade uses physics vx via update_bolt_state

			## Compare to expected profile after stage gate_i
			var v_exp: float = get_v_profile(gate_i)
			print("MCU: IR[%d]  v_ir=%.2f m/s  v_phys=%.2f  target=%.2f  err=%.2f" \
				% [gate_i, v_meas, _current_vx, v_exp, v_meas - v_exp])

			## Velocity feedback: recompute remaining stage voltages if off by threshold.
			## Only effective when stages are still in CHARGING state; if all stages
			## are pre-armed (typical for short barrels), adaptation has no effect.
			var next_stage: int = gate_i + 1
			if next_stage < stage_count and absf(v_meas - v_exp) > velocity_adapt_threshold_ms:
				var n_charging: int = 0
				for j in range(next_stage, _pp.size()):
					if _state[j] == StageState.CHARGING: n_charging += 1
				if n_charging > 0:
					print("MCU: adapting S%d–S%d voltages (v=%.1f vs %.1f m/s, %d still charging)" \
						% [next_stage, stage_count - 1, v_meas, v_exp, n_charging])
					_compute_stage_voltages(next_stage, v_meas)
					for j in range(next_stage, _pp.size()):
						if _pp[j] and j < _stage_target_v.size():
							if _state[j] == StageState.CHARGING:
								_pp[j].target_voltage_v = _stage_target_v[j]
								if j < _vs.size() and _vs[j] and "max_voltage_v" in _vs[j]:
									_vs[j].max_voltage_v = _stage_target_v[j] * 1.15

	_prev_gate_i = gate_i

## Emergency stop: bolt is moving backwards during a shot.
## Drains all active stages and locks out further firing.
func _trigger_bolt_fault(vx: float) -> void:
	var reason: String = "bolt reversed vx=%.2f m/s" % vx
	print("MCU: *** FAULT *** %s" % reason)
	_shot_active        = false
	_backward_fault_cnt = 0
	for i in range(_pp.size()):
		if _state[i] in [StageState.FIRING, StageState.ARMED, StageState.CHARGING]:
			if _pp[i]: _pp[i].drain()
			_state[i] = StageState.FAULT
	mcu_fault.emit(0, reason)

## ── Internal ─────────────────────────────────────────────────────────────────

func _charge_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	if _state[i] in [StageState.CHARGING, StageState.ARMED,
					  StageState.FIRING]: return
	_pp[i].begin_charge()
	_set_state(i, StageState.CHARGING)

func _on_stage_charged(i: int) -> void:
	_set_state(i, StageState.ARMED)
	if _group0_ready: return  ## mcu_ready already emitted for this arm cycle
	## Emit mcu_ready when the first group (stages 0..group_size-1) is fully armed.
	## Remaining groups keep charging in background and fire if the bolt reaches them.
	var g: int = mini(group_size, stage_count)
	for s in range(g):
		if _state[s] != StageState.ARMED: return
	_group0_ready = true
	print("MCU: GROUP 0 (%d stages) ARMED — READY TO FIRE" % g)
	mcu_ready.emit()

func _on_muzzle_exit() -> void:
	var dt: float = _sim_time - _t_muzzle0
	var v_ms: float = 0.20 / dt if dt > 0.0001 else 0.0
	print("MCU: MUZZLE v≈%.1f m/s (Δt=%.5fs)" % [v_ms, dt])
	var hud: Node = get_node_or_null("../HUD")
	if hud and hud.has_method("show_muzzle_velocity"):
		hud.show_muzzle_velocity(v_ms)

func _set_state(i: int, s: StageState) -> void:
	_state[i] = s
	var pp: Node = _pp[i] if i < _pp.size() else null
	match s:
		StageState.CHARGING:
			print("MCU: S%d CHARGING" % i)
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
	print("MCU: *** FAULT S%d *** %s" % [i, reason])
	if i < _pp.size() and _pp[i]: _pp[i].drain()
	_state[i] = StageState.FAULT
	mcu_fault.emit(i, reason)
