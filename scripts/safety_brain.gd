extends Node

## Safety Brain — watchdog MCU with kill authority.
##
## Owns: voltage sensors, temp sensors, IR gates, bleed switches, kill switch.
## Responsibility: fault detection every tick, bolt tracking via IR gates.
## Feeds: ferronock position + velocity to firing brain each tick.
## Authority: can kill (drain all caps) independently of firing brain.
##
## In hardware: separate MCU (e.g., ATtiny or STM32) connected to firing brain
## via SPI/UART.  Pin-limited; only needs ADC inputs + digital outputs for bleeds.

@export var stage_count:                  int   = 20
@export var backward_fault_threshold_ms:  float = -0.5
@export var kill_on_fault:                bool  = true  ## auto-drain on any fault

signal bolt_state_updated(fx: float, vx: float)
signal fault_detected(stage: int, reason: String)
signal system_kill(reason: String)
signal ir_gate_triggered(gate_i: int, v_meas: float)

var _pp:    Array = []
var _sol:   Array = []
var _vs:    Array = []
var _ts:    Array = []

var _gate_x:        Array = []
var _gate_t:        Array = []
var _prev_gate_i:   int   = -1
var _sim_time:      float = 0.0
var _current_fx:    float = 0.0
var _current_vx:    float = 0.0
var _backward_cnt:  int   = 0
var _killed:        bool  = false
var _shot_active:   bool  = false

## Muzzle velocity (optional physical gates at barrel exit)
var _t_muzzle0: float = 0.0

func _ready() -> void:
	for i in range(stage_count):
		var pp:  Node = get_node_or_null("../Segment%d/PowerPack" % i)
		var sol: Node = get_node_or_null("../Segment%d/Solenoid"  % i)
		_pp.append(pp)
		_sol.append(sol)
		_setup_sensors(i)

	## Inter-stage IR gates
	for i in range(stage_count - 1):
		_gate_t.append(-1.0)
		var gs: Node = get_node_or_null("../IRGateSegment%d" % i)
		_gate_x.append(gs.global_position.x if gs else 0.70 + i * 0.40)
		if gs:
			var g: Node = get_node_or_null("../IRGateSegment%d/IRGate" % i)
			if g and g.has_signal("beam_broken"):
				g.beam_broken.connect(_on_ir_gate_triggered.bind(i))

	## Optional muzzle gates
	_connect_ir("../IRGateMuzzle0", func(): _t_muzzle0 = _sim_time)
	_connect_ir("../IRGateMuzzle1", func(): _on_muzzle_exit())

	print("SafetyBrain ready  stages=%d  ir_gates=%d" % [stage_count, _gate_t.size()])

func _setup_sensors(i: int) -> void:
	var pp: Node = _pp[i] if i < _pp.size() else null
	if not pp:
		_vs.append(null); _ts.append(null); return
	var vs = pp.get_node_or_null("VoltageSensor")
	var ts = pp.get_node_or_null("TempSensor")
	_vs.append(vs)
	_ts.append(ts)
	if vs:
		if vs.has_signal("overvoltage"):
			vs.overvoltage.connect(func(v): _on_fault(i, "overvoltage %.1fV" % v))
		if vs.has_signal("undervoltage"):
			vs.undervoltage.connect(func(v): _on_fault(i, "undervoltage %.1fV" % v))
	if ts and ts.has_signal("overtemp"):
		ts.overtemp.connect(func(t): _on_fault(i, "overtemp %.1f°C" % t))

func _connect_ir(path: String, cb: Callable) -> void:
	var g: Node = get_node_or_null(path)
	if g and g.has_signal("beam_broken"): g.beam_broken.connect(cb)

## ── Per-tick sensor sampling ────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_sim_time += delta

	## Sample all sensors
	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if not pp: continue
		if i < _vs.size() and _vs[i]: _vs[i].sample(pp.get_voltage())
		if i < _ts.size() and _ts[i]: _ts[i].sample(pp.get_coil_temp_c())

## ── Bolt state (called by SimCtrl) ──────────────────────────────────────────

func update_bolt_state(fx: float, vx: float) -> void:
	_current_fx = fx
	_current_vx = vx

	## Backward-motion fault check
	if _shot_active:
		if vx < backward_fault_threshold_ms:
			_backward_cnt += 1
			if _backward_cnt >= 2:
				_trigger_system_kill("bolt reversed vx=%.2f m/s" % vx)
				return
		else:
			_backward_cnt = 0

	## Feed bolt state to firing brain
	bolt_state_updated.emit(fx, vx)

