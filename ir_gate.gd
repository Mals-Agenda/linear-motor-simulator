extends Area3D
class_name IRGate

@export var gate_label: String = "IRGate"

signal beam_broken
signal beam_restored

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("bolt"):
		beam_broken.emit()

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("bolt"):
		beam_restored.emit()
