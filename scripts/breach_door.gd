extends StaticBody3D

@export_group("BOM — Holding Magnet")
@export var magnet_desc:        String = "N52 Neodymium disc 20mm x 5mm, axially magnetized"
@export var magnet_digikey:     String = ""  ## magnets typically sourced from K&J Magnetics

@export_group("Physics")
@export var magnet_hold_force_n: float = 15.0
@export var decay_m:             float = 0.10

var breach_x: float = 0.0

func _ready() -> void:
	breach_x = global_position.x

func get_magnet_force(ferronock_x: float) -> float:
	var dist: float = max(0.0, ferronock_x - breach_x)
	return -magnet_hold_force_n * exp(-dist / decay_m)
