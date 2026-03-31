extends Node

## Physics controller — applies solenoid, drag, friction, and magnet forces each frame.
##
## Scales to N stages automatically by reading stage_count from MCU.
## Each frame it:
##   1. Passes bolt position + velocity into each PowerPack (back-EMF coupling).
##   2. Queries each Solenoid for position-dependent force F = ½·I²·dL/dx.
##   3. De-energises a stage when bolt centre passes solenoid centre.
##   4. Accumulates all forces → bolt.constant_force.

@onready var bolt:        RigidBody3D = $"../Bolt"
@onready var breach_door              = $"../BreachDoor"
@onready var mcu:         Node        = $"../MCU"
@onready var _telem_graph: Node       = $"../TelemetryGraph"
@onready var _recorder:    Node       = $"../ShotRecorder"

@export var friction_coeff:   float = 0.15
@export var drag_coeff:       float = 0.02
@export var bolt_load_offset: float = 0.10   ## bolt centre behind solenoid0 centre [m]
@export var ferronock_offset: float = 0.37   ## bolt centre to ferronock [m]
@export var barrel_start_x:   float = 0.00
@export var barrel_end_x:     float = 2.50

## Populated in _ready from sibling PowerPackN / SolenoidN nodes
var _pp:   Array = []
var _sol:  Array = []
var _deenergised: Array = []

var _breach_ok:   bool  = false
var _mcu_ok:      bool  = false
var _sim_time:    float = 0.0

## Telemetry IR state (used in log string)
var _ir0_rear_blocked:  bool = false
var _ir0_front_blocked: bool = false
var _ir1_trig_blocked:  bool = false
var _ir1_front_blocked: bool = false

func _ready() -> void:
	if not bolt:
		push_error("SimCtrl: Bolt node missing"); return

	_breach_ok = breach_door != null and breach_door.has_method("get_magnet_force")
	_mcu_ok    = mcu         != null and mcu.has_method("fire_stage")

	## Discover stage nodes from MCU stage_count (or scan until not found)
	var n: int = mcu.stage_count if (_mcu_ok and "stage_count" in mcu) else 2
	for i in range(n):
		var pp:  Node = get_node_or_null("../PowerPack%d" % i)
		var sol: Node = get_node_or_null("../Solenoid%d"  % i)
		_pp.append(pp)
		_sol.append(sol)
		_deenergised.append(false)

	## Connect IR telemetry
	_connect_ir("../IRGate0Rear",    _on_telem_ir0_rear_broken,    _on_telem_ir0_rear_restored)
	_connect_ir("../IRGate0Front",   _on_telem_ir0_front_broken,   _on_telem_ir0_front_restored)
	_connect_ir("../IRGate1Trigger", _on_telem_ir1_trig_broken,    _on_telem_ir1_trig_restored)
	_connect_ir("../IRGate1Front",   _on_telem_ir1_front_broken,   _on_telem_ir1_front_restored)

	var cx: String = ""
	for i in range(_sol.size()):
		var sol: Node = _sol[i]
		cx += " cx%d=%.3f" % [i, sol.global_position.x if sol else 0.0]
	print("SimCtrl ready  stages=%d%s  breach=%s  mcu=%s" % [_pp.size(), cx, _breach_ok, _mcu_ok])

func _connect_ir(path: String, broken_cb: Callable, restored_cb: Callable) -> void:
	var n: Node = get_node_or_null(path)
	if n:
		if n.has_signal("beam_broken"):   n.beam_broken.connect(broken_cb)
		if n.has_signal("beam_restored"): n.beam_restored.connect(restored_cb)

func _physics_process(delta: float) -> void:
	if not bolt: return
	_sim_time += delta

	var x:  float = bolt.global_position.x
	var vx: float = bolt.linear_velocity.x
	var ferronock_x: float = x - ferronock_offset

	## ── Pass bolt state into each power pack (enables back-EMF) ──────────────
	for i in range(_pp.size()):
		var pp:  Node = _pp[i]
		var sol: Node = _sol[i]
		if pp and pp.has_method("set_bolt_state"):
			pp.set_bolt_state(x, vx, sol)

	## ── De-energise each stage when bolt centre passes solenoid centre ────────
	for i in range(_pp.size()):
		var pp:  Node = _pp[i]
		var sol: Node = _sol[i]
		if not pp or not sol: continue
		var cx: float = sol.center_x if "center_x" in sol else sol.global_position.x
		if not _deenergised[i] and pp.is_fire_active() and x >= cx:
			_deenergised[i] = true
			pp.safe()
			print("EVENT: S%d de-energised  t=%.4f  x=%.3f  v=%.3f" % [i, _sim_time, x, vx])

	## ── Compute forces ────────────────────────────────────────────────────────
	var f_total: float = 0.0

	for i in range(_pp.size()):
		var pp:  Node = _pp[i]
		var sol: Node = _sol[i]
		if not pp or not sol: continue
		var isq:   float = pp.get_avg_current_sq()
		var f_sol: float = sol.get_force(x, isq) if sol.has_method("get_force") else 0.0
		f_total += f_sol

	var in_barrel:  bool  = x > barrel_start_x and x < barrel_end_x
	var f_friction: float = -friction_coeff * vx if in_barrel else 0.0
	var f_drag:     float = -drag_coeff * vx * abs(vx)
	var f_magnet:   float = breach_door.get_magnet_force(ferronock_x) if _breach_ok else 0.0

	f_total += f_friction + f_drag + f_magnet
	bolt.constant_force = Vector3(f_total, 0.0, 0.0)

	_log_telemetry(x, vx, f_friction, f_drag, f_magnet)
	_feed_instruments(x, vx, f_friction, f_drag, f_magnet)

