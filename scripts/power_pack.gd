extends Node3D

## Capacitor bank with controlled switches, DC-DC charger, and back-EMF coupling.
##
## Back-EMF coupling:
##   SimCtrl calls set_bolt_state(ferronock_x, bolt_vx, solenoid) each frame.
##   During Fire the circuit equation becomes:
##     L(x)·dI/dt = V_cap − I·R − I·(dL/dx)·vx
##   where L(x) and dL/dx come from the paired Solenoid node, evaluated at
##   ferronock_x.

@export var label:                String = "PowerPack"

## ── Bill of Materials ────────────────────────────────────────────────────────
@export_group("BOM — Capacitor")
@export var cap_digikey:       String = "493-14542-ND"
@export var cap_manufacturer:  String = "Nichicon"
@export var cap_mpn:           String = "UBY2D102MHD"
@export var cap_desc:          String = "1000uF 200V Aluminum Electrolytic Snap-in"
@export var cap_diameter_mm:   float  = 30.0   ## package diameter
@export var cap_height_mm:     float  = 45.0   ## package height

@export_group("BOM — Discharge MOSFET")
@export var mosfet_digikey:    String = "IRFP4668PBF-ND"
@export var mosfet_manufacturer: String = "Infineon"
@export var mosfet_mpn:        String = "IRFP4668PBF"
@export var mosfet_desc:       String = "N-Ch 200V 130A TO-247AC"
@export var mosfet_w_mm:       float  = 15.75
@export var mosfet_h_mm:       float  = 20.80
@export var mosfet_d_mm:       float  = 5.31

@export_group("BOM — Bleed Resistor")
@export var bleed_digikey:     String = "825F10R0-ND"
@export var bleed_manufacturer: String = "Ohmite"
@export var bleed_mpn:         String = "825F10R0"
@export var bleed_desc:        String = "10 Ohm 25W Wirewound Axial"
@export var bleed_diameter_mm: float  = 12.7
@export var bleed_length_mm:   float  = 50.8

@export_group("BOM — Boost Converter")
@export var boost_digikey:     String = "LT3757EMSE#PBF-ND"
@export var boost_manufacturer: String = "Analog Devices"
@export var boost_mpn:         String = "LT3757EMSE#PBF"
@export var boost_desc:        String = "Boost/Flyback DC-DC Controller MSOP-10 (on custom PCB)"
@export var boost_pcb_w_mm:    float  = 40.0
@export var boost_pcb_h_mm:    float  = 25.0
@export var boost_pcb_d_mm:    float  = 15.0  ## includes inductor height

@export_group("BOM — Gate Driver")
@export var gdrv_digikey:      String = "IR2110-ND"
@export var gdrv_manufacturer: String = "Infineon"
@export var gdrv_mpn:          String = "IR2110"
@export var gdrv_desc:         String = "Half-Bridge Gate Driver DIP-14"

@export_group("Electrical")
## ── Real-component values ─────────────────────────────────────────────────────
@export var capacitance_f:        float  = 0.001   ## 1000 µF [F]
@export var initial_voltage_v:    float  = 50.0
@export var target_voltage_v:     float  = 50.0
@export var resistance_ohm:       float  = 0.50    ## coil 0.42 Ω + ESR 0.08 Ω [Ω]
@export var bleed_resistance_ohm: float  = 10.0    ## bleed resistor [Ω]
@export var substeps:             int    = 32

@export var charge_power_w:       float  = 30.0    ## 30 W boost converter [W]

@export var thermal_mass_j_k:     float  = 12.0    ## inner winding thermal mass [J/K]
@export var cooling_coeff_w_k:    float  = 0.8     ## natural convection + fins [W/K]
@export var ambient_temp_c:       float  = 20.0

var _voltage:        float = 0.0
var _current:        float = 0.0
var _avg_current_sq: float = 0.0
var _fire_switch:    bool  = false
var _drain_switch:   bool  = false
var _charging:       bool  = false
var _coil_temp_c:    float = 20.0

## Back-EMF coupling — updated by SimCtrl every physics frame
var _bolt_x:   float = 0.0   ## ferronock world position
var _bolt_vx:  float = 0.0
var _solenoid: Node  = null

signal charge_complete

## step() is now driven externally by SimCtrl (called after MCU fires stages and
## after set_bolt_state, so the correct bolt position and fire-switch state are
## both visible in the same frame).  _physics_process is intentionally removed.

func set_bolt_state(bolt_x: float, bolt_vx: float, solenoid: Node) -> void:
	_bolt_x   = bolt_x
	_bolt_vx  = bolt_vx
	_solenoid = solenoid

## ── Switch / charger control ──────────────────────────────────────────────────

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
	_fire_switch    = false
	_drain_switch   = false
	_charging       = false
	_current        = 0.0
	_avg_current_sq = 0.0

## ── Simulation step ──────────────────────────────────────────────────────────

func step(delta: float) -> void:
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

	if not _fire_switch and not _drain_switch:
		_avg_current_sq = 0.0
		_cool(delta)
		return

	var dt:      float = delta / float(substeps)
	var sum_isq: float = 0.0

	for _i in range(substeps):
		if _fire_switch:
			var L:      float = _get_inductance()
			var dl_dx:  float = _get_dl_dx()
			var v_back: float = _current * dl_dx * _bolt_vx

			_voltage += (-_current / capacitance_f) * dt

			if _voltage <= 0.0:
				_voltage  = 0.0
				_current -= (_current * resistance_ohm) / L * dt
				if _current <= 1e-4:
					_current = 0.0; _fire_switch = false; break
			else:
				_current += (_voltage - _current * resistance_ohm - v_back) / L * dt

			sum_isq += _current * _current

			if 0.5 * L * _current * _current + \
			   0.5 * capacitance_f * _voltage * _voltage < 1e-6:
				_voltage = 0.0; _current = 0.0; _fire_switch = false; break

		else:
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

func _get_inductance() -> float:
	if _solenoid and _solenoid.has_method("get_inductance"):
		return _solenoid.get_inductance(_bolt_x)
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
