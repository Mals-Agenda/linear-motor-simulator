extends Node3D
class_name PowerPack

## Capacitor bank with controlled switches, DC-DC charger, and back-EMF coupling.
##
## States:
##   Idle     — both switches off, cap at rest voltage
##   Charging — DC-DC converter ramping cap voltage toward target
##   Fire     — S1 (fire switch) → cap → solenoid RLC path
##   Drain    — S2 (drain switch) → cap → bleed resistor RC path
##
## Back-EMF coupling:
##   SimCtrl calls set_bolt_state(bolt_x, bolt_vx) each physics frame.
##   During Fire the circuit equation becomes:
##     L(x)·dI/dt = V_cap − I·R − I·(dL/dx)·vx
##   where L(x) and dL/dx come from the paired Solenoid node.
##   This correctly models energy exchange between electrical and kinetic domains.
##
## Switch control is owned by MCU.  PowerPack is purely electrical/thermal.

@export var label:                String = "PowerPack"
@export var capacitance_f:        float  = 0.001
@export var initial_voltage_v:    float  = 50.0
@export var target_voltage_v:     float  = 50.0   ## charge-to voltage [V]
@export var resistance_ohm:       float  = 0.10    ## solenoid path series R [Ω]
@export var bleed_resistance_ohm: float  = 10.0    ## bleed/dump resistor [Ω]
@export var substeps:             int    = 32

## DC-DC charger
@export var charge_power_w:       float  = 2.0     ## converter output power [W]

## Thermal model
@export var thermal_mass_j_k:     float  = 8.0
@export var cooling_coeff_w_k:    float  = 0.5
@export var ambient_temp_c:       float  = 20.0

var _voltage:        float = 0.0
var _current:        float = 0.0
var _avg_current_sq: float = 0.0
var _fire_switch:    bool  = false
var _drain_switch:   bool  = false
var _charging:       bool  = false
var _coil_temp_c:    float = 20.0

## Back-EMF coupling — set each frame by SimCtrl
var _bolt_x:        float = 0.0
var _bolt_vx:       float = 0.0
var _solenoid:      Node  = null   ## typed Solenoid, stored as Node to avoid circular dep

signal charge_complete

func _physics_process(delta: float) -> void:
	step(delta)

## ── Bolt-state coupling (called by SimCtrl every physics frame) ───────────────

func set_bolt_state(bolt_x: float, bolt_vx: float, solenoid: Node) -> void:
	_bolt_x   = bolt_x
	_bolt_vx  = bolt_vx
	_solenoid = solenoid

## ── Switch / charger control (called by MCU) ─────────────────────────────────

func begin_charge() -> void:
	_fire_switch  = false
	_drain_switch = false
	_charging     = true
	_voltage      = 0.0
	_current      = 0.0
	_coil_temp_c  = ambient_temp_c

func arm() -> void:
	_voltage      = initial_voltage_v
	_current      = 0.0
	_fire_switch  = false
	_drain_switch = false
	_charging     = false

func fire() -> void:
	_drain_switch = false
	_fire_switch  = true
	_charging     = false

func drain() -> void:
	_fire_switch  = false
	_drain_switch = true
	_charging     = false

func safe() -> void:
	_fire_switch  = false
	_drain_switch = false
	_charging     = false

## ── Simulation step ──────────────────────────────────────────────────────────

func step(delta: float) -> void:
	## ── Charging mode ────────────────────────────────────────────────────────
	if _charging:
		var i_in: float = charge_power_w / maxf(_voltage, 1.0)
		_voltage       += i_in / capacitance_f * delta
		_avg_current_sq = i_in * i_in
		if _voltage >= target_voltage_v:
			_voltage        = target_voltage_v
			_avg_current_sq = 0.0
			_charging       = false
			charge_complete.emit()
		_cool(delta)
		return

	## ── Idle ─────────────────────────────────────────────────────────────────
	if not _fire_switch and not _drain_switch:
		_avg_current_sq = 0.0
		_cool(delta)
		return

	## ── Fire / freewheeling / drain ──────────────────────────────────────────
	var dt:      float = delta / float(substeps)
	var sum_isq: float = 0.0

	for _i in range(substeps):
		if _fire_switch:
			## Get position-dependent inductance and dL/dx from paired solenoid.
			## Falls back to export value if solenoid not yet set.
			var L:     float = _get_inductance()
			var dl_dx: float = _get_dl_dx()

			## Back-EMF from bolt motion: V_back = I · (dL/dx) · vx
			var v_back: float = _current * dl_dx * _bolt_vx

			## Symplectic Euler — V update then I update keeps energy stable
			_voltage += (-_current / capacitance_f) * dt

			if _voltage <= 0.0:
				## Reverse-blocking diode clamps; freewheeling decay through R
				_voltage  = 0.0
				_current -= (_current * resistance_ohm) / L * dt
				if _current <= 1e-4:
					_current = 0.0; _fire_switch = false; break
			else:
				_current += (_voltage - _current * resistance_ohm - v_back) / L * dt

			sum_isq += _current * _current

			if 0.5 * L * _current * _current + 0.5 * capacitance_f * _voltage * _voltage < 1e-6:
				_voltage = 0.0; _current = 0.0; _fire_switch = false; break

		else:  ## drain — RC through bleed resistor
			_voltage += (-_voltage / (bleed_resistance_ohm * capacitance_f)) * dt
			_current  = _voltage / bleed_resistance_ohm
			sum_isq  += _current * _current
			if abs(_voltage) < 0.001:
				_voltage = 0.0; _current = 0.0; _drain_switch = false; break

	_avg_current_sq = sum_isq / float(substeps)

	var p_heat: float = _avg_current_sq * resistance_ohm
	var p_cool: float = cooling_coeff_w_k * (_coil_temp_c - ambient_temp_c)
	_coil_temp_c += (p_heat - p_cool) / thermal_mass_j_k * delta

func _cool(delta: float) -> void:
	var p_cool: float = cooling_coeff_w_k * (_coil_temp_c - ambient_temp_c)
	_coil_temp_c -= p_cool / thermal_mass_j_k * delta
	_coil_temp_c  = maxf(_coil_temp_c, ambient_temp_c)

## ── Solenoid coupling helpers ─────────────────────────────────────────────────

func _get_inductance() -> float:
	if _solenoid and _solenoid.has_method("get_inductance"):
		return _solenoid.get_inductance(_bolt_x)
	## Fallback: estimate from export; not ideal but prevents crash
	return 0.001

func _get_dl_dx() -> float:
	if _solenoid and _solenoid.has_method("get_dl_dx"):
		return _solenoid.get_dl_dx(_bolt_x)
	return 0.0

## ── Accessors ────────────────────────────────────────────────────────────────

func get_voltage()        -> float: return _voltage
func get_current()        -> float: return _current
func get_coil_temp_c()    -> float: return _coil_temp_c
func is_fire_active()     -> bool:  return _fire_switch
func is_drain_active()    -> bool:  return _drain_switch
func is_charging()        -> bool:  return _charging
func is_active()          -> bool:  return _fire_switch or _drain_switch or _charging
func get_avg_current_sq() -> float: return _avg_current_sq
func get_rms_current()    -> float: return sqrt(_avg_current_sq)

func get_charge_fraction() -> float:
	if target_voltage_v <= 0.0: return 0.0
	return clamp(_voltage / target_voltage_v, 0.0, 1.0)
