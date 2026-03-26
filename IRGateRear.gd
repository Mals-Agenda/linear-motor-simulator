extends Area3D

signal beam_broken
signal beam_restored

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.name == "Bolt":
		beam_broken.emit()

func _on_body_exited(body: Node3D) -> void:
	if body.name == "Bolt":
		beam_restored.emit()
