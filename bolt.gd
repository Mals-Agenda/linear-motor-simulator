extends RigidBody3D
class_name Bolt

## Digital twin of the crossbow bolt.
## Non-ferromagnetic carbon shaft with a ferromagnetic FerroNock at the rear.
## The FerroNock is the component attracted by each solenoid stage.

@export var shaft_mass_kg:     float = 0.045  ## Carbon/aluminium shaft
@export var ferronock_mass_kg: float = 0.005  ## Ferromagnetic nock insert

func _ready() -> void:
	mass = shaft_mass_kg + ferronock_mass_kg
	add_to_group("bolt")
