extends Node
class_name MCU

## Multi-stage fire sequencer, sensor watchdog, and fault manager.
##
## Scales automatically to any number of stages.
## Name convention in the parent scene:
##   PowerPack0 … PowerPackN-1
##   Solenoid0  … SolenoidN-1   (optional — used by SimCtrl)
##   IRGate<i>Trigger            (optional — fires stage i when beam breaks)
##   IRGate<i>Front              (optional — muzzle-velocity gate on last stage)
##
## User flow:
##   arm_request()  → charges all caps (SAFE → CHARGING → ARMED)
##   fire_request() → resets bolt, fires stage 0 (ARMED → FIRING)
##   Subsequent stages fire automatically via IR gate cascade.
##
## ── Adding stages ─────────────────────────────────────────────────────────────
## 1. Add PowerPackN to the parent scene.
## 2. Increment stage_count export.
## 3. Add IRGate<N>Trigger (optional — for auto-cascade).
## All signal names, StageState values, and method signatures are stable.
##
## ── Swapping for a real MCU (UART/USB bridge) ─────────────────────────────────
## • arm_request / fire_request → TX serial command packets
## • on_ir_gateN_*  callbacks   → RX serial interrupt handlers
## • _physics_process polling   → RX ADC telemetry stream
## • Signal names, StageState enum, method signatures stay IDENTICAL

@export var stage_count:       int   = 2
@export var firing_timeout_s:  float = 2.0

## Outbound signals — keep names identical in any real MCU bridge
signal mcu_stage_charging(stage: int)
signal mcu_stage_armed(stage: int)
signal mcu_stage_fired(stage: int)
signal mcu_stage_drained(stage: int)
signal mcu_stage_safe(stage: int)
signal mcu_fault(stage: int, reason: String)
signal mcu_ready   ## all stages ARMED, fire_request() may be called

enum StageState { SAFE, CHARGING, ARMED, FIRING, DRAINING, FAULT }

var _pp:    Array = []
var _vs:    Array = []
var _ts:    Array = []
var _state: Array = []
var _timer: Array = []

var _t_trig:    Array = []   ## IR trigger timestamps per stage
var _sim_ctrl:  Node  = null
var _sim_time:  float = 0.0

func _ready() -> void:
	_sim_ctrl = get_node_or_null("../SimCtrl")

	## Dynamically discover PowerPack nodes
	for i in range(stage_count):
		var pp: Node = get_node_or_null("../PowerPack%d" % i)
		_pp.append(pp)
		_state.append(StageState.SAFE)
		_timer.append(0.0)
		_t_trig.append(0.0)

		if pp and pp.has_signal("charge_complete"):
			pp.charge_complete.connect(_on_stage_charged.bind(i))

		_setup_stage_sensors(i)

	## Wire IR gates dynamically
	for i in range(stage_count):
		_connect_ir_gate("../IRGate%dTrigger" % i,
			func(): _on_ir_trigger(i),
			func(): print("MCU: IRGate%dTrigger restored" % i))
		_connect_ir_gate("../IRGate%dFront" % i,
			func(): _on_ir_front(i),
			func(): print("MCU: IRGate%dFront restored" % i))
		_connect_ir_gate("../IRGate%dRear" % i,
			func(): print("MCU: IRGate%dRear BROKEN" % i),
			func(): print("MCU: IRGate%dRear restored" % i))

func _connect_ir_gate(path: String, broken_cb: Callable, restored_cb: Callable) -> void:
	var gate: Node = get_node_or_null(path)
	if not gate: return
	if gate.has_signal("beam_broken"):   gate.beam_broken.connect(broken_cb)
	if gate.has_signal("beam_restored"): gate.beam_restored.connect(restored_cb)

func _setup_stage_sensors(i: int) -> void:
	var pp: Node = _pp[i] if i < _pp.size() else null
	if not pp:
		_vs.append(null); _ts.append(null); return
	var vs: VoltageSensor = pp.get_node_or_null("VoltageSensor") as VoltageSensor
	var ts: TempSensor    = pp.get_node_or_null("TempSensor")    as TempSensor
	_vs.append(vs)
	_ts.append(ts)
	if vs:
		vs.overvoltage.connect( func(v): _trigger_fault(i, "overvoltage %.1fV"  % v))
		vs.undervoltage.connect(func(v): _trigger_fault(i, "undervoltage %.1fV" % v))
	if ts:
		ts.overtemp.connect(    func(t): _trigger_fault(i, "overtemp %.1f°C"    % t))

