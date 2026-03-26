extends Node
class_name TempSensor

## NTC thermistor simulation mounted on the solenoid coil. Child of PowerPack.
## MCU calls sample(temp_c) each physics tick.
##
## To swap for a real MCU: replace sample() body with a serial ADC + Steinhart-Hart read.
## Signal names and get_reading()/has_fault() stay identical.

@export var label:      String = "TempSensor"
@export var max_temp_c: float  = 85.0   ## fault threshold [°C]
@export var noise_c:    float  = 0.5    ## simulated sensor noise [°C]

signal overtemp(t: float)

var _reading: float = 20.0
var _faulted: bool  = false

func sample(temp_c: float) -> float:
	_reading = temp_c + randf_range(-noise_c, noise_c)
	if _reading > max_temp_c:
		if not _faulted:
			_faulted = true
			overtemp.emit(_reading)
			print("%s: OVERTEMP %.1f °C" % [label, _reading])
	else:
		_faulted = false
	return _reading

func get_reading() -> float: return _reading
func has_fault()   -> bool:  return _faulted
func clear_fault() -> void:  _faulted = false
