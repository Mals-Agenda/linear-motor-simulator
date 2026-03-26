extends Node3D
class_name PowerPack

## Capacitor bank with controlled switches and a DC-DC charger input.
##
## States:
##   Idle     — both switches off, cap at rest voltage
##   Charging — DC-DC converter ramping cap voltage toward target
##   Fire     — S1 (fire switch) → cap → solenoid RLC path
##   Drain    — S2 (drain switch) → cap → bleed resistor RC path
##
## Switch control is owned by MCU.  PowerPack is purely electrical/thermal.

@export var label:                String = "PowerPack"
@export var capacitance_f:        float  = 0.001
@export var initial_voltage_v:    float  = 50.0
@export var target_voltage_v:     float  = 50.0   ## charge-to voltage [V]
@export var resistance_ohm:       float  = 0.10    ## solenoid path series R [Ω]
@export var inductance_h:         float  = 0.001   ## solenoid inductance [H]
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

signal charge_complete

func _physics_process(delta: float) -> void:
	step(delta)

## ── Switch / charger control (called by MCU) ─────────────────────────────────

func begin_charge() -> void:
	_fire_switch  = false
	_drain_switch = false
	_charging     = true
	_voltage      = 0.0
	_current      = 0.0
	_coil_temp_c  = ambient_temp_c

func arm() -> void:
	## Instant-charge fallback (used when no charging sequence is needed)
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
		## Constant-power DC-DC converter model: I_cap = P / V_cap
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

	## ── Fire / freewheeling / drain  ─────────────────────────────────────────
	var dt:      float = delta / float(substeps)
	var sum_isq: float = 0.0

	for _i in range(substeps):
		if _fire_switch:
			## Symplectic Euler — stable RLC at any dt
			_voltage += (-_current / capacitance_f) * dt
			if _voltage <= 0.0:
				## Reverse-blocking diode clamps; transition to freewheeling.
				## Inductor current decays through R only (V = 0) until I → 0.
				_voltage = 0.0
				_current -= (_current * resistance_ohm) / inductance_h * dt
				if _current <= 1e-4:
					_current = 0.0; _fire_switch = false; break
			else:
				_current += (_voltage - _current * resistance_ohm) / inductance_h * dt
			sum_isq  += _current * _current
			var energy := 0.5 * inductance_h * _current * _current \
						+ 0.5 * capacitance_f * _voltage * _voltage
			if energy < 1e-6:
				_voltage = 0.0; _current = 0.0; _fire_switch = false; break

		else:  ## drain switch — RC discharge through bleed resistor
			_voltage += (-_voltage / (bleed_resistance_ohm * capacitance_f)) * dt
			_current  = _voltage / bleed_resistance_ohm
			sum_isq  += _current * _current
			if abs(_voltage) < 0.001:
				_voltage = 0.0; _current = 0.0; _drain_switch = false; break

	_avg_current_sq = sum_isq / float(substeps)

	## I²R heating + Newton cooling
	var p_heat: float = _avg_current_sq * resistance_ohm
	var p_cool: float = cooling_coeff_w_k * (_coil_temp_c - ambient_temp_c)
	_coil_temp_c += (p_heat - p_cool) / thermal_mass_j_k * delta

func _cool(delta: float) -> void:
	var p_cool: float = cooling_coeff_w_k * (_coil_temp_c - ambient_temp_c)
	_coil_temp_c -= p_cool / thermal_mass_j_k * delta
	_coil_temp_c  = maxf(_coil_temp_c, ambient_temp_c)

## ── Accessors ────────────────────────────────────────────────────────────────

func get_voltage()         -> float: return _voltage
func get_current()         -> float: return _current
func get_coil_temp_c()     -> float: return _coil_temp_c
func is_fire_active()      -> bool:  return _fire_switch
func is_drain_active()     -> bool:  return _drain_switch
func is_charging()         -> bool:  return _charging
func is_active()           -> bool:  return _fire_switch or _drain_switch or _charging
func get_avg_current_sq()  -> float: return _avg_current_sq
func get_rms_current()     -> float: return sqrt(_avg_current_sq)

func get_charge_fraction() -> float:
	if target_voltage_v <= 0.0: return 0.0
	return clamp(_voltage / target_voltage_v, 0.0, 1.0)
