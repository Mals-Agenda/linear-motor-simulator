extends Node3D
class_name Capacitor

## Capacitance in Farads  (1000 µF = 0.001 F)
@export var capacitance_f:     float = 0.001
## Pre-charge voltage
@export var initial_voltage_v: float = 50.0
## Total series resistance in Ohms
@export var resistance_ohm:    float = 0.10
## Solenoid inductance in Henries  (1 mH = 0.001 H)
@export var inductance_h:      float = 0.001
## Euler sub-steps per physics frame
@export var substeps:          int   = 32

var _voltage: float = 0.0
var _current: float = 0.0
var _active:  bool  = false

func charge() -> void:
	_voltage = initial_voltage_v
	_current = 0.0
	_active  = true

func step(delta: float) -> void:
	if not _active:
		return
	var dt: float = delta / float(substeps)
	for _i in range(substeps):
		# Symplectic (semi-implicit) Euler — stable for any dt on LC circuits.
		# Update V with old I first, then I with the new V.
		_voltage += (-_current / capacitance_f) * dt
		_current += (_voltage - _current * resistance_ohm) / inductance_h * dt
		# Stop only when circuit energy is fully dissipated, not on first
		# negative half-cycle (LC oscillation makes both go negative briefly).
		var energy := 0.5 * inductance_h * _current * _current \
					+ 0.5 * capacitance_f * _voltage * _voltage
		if energy < 1e-6:
			_voltage = 0.0
			_current = 0.0
			_active  = false
			break

func get_voltage() -> float:
	return _voltage

func get_current() -> float:
	return _current

func is_active() -> bool:
	return _active
