extends Node3D
class_name Battery

## 10s2p lithium-ion pack — 21700 format cells.
## 10 cells in series, 2 strings in parallel = 20 cells total.
##
## Samsung 50E / Molicel P42A class specs:
##   Capacity   : 4.5 Ah per cell  →  9.0 Ah pack
##   Max voltage: 4.20 V per cell  → 42.0 V pack
##   Nominal    : 3.60 V per cell  → 36.0 V pack
##   Cutoff     : 3.00 V per cell  → 30.0 V pack
##   ESR        : 25 mΩ per cell   → 125 mΩ pack  (10s / 2p)

@export var label:            String = "Battery"
@export var series:           int    = 10
@export var parallel:         int    = 2
@export var cell_capacity_ah: float  = 4.5
@export var cell_v_full:      float  = 4.20
@export var cell_v_nominal:   float  = 3.60
@export var cell_v_cutoff:    float  = 3.00
@export var cell_r_ohm:       float  = 0.025   ## ESR per cell [Ω]

## Derived pack values (computed in _ready)
var v_full:      float = 42.0
var v_nominal:   float = 36.0
var v_cutoff:    float = 30.0
var r_pack:      float = 0.125
var capacity_ah: float = 9.0

var _soc: float = 1.0   ## state of charge 0–1

signal low_battery(soc: float)
signal depleted

func _ready() -> void:
	v_full      = cell_v_full    * series
	v_nominal   = cell_v_nominal * series
	v_cutoff    = cell_v_cutoff  * series
	r_pack      = (cell_r_ohm * series) / float(parallel)
	capacity_ah = cell_capacity_ah * float(parallel)
	_build_visual()
	print("%s: %.1fV–%.1fV  R=%.4fΩ  %.1fAh" % [label, v_cutoff, v_full, r_pack, capacity_ah])

## ── OCV model ────────────────────────────────────────────────────────────────
## Piecewise linear Li-ion OCV approximation (3 segments)
func get_ocv() -> float:
	if _soc >= 0.9:
		return lerp(v_nominal * 1.03, v_full, (_soc - 0.9) / 0.1)
	elif _soc >= 0.2:
		return lerp(v_nominal * 0.97, v_nominal * 1.03, (_soc - 0.2) / 0.7)
	else:
		return lerp(v_cutoff, v_nominal * 0.97, _soc / 0.2)

## Terminal voltage under a given load current
func get_terminal_voltage(current_a: float) -> float:
	return get_ocv() - current_a * r_pack

## Draw current_a for dt seconds; returns terminal voltage
func draw(current_a: float, dt: float) -> float:
	if _soc <= 0.0: return v_cutoff
	_soc -= (current_a * dt / 3600.0) / capacity_ah
	_soc  = maxf(0.0, _soc)
	if _soc < 0.15 and _soc > 0.0: low_battery.emit(_soc)
	if _soc <= 0.0:                 depleted.emit()
	return get_terminal_voltage(current_a)

func get_soc()     -> float: return _soc
func get_voltage() -> float: return get_ocv()

## ── 3D visual (procedural) ───────────────────────────────────────────────────
const CELL_RADIUS := 0.0105   ## 21700: 21 mm diameter
const CELL_HEIGHT := 0.0700   ## 21700: 70 mm height
const CELL_GAP    := 0.0020   ## 2 mm gap between cells

func _build_visual() -> void:
	var cell_mesh := CylinderMesh.new()
	cell_mesh.top_radius      = CELL_RADIUS
	cell_mesh.bottom_radius   = CELL_RADIUS
	cell_mesh.height          = CELL_HEIGHT
	cell_mesh.radial_segments = 12

	var mat_body := StandardMaterial3D.new()
	mat_body.albedo_color = Color(0.18, 0.18, 0.20)   ## dark nickel wrap

	var mat_term := StandardMaterial3D.new()
	mat_term.albedo_color = Color(0.90, 0.80, 0.15)   ## gold positive terminal

	var step_x := CELL_RADIUS * 2.0 + CELL_GAP
	var step_z := CELL_RADIUS * 2.0 + CELL_GAP
	var ox     := -(series   - 1) * step_x * 0.5
	var oz     := -(parallel - 1) * step_z * 0.5

	for s in range(series):
		for p in range(parallel):
			## Cell body
			var mi := MeshInstance3D.new()
			mi.mesh = cell_mesh
			mi.set_surface_override_material(0, mat_body)
			mi.position = Vector3(ox + s * step_x, 0.0, oz + p * step_z)
			add_child(mi)
			## Positive terminal cap
			var cap_mesh := CylinderMesh.new()
			cap_mesh.top_radius      = CELL_RADIUS * 0.4
			cap_mesh.bottom_radius   = CELL_RADIUS * 0.4
			cap_mesh.height          = 0.002
			cap_mesh.radial_segments = 8
			var cap_mi := MeshInstance3D.new()
			cap_mi.mesh = cap_mesh
			cap_mi.set_surface_override_material(0, mat_term)
			cap_mi.position = Vector3(ox + s * step_x, CELL_HEIGHT * 0.5 + 0.001, oz + p * step_z)
			add_child(cap_mi)

	## Translucent housing shell
	var pack_w := series   * step_x + CELL_GAP * 2.0
	var pack_d := parallel * step_z + CELL_GAP * 2.0
	var pack_h := CELL_HEIGHT + 0.006
	var box    := BoxMesh.new()
	box.size   = Vector3(pack_w, pack_h, pack_d)
	var mat_shell := StandardMaterial3D.new()
	mat_shell.albedo_color = Color(0.05, 0.08, 0.15, 0.55)
	mat_shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var shell := MeshInstance3D.new()
	shell.mesh = box
	shell.set_surface_override_material(0, mat_shell)
	add_child(shell)
