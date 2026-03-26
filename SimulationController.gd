extends Node

# ── Node references ─────────────────────────────────────────────────────────
@onready var bolt:          RigidBody3D = $"../Bolt"
@onready var solenoid:      Node3D      = $"../Solenoid"
@onready var capacitor                  = $"../Capacitor"
@onready var magnet_hold:   Area3D      = $"../MagnetHold"
@onready var ir_gate_front: Area3D      = $"../Sensors/IRGateFront"
@onready var ir_gate_rear:  Area3D      = $"../Sensors/IRGateRear"

# ── Physics parameters ───────────────────────────────────────────────────────
## Maps solenoid current² to force:  F = force_constant · I²
## Units: N / A².  Calibrate against real hardware or FEA data.
@export var force_constant: float = 0.04
## Mass of the bolt in kg (synced to RigidBody3D at startup).
@export var bolt_mass_kg:   float = 0.05

# ── Internal state ───────────────────────────────────────────────────────────
var _center_x:   float = 1.5
var _energized:  bool  = false
var _cap_ok:     bool  = false   # true when capacitor script loaded correctly

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	if not bolt or not solenoid:
		push_error("SimulationController: Bolt or Solenoid node missing")
		return

	# Verify the Capacitor script is actually attached and callable
	_cap_ok = capacitor != null \
		and capacitor.has_method("charge") \
		and capacitor.has_method("step") \
		and capacitor.has_method("get_current")

	print("SimCtrl _ready  bolt=%s  solenoid=%s  capacitor=%s  cap_ok=%s" \
		% [bolt != null, solenoid != null, capacitor != null, _cap_ok])

	bolt.mass = bolt_mass_kg
	_center_x = solenoid.global_position.x
	fire()

	var cap_state: String = "n/a"
	if _cap_ok:
		cap_state = "active=%s  V=%.1f  I=%.3f" \
			% [capacitor.is_active(), capacitor.get_voltage(), capacitor.get_current()]
	print("SimCtrl after fire()  _energized=%s  _center_x=%.3f  cap=%s" \
		% [_energized, _center_x, cap_state])

func _physics_process(delta: float) -> void:
	if not bolt:
		return

	if _cap_ok:
		capacitor.step(delta)

	var x:  float = bolt.global_position.x
	var vx: float = bolt.linear_velocity.x
	var I:  float = capacitor.get_current() if _cap_ok else 100.0
	var Vc: float = capacitor.get_voltage() if _cap_ok else 50.0

	# De-energise at solenoid centre (prevents retarding force on exit)
	if _energized and x >= _center_x:
		_energized = false
		bolt.constant_force = Vector3.ZERO
		print("─── de-energised  x=%.3f m  vx=%.3f m/s ───" % [x, vx])
		return

	# Force ∝ I²  (solenoid pull on ferromagnetic core)
	var f:         float = force_constant * I * I if _energized else 0.0
	var f_friction: float = -0.15 * vx
	var f_drag:     float = -0.02 * vx * abs(vx)
	var f_total:    float = f + f_friction + f_drag
	bolt.constant_force = Vector3(f_total, 0.0, 0.0)

	print("x=%6.3f m  vx=%6.3f m/s  I=%7.3f A  Vc=%6.2f V  F=%6.3f N  Ff=%6.3f N  Fd=%6.3f N" \
		% [x, vx, I, Vc, f, f_friction, f_drag])

# ── Public API ───────────────────────────────────────────────────────────────

## Charge capacitor and reset bolt to the loading position, then fire.
func fire() -> void:
	if not bolt:
		return
	_energized = false
	bolt.constant_force  = Vector3.ZERO
	bolt.linear_velocity = Vector3.ZERO
	bolt.global_position = Vector3(_center_x - 0.45, 0.0, 0.0)
	if _cap_ok:
		capacitor.charge()
	_energized = true

func update_electrical(_delta: float, _pwm: float) -> void:
	pass

func update_thermal(_delta: float) -> void:
	pass

func get_pwm_from_mcu() -> float:
	return 1.0 if _energized else 0.0

# ── IR gate callbacks ────────────────────────────────────────────────────────
func _on_ir_gate_front_beam_broken()   -> void: print("IRGateFront ── BROKEN")
func _on_ir_gate_front_beam_restored() -> void: print("IRGateFront ── restored")
func _on_ir_gate_rear_beam_broken()    -> void: print("IRGateRear  ── BROKEN")
func _on_ir_gate_rear_beam_restored()  -> void: print("IRGateRear  ── restored")
