extends Area3D

@export var gate_label: String = "IRGate"

@export_group("BOM — IR Emitter/Detector")
@export var emitter_digikey:   String = "475-1415-ND"
@export var emitter_mpn:       String = "SFH 4545"
@export var emitter_desc:      String = "IR LED 940nm, 5mm T-1 3/4"
@export var detector_digikey:  String = "751-1057-ND"
@export var detector_mpn:      String = "SFH 309 FA"
@export var detector_desc:     String = "IR Phototransistor 860nm, 5mm T-1 3/4"
@export var housing_desc:      String = "3D printed Nylon PA12 ring spacer, 28mm ID"

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
