extends Node

@export var label:      String = "TempSensor"
@export var max_temp_c: float  = 85.0
@export var noise_c:    float  = 0.5

signal overtemp(t: float)

var _reading: float = 20.0
var _faulted: bool  = false

func sample(temp_c: float) -> float:
	_reading = temp_c + randf_range(-noise_c, noise_c)
	if _reading > max_temp_c:
		if not _faulted:
			_faulted = true
			overtemp.emit(_reading)
	else:
		_faulted = false
	return _reading

func get_reading() -> float: return _reading
func has_fault()   -> bool:  return _faulted
func clear_fault() -> void:  _faulted = false
