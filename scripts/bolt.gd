extends RigidBody3D

## Digital twin of the crossbow bolt.
## Non-ferromagnetic carbon shaft with a ferromagnetic FerroNock at the rear.
## The FerroNock is the component attracted by each solenoid stage.
## SimCtrl computes ferronock_x = global_position.x - ferronock_offset (0.37 m).

@export_group("BOM — Shaft")
@export var shaft_desc:        String = "Carbon fiber crossbow bolt shaft, 20in, 300 spine"
@export var shaft_mass_kg:     float  = 0.045

@export_group("BOM — FerroNock")
@export var ferronock_desc:    String = "1018 mild steel press-fit nock, 8mm OD x 60mm"
@export var ferronock_mass_kg: float  = 0.005

func _ready() -> void:
	mass = shaft_mass_kg + ferronock_mass_kg
	add_to_group("bolt")
