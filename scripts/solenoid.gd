extends Node3D

## Position-dependent solenoid model.
##
## Physics model — sech² inductance profile:
##   ξ = (bolt_x - center_x) / coil_half_length
##   L(ξ) = L_air + (L_core - L_air) / cosh²(ξ · sharpness)
##
## NOTE: bolt_x passed to all methods should be the FERRONOCK position,
##       not the bolt centre.  SimCtrl handles this conversion.
##
## Properties:
##   • L is maximum at ξ=0 (ferronock centred in coil)
##   • L → L_air as ferronock moves away
##   • dL/dx > 0 for ξ < 0  → attractive (forward) force
##   • dL/dx < 0 for ξ > 0  → braking; MCU de-energises at ξ=0
##   • Force  F = ½ · I² · dL/dx

@export var label:             String = "Solenoid"

@export_group("BOM — Magnet Wire")
@export var wire_digikey:      String = ""     ## bulk spool; order by weight
@export var wire_manufacturer: String = "Remington Industries"
@export var wire_mpn:          String = "14SNS"
@export var wire_desc:         String = "14 AWG Magnet Wire, Polyimide, 10 lb spool"
@export var wire_gauge_awg:    int    = 14     ## 1.628 mm bare diameter
@export var wire_turns:        int    = 600
@export var bore_diameter_m:   float  = 0.030  ## inner bore [m]

@export_group("BOM — Bobbin")
@export var bobbin_desc:       String = "3D printed Nylon PA12, 30mm bore x 300mm long"

@export_group("Inductance Model")
@export var coil_length:       float  = 0.30   ## physical coil length [m]
@export var inductance_air_h:  float  = 0.001  ## L — no ferromagnetic core [H]
@export var inductance_core_h: float  = 0.008  ## L — ferronock fully centred [H]
@export var sharpness:         float  = 1.5    ## profile width (higher = sharper peak)

var center_x:   float = 0.0
var coil_od_m:  float = 0.0  ## computed outer diameter [m]

var _dl_range:  float = 0.0
var _coil_half: float = 0.0

## AWG bare wire diameters in mm (common gauges)
const _AWG_DIA_MM := {
	10: 2.588, 12: 2.053, 14: 1.628, 16: 1.291, 18: 1.024, 20: 0.812, 22: 0.644
}

func _ready() -> void:
	center_x   = global_position.x
	_dl_range  = inductance_core_h - inductance_air_h
	_coil_half = coil_length * 0.5
	_compute_coil_od()
	_rebuild_visual()

func _compute_coil_od() -> void:
	var wire_dia_mm: float = _AWG_DIA_MM.get(wire_gauge_awg, 1.628)
	var wire_dia_m:  float = wire_dia_mm * 0.001
	## With enamel insulation add ~8%
	var insulated_dia_m: float = wire_dia_m * 1.08
	var turns_per_layer: int = int(coil_length / insulated_dia_m)
	if turns_per_layer < 1: turns_per_layer = 1
	var layers: float = float(wire_turns) / float(turns_per_layer)
	var buildup_m: float = layers * insulated_dia_m
	coil_od_m = bore_diameter_m + 2.0 * buildup_m

func _rebuild_visual() -> void:
	var coil_node: Node = get_node_or_null("Coil")
	if not coil_node: return
	## Update collision shape
	var cs: CollisionShape3D = coil_node.get_node_or_null("CollisionShape3D")
	if cs and cs.shape is CylinderShape3D:
		cs.shape.radius = coil_od_m * 0.5
		cs.shape.height = coil_length
	## Update CSG outer cylinder
	var combiner: Node = coil_node.get_node_or_null("CSGCombiner3D")
	if not combiner: return
	var outer: CSGCylinder3D = combiner.get_node_or_null("Outer")
	if outer:
		outer.radius = coil_od_m * 0.5
		outer.height = coil_length
	var bore: CSGCylinder3D = combiner.get_node_or_null("Bore")
	if bore:
		bore.radius = bore_diameter_m * 0.5
		bore.height = coil_length + 0.01  ## slightly longer for clean subtraction

## Normalised position ξ.  ξ=0 at coil centre; negative = ferronock approaching.
func _xi(bolt_x: float) -> float:
	return (bolt_x - center_x) / _coil_half

## Inductance at ferronock position [H]
func get_inductance(bolt_x: float) -> float:
	var u:  float = _xi(bolt_x) * sharpness
	var ch: float = cosh(u)
	return inductance_air_h + _dl_range / (ch * ch)

## dL/dx at ferronock position [H/m]
## Positive  (ferronock approaching centre) → forward force
## Negative  (ferronock past centre) → braking; MCU de-energises at ξ=0
func get_dl_dx(bolt_x: float) -> float:
	var xi: float = _xi(bolt_x)
	var u:  float = xi * sharpness
	var ch: float = cosh(u)
	var th: float = tanh(u)
	return -2.0 * _dl_range * sharpness * th / (ch * ch) / _coil_half

## Magnetic force on ferronock [N].  Positive = forward (+X).
func get_force(bolt_x: float, current_sq: float) -> float:
	return 0.5 * current_sq * get_dl_dx(bolt_x)
