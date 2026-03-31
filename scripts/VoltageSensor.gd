extends Node

@export var label:         String = "VoltageSensor"
@export var max_voltage_v: float  = 60.0
@export var min_voltage_v: float  = -5.0
@export var noise_mv:      float  = 50.0

signal overvoltage(v: float)
signal undervoltage(v: float)

var _reading:    float = 0.0
var _fault_code: int   = 0

func sample(voltage: float) -> float:
	_reading = voltage + randf_range(-noise_mv * 0.001, noise_mv * 0.001)
	if _reading > max_voltage_v:
		if _fault_code != 1:
			_fault_code = 1
			overvoltage.emit(_reading)
	elif _reading < min_voltage_v:
		if _fault_code != -1:
			_fault_code = -1
			undervoltage.emit(_reading)
	else:
		_fault_code = 0
	return _reading

func get_reading() -> float: return _reading
func has_fault()   -> bool:  return _fault_code != 0
func clear_fault() -> void:  _fault_code = 0