func get_bolt_fx() -> float: return _current_fx
func get_bolt_vx() -> float: return _current_vx

## ── Shot lifecycle (firing brain notifies us) ───────────────────────────────

func notify_shot_start() -> void:
	_shot_active    = true
	_backward_cnt   = 0
	_prev_gate_i    = -1
	_killed         = false
	for i in range(_gate_t.size()): _gate_t[i] = -1.0
	## Reset fault tracking for new shot cycle
	_faulted.resize(stage_count)
	for i in range(stage_count): _faulted[i] = false

func notify_shot_end() -> void:
	_shot_active = false

## ── IR gate callbacks ───────────────────────────────────────────────────────

func _on_ir_gate_triggered(gate_i: int) -> void:
	if not _shot_active: return
	_gate_t[gate_i] = _sim_time

	if _prev_gate_i >= 0 and _gate_t[_prev_gate_i] > 0.0:
		var dt: float = _sim_time - _gate_t[_prev_gate_i]
		if dt > 0.0005:
			var dx:     float = _gate_x[gate_i] - _gate_x[_prev_gate_i]
			var v_meas: float = dx / dt

			if v_meas < backward_fault_threshold_ms:
				_trigger_system_kill("IR gate backward v=%.2f m/s" % v_meas)
				return

			ir_gate_triggered.emit(gate_i, v_meas)
			print("SafetyBrain: IR[%d]  v_ir=%.2f m/s  v_phys=%.2f" \
				% [gate_i, v_meas, _current_vx])

	_prev_gate_i = gate_i

## ── Sensor threshold management ──────────────────────────────────────────────

## Called by firing brain after computing voltage profile.
## Sets overvoltage thresholds to 115% of each stage's target voltage.
func set_voltage_limits(stage_voltages: Array) -> void:
	for i in range(mini(stage_voltages.size(), _vs.size())):
		if _vs[i] and "max_voltage_v" in _vs[i]:
			_vs[i].max_voltage_v = stage_voltages[i] * 1.15
	print("SafetyBrain: voltage limits updated (S0=%.0fV ... S%d=%.0fV)" \
		% [stage_voltages[0] * 1.15 if stage_voltages.size() > 0 else 0,
		   stage_voltages.size() - 1,
		   stage_voltages[stage_voltages.size() - 1] * 1.15 if stage_voltages.size() > 0 else 0])

## ── Fault handling ──────────────────────────────────────────────────────────

var _faulted: Array = []  ## track which stages have already faulted this cycle

func _on_fault(stage: int, reason: String) -> void:
	## Initialize fault tracking array on first use
	if _faulted.size() != stage_count:
		_faulted.resize(stage_count)
		for i in range(stage_count): _faulted[i] = false
	if stage < _faulted.size() and _faulted[stage]: return  ## already reported
	if stage < _faulted.size(): _faulted[stage] = true
	print("SafetyBrain: *** FAULT S%d *** %s" % [stage, reason])
	fault_detected.emit(stage, reason)
	if kill_on_fault:
		drain_stage(stage)

func _trigger_system_kill(reason: String) -> void:
	if _killed: return
	_killed      = true
	_shot_active = false
	print("SafetyBrain: *** SYSTEM KILL *** %s" % reason)
	for i in range(_pp.size()):
		drain_stage(i)
	system_kill.emit(reason)

## ── Bleed / drain control (safety brain owns these switches) ────────────────

func drain_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	_pp[i].drain()

func drain_all() -> void:
	for i in range(_pp.size()):
		drain_stage(i)

func is_killed() -> bool: return _killed

func clear_kill() -> void:
	_killed = false

## ── Muzzle gate ─────────────────────────────────────────────────────────────

func _on_muzzle_exit() -> void:
	var dt: float = _sim_time - _t_muzzle0
	var v_ms: float = 0.20 / dt if dt > 0.0001 else 0.0
	print("SafetyBrain: MUZZLE v≈%.1f m/s (Δt=%.5fs)" % [v_ms, dt])
	var hud: Node = get_node_or_null("../HUD")
	if hud and hud.has_method("show_muzzle_velocity"):
		hud.show_muzzle_velocity(v_ms)
