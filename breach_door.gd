extends StaticBody3D
class_name BreachDoor

@export var magnet_hold_force_n: float = 15.0
@export var decay_m:             float = 0.10

var breach_x: float = 0.0

func _ready() -> void:
	breach_x = global_position.x

func get_magnet_force(ferronock_x: float) -> float:
	var dist: float = max(0.0, ferronock_x - breach_x)
	return -magnet_hold_force_n * exp(-dist / decay_m)
