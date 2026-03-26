extends Node3D
class_name Solenoid

@export var label:          String = "Solenoid"
@export var force_constant: float  = 0.04  ## N/A²

var center_x: float = 0.0

func _ready() -> void:
	center_x = global_position.x

func get_force(current_a: float) -> float:
	return force_constant * current_a * current_a

func get_force_from_isq(current_sq: float) -> float:
	return force_constant * current_sq