## ── Public interface ──────────────────────────────────────────────────────────

func reset_bolt() -> void:
	if not bolt: return
	for i in range(_deenergised.size()):
		_deenergised[i] = false
	_sim_time = 0.0
	bolt.constant_force  = Vector3.ZERO
	bolt.linear_velocity = Vector3.ZERO
	## Load position: bolt centre just behind solenoid0
	var cx0: float = _sol[0].global_position.x if (_sol.size() > 0 and _sol[0]) else 0.75
	bolt.global_position = Vector3(cx0 - bolt_load_offset, 0.0, 0.0)

func fire() -> void:
	reset_bolt()
	if _mcu_ok:
		mcu.fire_stage(0)
	elif _pp.size() > 0 and _pp[0]:
		_pp[0].arm()
		_pp[0].fire()

func get_bolt_euler_deg() -> Vector3:
	return bolt.rotation_degrees if bolt else Vector3.ZERO

func get_bolt_omega() -> Vector3:
	return bolt.angular_velocity if bolt else Vector3.ZERO

func get_ir_states() -> Array:
	return [_ir0_rear_blocked, _ir0_front_blocked, _ir1_trig_blocked, _ir1_front_blocked]

## ── Telemetry ─────────────────────────────────────────────────────────────────

func _log_telemetry(x: float, vx: float, f_fric: float, f_drag: float, f_mag: float) -> void:
	var parts: Array = ["t=%.4f x=%.4f v=%.4f" % [_sim_time, x, vx]]
	for i in range(_pp.size()):
		var pp:  Node = _pp[i]
		var sol: Node = _sol[i]
		var vc:  float = pp.get_voltage()        if (pp  and pp.has_method("get_voltage"))       else 0.0
		var I:   float = pp.get_rms_current()    if (pp  and pp.has_method("get_rms_current"))   else 0.0
		var T:   float = pp.get_coil_temp_c()    if (pp  and pp.has_method("get_coil_temp_c"))   else 0.0
		var F:   float = sol.get_force(x, pp.get_avg_current_sq() if pp else 0.0) \
						if (sol and sol.has_method("get_force")) else 0.0
		var L:   float = sol.get_inductance(x)   if (sol and sol.has_method("get_inductance"))   else 0.0
		var en:  String = "ON" if (pp and pp.is_fire_active()) else "OFF"
		parts.append("S%d[Vc=%.1f I=%.2f T=%.1f F=%.2f L=%.5f %s]" % [i, vc, I, T, F, L, en])
	parts.append("Ff=%.3f Fd=%.3f Fm=%.3f" % [f_fric, f_drag, f_mag])
	parts.append("IR[%s %s %s %s]" % [
		"T" if _ir0_rear_blocked  else "F",
		"T" if _ir0_front_blocked else "F",
		"T" if _ir1_trig_blocked  else "F",
		"T" if _ir1_front_blocked else "F"])
	print(" ".join(parts))

## ── Instrument feed ──────────────────────────────────────────────────────────

func _feed_instruments(x: float, vx: float, ff: float, fd: float, fm: float) -> void:
	## Gather per-stage values (up to 2 for graph channels; recorder uses first 2)
	var vc0: float = 0.0; var i0: float = 0.0; var f0: float = 0.0
	var l0:  float = 0.0; var t0: float = 0.0
	var vc1: float = 0.0; var i1: float = 0.0; var f1: float = 0.0
	var l1:  float = 0.0; var t1: float = 0.0

	if _pp.size() > 0 and _pp[0]:
		vc0 = _pp[0].get_voltage()
		i0  = _pp[0].get_rms_current()
		t0  = _pp[0].get_coil_temp_c()
	if _sol.size() > 0 and _sol[0]:
		f0 = _sol[0].get_force(bolt.global_position.x, _pp[0].get_avg_current_sq() if _pp[0] else 0.0)
		l0 = _sol[0].get_inductance(bolt.global_position.x)
	if _pp.size() > 1 and _pp[1]:
		vc1 = _pp[1].get_voltage()
		i1  = _pp[1].get_rms_current()
		t1  = _pp[1].get_coil_temp_c()
	if _sol.size() > 1 and _sol[1]:
		f1 = _sol[1].get_force(bolt.global_position.x, _pp[1].get_avg_current_sq() if _pp[1] else 0.0)
		l1 = _sol[1].get_inductance(bolt.global_position.x)

	if _telem_graph and _telem_graph.has_method("push_sample"):
		_telem_graph.push_sample(vc0, i0, f0, vc1, i1, f1,
								 bolt.global_position.x, bolt.linear_velocity.x)

	if _recorder and _recorder.has_method("push_row"):
		_recorder.push_row(_sim_time, bolt.global_position.x, bolt.linear_velocity.x,
							vc0, i0, f0, l0, t0, vc1, i1, f1, l1, t1, ff, fd, fm)

## ── IR telemetry callbacks ────────────────────────────────────────────────────

func _on_telem_ir0_rear_broken()    -> void: _ir0_rear_blocked  = true
func _on_telem_ir0_rear_restored()  -> void: _ir0_rear_blocked  = false
func _on_telem_ir0_front_broken()   -> void: _ir0_front_blocked = true
func _on_telem_ir0_front_restored() -> void: _ir0_front_blocked = false
func _on_telem_ir1_trig_broken()    -> void: _ir1_trig_blocked  = true
func _on_telem_ir1_trig_restored()  -> void: _ir1_trig_blocked  = false
func _on_telem_ir1_front_broken()   -> void: _ir1_front_blocked = true
func _on_telem_ir1_front_restored() -> void: _ir1_front_blocked = false
