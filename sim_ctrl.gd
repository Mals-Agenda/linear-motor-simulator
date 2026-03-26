extends Node

## Physics controller — applies forces to the bolt each frame.
## Electrical sequencing delegated to MCU; de-energise at solenoid centres is physics.

@onready var bolt:        RigidBody3D = $"../Bolt"
@onready var solenoid0                = $"../Solenoid0"
@onready var solenoid1                = $"../Solenoid1"
@onready var power_pack0              = $"../PowerPack0"
@onready var power_pack1              = $"../PowerPack1"
@onready var breach_door              = $"../BreachDoor"
@onready var mcu                      = $"../MCU"

@export var friction_coeff:   float = 0.15
@export var drag_coeff:       float = 0.02
@export var bolt_load_offset: float = 0.30   ## metres behind solenoid0 centre
@export var ferronock_offset: float = 0.37   ## metres bolt-centre to ferronock
@export var barrel_start_x:   float = 0.00
@export var barrel_end_x:     float = 2.50

var _center_x0:    float = 0.75
var _center_x1:    float = 1.75
var _deenergised0: bool  = false
var _deenergised1: bool  = false
var _pp0_ok:       bool  = false
var _pp1_ok:       bool  = false
var _breach_ok:    bool  = false
var _mcu_ok:       bool  = false

## ── Telemetry state ──────────────────────────────────────────────────────────
var _sim_time:          float = 0.0
var _ir0_rear_blocked:  bool  = false
var _ir0_front_blocked: bool  = false
var _ir1_trig_blocked:  bool  = false
var _ir1_front_blocked: bool  = false

func _ready() -> void:
	if not bolt:
		push_error("SimCtrl: Bolt node missing"); return
	_pp0_ok    = power_pack0 != null and power_pack0.has_method("is_fire_active")
	_pp1_ok    = power_pack1 != null and power_pack1.has_method("is_fire_active")
	_breach_ok = breach_door != null and breach_door.has_method("get_magnet_force")
	_mcu_ok    = mcu         != null and mcu.has_method("fire_stage")
	if solenoid0: _center_x0 = solenoid0.global_position.x
	if solenoid1: _center_x1 = solenoid1.global_position.x

	_connect_ir("../IRGate0Rear",    _on_telem_ir0_rear_broken,    _on_telem_ir0_rear_restored)
	_connect_ir("../IRGate0Front",   _on_telem_ir0_front_broken,   _on_telem_ir0_front_restored)
	_connect_ir("../IRGate1Trigger", _on_telem_ir1_trig_broken,    _on_telem_ir1_trig_restored)
	_connect_ir("../IRGate1Front",   _on_telem_ir1_front_broken,   _on_telem_ir1_front_restored)

	print("SimCtrl _ready  pp0=%s  pp1=%s  breach=%s  mcu=%s  cx0=%.3f  cx1=%.3f" \
		% [_pp0_ok, _pp1_ok, _breach_ok, _mcu_ok, _center_x0, _center_x1])
	print("SimCtrl: waiting for ARM command")

func _connect_ir(path: String, broken_cb: Callable, restored_cb: Callable) -> void:
	var n := get_node_or_null(path) as Area3D
	if n:
		n.beam_broken.connect(broken_cb)
		n.beam_restored.connect(restored_cb)

func _physics_process(delta: float) -> void:
	if not bolt: return
	_sim_time += delta

	var x:  float = bolt.global_position.x
	var vx: float = bolt.linear_velocity.x
	var en0: bool = _pp0_ok and power_pack0.is_fire_active()
	var en1: bool = _pp1_ok and power_pack1.is_fire_active()

	## De-energise each stage when bolt centre passes its solenoid centre
	if en0 and not _deenergised0 and x >= _center_x0:
		_deenergised0 = true
		power_pack0.safe()
		print("EVENT: S0 de-energised  t=%.4f  x=%.3f  v=%.3f" % [_sim_time, x, vx])

	if en1 and not _deenergised1 and x >= _center_x1:
		_deenergised1 = true
		power_pack1.safe()
		print("EVENT: S1 de-energised  t=%.4f  x=%.3f  v=%.3f" % [_sim_time, x, vx])

	var isq0: float = power_pack0.get_avg_current_sq() if _pp0_ok else 0.0
	var isq1: float = power_pack1.get_avg_current_sq() if _pp1_ok else 0.0
	var I0:   float = sqrt(isq0)
	var I1:   float = sqrt(isq1)
	var Vc0:  float = power_pack0.get_voltage() if _pp0_ok else 0.0
	var Vc1:  float = power_pack1.get_voltage() if _pp1_ok else 0.0
	var T0:   float = power_pack0.get_coil_temp_c() if _pp0_ok else 0.0
	var T1:   float = power_pack1.get_coil_temp_c() if _pp1_ok else 0.0

	var f_s0: float = solenoid0.get_force_from_isq(isq0) if solenoid0 else 0.0
	var f_s1: float = solenoid1.get_force_from_isq(isq1) if solenoid1 else 0.0

	var in_barrel:   bool  = x > barrel_start_x and x < barrel_end_x
	var f_friction:  float = -friction_coeff * vx if in_barrel else 0.0
	var f_drag:      float = -drag_coeff * vx * abs(vx)
	var ferronock_x: float = x - ferronock_offset
	var f_magnet:    float = breach_door.get_magnet_force(ferronock_x) if _breach_ok else 0.0
	var f_total:     float = f_s0 + f_s1 + f_friction + f_drag + f_magnet
	bolt.constant_force = Vector3(f_total, 0.0, 0.0)

	print(_build_telemetry(x, vx, f_s0, f_s1, f_drag, f_friction, f_magnet,
		Vc0, I0, T0, Vc1, I1, T1, en0, en1))

