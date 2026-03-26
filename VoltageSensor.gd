extends Node
class_name VoltageSensor

## ADC-backed capacitor voltage sensor. Designed as a child of PowerPack.
## MCU calls sample(voltage) each physics tick.
##
## To swap for a real MCU: replace sample() body with a serial ADC read.
## Signal names and get_reading()/has_fault() stay identical.

@export var label:         String = "VoltageSensor"
@export var max_voltage_v: float  = 60.0   ## overvoltage fault threshold
@export var min_voltage_v: float  = -5.0   ## undervoltage threshold (allows LC undershoot)
@export var noise_mv:      float  = 50.0   ## simulated ADC noise [mV]

signal overvoltage(v: float)
signal undervoltage(v: float)

var _reading:    float = 0.0
var _fault_code: int   = 0    ## 0=ok  1=over  -1=under

func sample(voltage: float) -> float:
	_reading = voltage + randf_range(-noise_mv * 0.001, noise_mv * 0.001)
	if _reading > max_voltage_v:
		if _fault_code != 1:
			_fault_code = 1
			overvoltage.emit(_reading)
			print("%s: OVERVOLTAGE %.2f V" % [label, _reading])
	elif _reading < min_voltage_v:
		if _fault_code != -1:
			_fault_code = -1
			undervoltage.emit(_reading)
			print("%s: UNDERVOLTAGE %.2f V" % [label, _reading])
	else:
		_fault_code = 0
	return _reading

func get_reading() -> float: return _reading
func has_fault()   -> bool:  return _fault_code != 0
func clear_fault() -> void:  _fault_code = 0
