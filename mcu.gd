extends Node
class_name MCU

## Multi-stage fire sequencer, sensor watchdog, and fault manager.
##
## User flow:
##   arm_request()  → charges all caps (SAFE → CHARGING → ARMED)
##   fire_request() → resets bolt, fires stage 0 (ARMED → FIRING)
##   Stage 1 fires automatically via IR gate cascade.
##
## ── Adding stage N ────────────────────────────────────────────────────────────
## 1. Add @onready var ppN = $"../PowerPackN"
## 2. Append ppN to _pp in _ready()
## 3. Add on_ir_gateN_* callbacks wired from CrossbowRig.tscn
##
## ── Swapping for a real MCU (UART/USB bridge) ─────────────────────────────────
## • arm_request / fire_request → TX serial command packets
## • on_ir_gate_* callbacks     → RX serial interrupt handlers
## • _physics_process polling   → RX ADC telemetry stream
## • Signal names, StageState enum, method signatures stay IDENTICAL

@onready var pp0       = $"../PowerPack0"
@onready var pp1       = $"../PowerPack1"
@onready var _sim_ctrl = $"../SimCtrl"

@export var firing_timeout_s: float = 2.0

## Outbound signals — keep names identical in any real MCU bridge
signal mcu_stage_charging(stage: int)
signal mcu_stage_armed(stage: int)
signal mcu_stage_fired(stage: int)
signal mcu_stage_drained(stage: int)
signal mcu_fault(stage: int, reason: String)
signal mcu_ready   ## all stages ARMED, fire_request() may be called

enum StageState { SAFE, CHARGING, ARMED, FIRING, DRAINING, FAULT }

var _pp:    Array = []
var _vs:    Array = []
var _ts:    Array = []
var _state: Array = []
var _timer: Array = []

var _t_ir1_trigger: float = 0.0
var _t_ir1_front:   float = 0.0
var _sim_time:      float = 0.0

func _ready() -> void:
	_pp    = [pp0, pp1]
	_state = [StageState.SAFE, StageState.SAFE]
	_timer = [0.0, 0.0]

	## Connect charge_complete signals once
	for i in range(_pp.size()):
		if _pp[i] and _pp[i].has_signal("charge_complete"):
			_pp[i].charge_complete.connect(_on_stage_charged.bind(i))

	_setup_stage_sensors(0)
	_setup_stage_sensors(1)

func _setup_stage_sensors(i: int) -> void:
	var pp = _pp[i] if i < _pp.size() else null
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
		var pp = _pp[i]
		if not pp: continue
		if i < _vs.size() and _vs[i]: _vs[i].sample(pp.get_voltage())
		if i < _ts.size() and _ts[i]: _ts[i].sample(pp.get_coil_temp_c())

	## Watchdogs
	for i in range(_pp.size()):
		var pp = _pp[i]
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
	## Charge all stages simultaneously from 0V
	for i in range(_pp.size()):
		_charge_stage(i)

func fire_request() -> void:
	## Fire stage 0 only if armed; reset bolt first
	if _state[0] != StageState.ARMED: return
	if _sim_ctrl and _sim_ctrl.has_method("reset_bolt"):
		_sim_ctrl.reset_bolt()
	_sim_time = 0.0
	fire_stage(0)

## ── Stage command interface ───────────────────────────────────────────────────

func arm_stage(i: int) -> void:
	## Instant-arm (sets voltage directly) — used as fallback if no charger
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

## ── IR gate callbacks (wired from CrossbowRig.tscn) ──────────────────────────

func on_ir_gate0_rear_broken()    -> void: print("MCU: IRGate0Rear  BROKEN")
func on_ir_gate0_rear_restored()  -> void: print("MCU: IRGate0Rear  restored")

func on_ir_gate0_front_broken() -> void:
	## Bolt cleared stage 0 — stage 1 should already be ARMED from arm_request
	print("MCU: IRGate0Front BROKEN — S1: %s" % get_stage_state_name(1))

func on_ir_gate0_front_restored() -> void: print("MCU: IRGate0Front restored")

func on_ir_gate1_trigger_broken() -> void:
	_t_ir1_trigger = _sim_time
	print("MCU: IRGate1Trigger BROKEN — firing stage 1")
	fire_stage(1)

func on_ir_gate1_trigger_restored() -> void: print("MCU: IRGate1Trigger restored")

func on_ir_gate1_front_broken() -> void:
	_t_ir1_front = _sim_time
	var dt: float = _t_ir1_front - _t_ir1_trigger
	var v_muzzle: float = 0.43 / dt if dt > 0.0001 else 0.0
	print("MCU: IRGate1Front BROKEN — muzzle v≈%.1f m/s  (Δt=%.5fs)" % [v_muzzle, dt])
	## Push to HUD if available
	var hud = get_node_or_null("../HUD")
	if hud and hud.has_method("show_muzzle_velocity"):
		hud.show_muzzle_velocity(v_muzzle)

func on_ir_gate1_front_restored() -> void: print("MCU: IRGate1Front restored")

## ── Internal helpers ─────────────────────────────────────────────────────────

func _charge_stage(i: int) -> void:
	if i >= _pp.size() or not _pp[i]: return
	## Skip if already in progress
	if _state[i] in [StageState.CHARGING, StageState.ARMED, StageState.FIRING]: return
	_pp[i].begin_charge()
	_set_state(i, StageState.CHARGING)

func _on_stage_charged(i: int) -> void:
	_set_state(i, StageState.ARMED)
	## Emit mcu_ready when all stages are ARMED
	for s in _state:
		if s != StageState.ARMED: return
	print("MCU: ALL STAGES ARMED — ready to fire")
	mcu_ready.emit()

func _set_state(i: int, s: StageState) -> void:
	_state[i] = s
	var pp = _pp[i] if i < _pp.size() else null
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
		StageState.FAULT:
			pass  ## logged by _trigger_fault

func _trigger_fault(i: int, reason: String) -> void:
	print("MCU: *** FAULT S%d *** %s" % [i, reason])
	if i < _pp.size() and _pp[i]: _pp[i].drain()
	_state[i] = StageState.FAULT
	mcu_fault.emit(i, reason)