## ── Public interface ─────────────────────────────────────────────────────────

func reset_bolt() -> void:
	## Reset bolt to loaded position; called by MCU before firing
	if not bolt: return
	_deenergised0 = false
	_deenergised1 = false
	_sim_time     = 0.0
	bolt.constant_force  = Vector3.ZERO
	bolt.linear_velocity = Vector3.ZERO
	bolt.global_position = Vector3(_center_x0 - bolt_load_offset, 0.0, 0.0)

func fire() -> void:
	## Legacy wrapper: reset bolt then fire through MCU (or direct if no MCU)
	reset_bolt()
	if _mcu_ok:
		mcu.fire_stage(0)
	elif _pp0_ok:
		power_pack0.arm()
		power_pack0.fire()

## ── Helper getters ───────────────────────────────────────────────────────────

func get_bolt_euler_deg() -> Vector3:
	return bolt.rotation_degrees if bolt else Vector3.ZERO

func get_bolt_omega() -> Vector3:
	return bolt.angular_velocity if bolt else Vector3.ZERO

func get_ir_states() -> Array:
	return [_ir0_rear_blocked, _ir0_front_blocked, _ir1_trig_blocked, _ir1_front_blocked]

func get_pwm_from_mcu() -> float:
	var e0: float = 1.0 if (_pp0_ok and power_pack0.is_fire_active()) else 0.0
	var e1: float = 1.0 if (_pp1_ok and power_pack1.is_fire_active()) else 0.0
	return max(e0, e1)

## ── Telemetry builder ────────────────────────────────────────────────────────

func _build_telemetry(
		x: float, vx: float,
		f_s0: float, f_s1: float, f_drag: float, f_fric: float, f_mag: float,
		vc0: float, i0: float, t0: float,
		vc1: float, i1: float, t1: float,
		en0: bool, en1: bool) -> String:
	var euler := get_bolt_euler_deg()
	var omega := get_bolt_omega()
	return (
		"t=%.4f, x=%.4f, v=%.4f, " +
		"yaw=%.2f, pitch=%.2f, roll=%.2f, " +
		"wx=%.2f, wy=%.2f, wz=%.2f, " +
		"Fx0=%.3f, Fx1=%.3f, Fd=%.3f, Ff=%.3f, Fm=%.3f, Fc=0.000, " +
		"Vc0=%.2f, I0=%.3f, T0=%.1f, " +
		"Vc1=%.2f, I1=%.3f, T1=%.1f, " +
		"S0=%s, S1=%s, " +
		"IR0r=%s, IR0f=%s, IR1t=%s, IR1f=%s"
	) % [
		_sim_time, x, vx,
		euler.y, euler.x, euler.z,
		omega.x, omega.y, omega.z,
		f_s0, f_s1, f_drag, f_fric, f_mag,
		vc0, i0, t0,
		vc1, i1, t1,
		"ON"  if en0 else "OFF",
		"ON"  if en1 else "OFF",
		"T" if _ir0_rear_blocked  else "F",
		"T" if _ir0_front_blocked else "F",
		"T" if _ir1_trig_blocked  else "F",
		"T" if _ir1_front_blocked else "F"
	]

## ── IR gate telemetry callbacks ──────────────────────────────────────────────

func _on_telem_ir0_rear_broken()    -> void: _ir0_rear_blocked  = true
func _on_telem_ir0_rear_restored()  -> void: _ir0_rear_blocked  = false
func _on_telem_ir0_front_broken()   -> void: _ir0_front_blocked = true
func _on_telem_ir0_front_restored() -> void: _ir0_front_blocked = false
func _on_telem_ir1_trig_broken()    -> void: _ir1_trig_blocked  = true
func _on_telem_ir1_trig_restored()  -> void: _ir1_trig_blocked  = false
func _on_telem_ir1_front_broken()   -> void: _ir1_front_blocked = true
func _on_telem_ir1_front_restored() -> void: _ir1_front_blocked = false