func _physics_process(delta: float) -> void:
	_sim_time += delta

	## Poll sensors
	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if not pp: continue
		if i < _vs.size() and _vs[i]: _vs[i].sample(pp.get_voltage())
		if i < _ts.size() and _ts[i]: _ts[i].sample(pp.get_coil_temp_c())

	## Watchdogs
	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		match _state[i]:
			StageState.FIRING:
				_timer[i] += delta
				if _timer[i] > firing_timeout_s:
					_trigger_fault(i, "S%d firing timeout %.2fs" % [i, _timer[i]])
				elif pp and not pp.is_fire_active():
					_set_state(i, StageState.SAFE)
			StageState.DRAINING:
				if pp and not pp.is_drain_active():
					_set_state(i, StageState.SAFE)

## ── User-facing interface ─────────────────────────────────────────────────────

func arm_request() -> void:
	for i in range(_pp.size()):
		_charge_stage(i)

func fire_request() -> void:
	if _state[0] != StageState.ARMED: return
	if _sim_ctrl and _sim_ctrl.has_method("reset_bolt"):
		_sim_ctrl.reset_bolt()
	_sim_time = 0.0
	fire_stage(0)

## ── Stage command interface ───────────────────────────────────────────────────

func arm_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	if _state[i] == StageState.SAFE:
		_pp[i].arm()
		if i == 0: _sim_time = 0.0
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

func get_sensor_reading(stage: int, which: String) -> float:
	if stage >= _pp.size(): return 0.0
	match which:
		"voltage": return _vs[stage].get_reading() if (stage < _vs.size() and _vs[stage]) else 0.0
		"temp":    return _ts[stage].get_reading()  if (stage < _ts.size() and _ts[stage]) else 0.0
	return 0.0

## ── IR gate callbacks ─────────────────────────────────────────────────────────

func _on_ir_trigger(i: int) -> void:
	_t_trig[i] = _sim_time
	print("MCU: IRGate%dTrigger BROKEN — firing stage %d  (S%d: %s)" \
		% [i, i, i, get_stage_state_name(i)])
	fire_stage(i)

func _on_ir_front(i: int) -> void:
	var dt: float = _sim_time - _t_trig[i]
	## 0.25 m is the IR gate spacing (IRGate1Trigger x=1.05 → IRGate1Front x=1.30)
	var gate_spacing: float = 0.25
	var v_ms: float = gate_spacing / dt if dt > 0.0001 else 0.0
	print("MCU: IRGate%dFront BROKEN — v≈%.1f m/s  (Δt=%.5fs)" % [i, v_ms, dt])
	## Push to HUD if it's the last gate
	if i == stage_count - 1:
		var hud: Node = get_node_or_null("../HUD")
		if hud and hud.has_method("show_muzzle_velocity"):
			hud.show_muzzle_velocity(v_ms)

## ── Internal helpers ─────────────────────────────────────────────────────────

func _charge_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	if _state[i] in [StageState.CHARGING, StageState.ARMED, StageState.FIRING]: return
	_pp[i].begin_charge()
	_set_state(i, StageState.CHARGING)

func _on_stage_charged(i: int) -> void:
	_set_state(i, StageState.ARMED)
	for s in _state:
		if s != StageState.ARMED: return
	print("MCU: ALL STAGES ARMED — ready to fire")
	mcu_ready.emit()

func _set_state(i: int, s: StageState) -> void:
	_state[i] = s
	var pp: Node = _pp[i] if i < _pp.size() else null
	match s:
		StageState.CHARGING:
			print("MCU: S%d CHARGING" % i)
			mcu_stage_charging.emit(i)
		StageState.ARMED:
			print("MCU: S%d ARMED    V=%.1fV" % [i, pp.get_voltage() if pp else 0.0])
			mcu_stage_armed.emit(i)
		StageState.FIRING:
			print("MCU: S%d FIRING   V=%.1fV" % [i, pp.get_voltage() if pp else 0.0])
			mcu_stage_fired.emit(i)
		StageState.DRAINING:
			print("MCU: S%d DRAINING" % i)
			mcu_stage_drained.emit(i)
		StageState.SAFE:
			print("MCU: S%d SAFE" % i)
			mcu_stage_safe.emit(i)
		StageState.FAULT:
			pass  ## logged by _trigger_fault

func _trigger_fault(i: int, reason: String) -> void:
	print("MCU: *** FAULT S%d *** %s" % [i, reason])
	if i < _pp.size() and _pp[i]: _pp[i].drain()
	_state[i] = StageState.FAULT
	mcu_fault.emit(i, reason)
