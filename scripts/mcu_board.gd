extends Node3D

## Physical MCU board — ESP32-S3-DevKitC-1
## This is purely visual; sequencing logic lives in mcu.gd.

@export var label: String = "MCU Board"

@export_group("BOM — MCU Board")
@export var board_digikey:      String = "1965-ESP32S3DEVKITC1N8R8-ND"
@export var board_manufacturer: String = "Espressif"
@export var board_mpn:          String = "ESP32-S3-DevKitC-1-N8R8"
@export var board_desc:         String = "ESP32-S3 Dev Board, 8MB Flash, 8MB PSRAM"
@export var board_w_mm:         float  = 69.0
@export var board_h_mm:         float  = 25.5
@export var board_d_mm:         float  = 3.0   ## PCB thickness (without components)

func _ready() -> void:
	_build_visual()

func _build_visual() -> void:
	var w: float = board_w_mm * 0.001
	var h: float = board_h_mm * 0.001
	var d: float = board_d_mm * 0.001

	## PCB
	var pcb := CSGBox3D.new()
	pcb.size = Vector3(w, d, h)
	var pcb_mat := StandardMaterial3D.new()
	pcb_mat.albedo_color = Color(0.02, 0.30, 0.08)
	pcb.material = pcb_mat
	pcb.name = "PCB"
	add_child(pcb)

	## ESP32-S3 module (metal shield)
	var module := CSGBox3D.new()
	module.size = Vector3(0.018, 0.003, 0.018)
	module.position = Vector3(0.010, d * 0.5 + 0.0015, 0.0)
	var mod_mat := StandardMaterial3D.new()
	mod_mat.albedo_color = Color(0.72, 0.72, 0.74)
	mod_mat.metallic = 0.7
	module.material = mod_mat
	module.name = "ESP32Module"
	add_child(module)

	## USB-C connector
	var usb := CSGBox3D.new()
	usb.size = Vector3(0.009, 0.003, 0.007)
	usb.position = Vector3(-w * 0.5 + 0.005, d * 0.5 + 0.0015, 0.0)
	var usb_mat := StandardMaterial3D.new()
	usb_mat.albedo_color = Color(0.65, 0.65, 0.67)
	usb_mat.metallic = 0.9
	usb.material = usb_mat
	usb.name = "USB_C"
	add_child(usb)

	## Pin headers (two rows of through-hole pins along length)
	for side in [-1, 1]:
		var pins := CSGBox3D.new()
		pins.size = Vector3(w * 0.85, 0.008, 0.0025)
		pins.position = Vector3(0.003, -0.003, side * (h * 0.5 - 0.002))
		var pin_mat := StandardMaterial3D.new()
		pin_mat.albedo_color = Color(0.20, 0.20, 0.22)
		pins.material = pin_mat
		pins.name = "PinHeader_%d" % [side]
		add_child(pins)
