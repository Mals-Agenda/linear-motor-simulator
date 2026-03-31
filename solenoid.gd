extends Node3D
class_name Solenoid

## Position-dependent solenoid model.
##
## Physics model — sech² inductance profile:
##   ξ = (bolt_x - center_x) / coil_half_length
##   L(ξ) = L_air + (L_core - L_air) / cosh²(ξ · sharpness)
##
## Properties:
##   • L is maximum at ξ=0 (bolt centred in coil)
##   • L → L_air as bolt moves away in either direction
##   • dL/dx > 0 for ξ < 0  → attractive (forward) force
##   • dL/dx < 0 for ξ > 0  → braking force  (MCU de-energises at ξ=0)
##   • Force  F = ½ · I² · dL/dx
##
## Back-EMF term (handled in PowerPack):
##   V_back = I · (dL/dx) · v_bolt
##   Included automatically when PowerPack.set_bolt_state() is called.

@export var label:             String = "Solenoid"
@export var coil_length:       float  = 0.30   ## physical coil length [m]
@export var inductance_air_h:  float  = 0.001  ## L — no ferromagnetic core [H]
@export var inductance_core_h: float  = 0.008  ## L — bolt fully centred [H]
@export var sharpness:         float  = 1.5    ## profile width (higher = sharper peak)

var center_x:   float = 0.0

## Cached derived values
var _dl_range:  float = 0.0
var _coil_half: float = 0.0

func _ready() -> void:
	center_x   = global_position.x
	_dl_range  = inductance_core_h - inductance_air_h
	_coil_half = coil_length * 0.5

## ── Core physics ─────────────────────────────────────────────────────────────

## Normalised position (ξ).  ξ=0 at coil centre; negative = bolt approaching.
func _xi(bolt_x: float) -> float:
	return (bolt_x - center_x) / _coil_half

## Inductance at bolt position [H]
func get_inductance(bolt_x: float) -> float:
	var u: float = _xi(bolt_x) * sharpness
	var ch: float = cosh(u)
	return inductance_air_h + _dl_range / (ch * ch)

## dL/dx at bolt position [H/m]
## Positive  (bolt approaching centre from behind) → forward force
## Negative  (bolt past centre) → braking; MCU prevents this by de-energising
func get_dl_dx(bolt_x: float) -> float:
	var xi: float = _xi(bolt_x)
	var u: float  = xi * sharpness
	var ch: float = cosh(u)
	var th: float = tanh(u)
	## d/dx of sech²(u) = -2·sharpness·tanh(u)·sech²(u) / coil_half
	return -2.0 * _dl_range * sharpness * th / (ch * ch) / _coil_half

## Magnetic force on bolt [N].  Positive = forward (+X).
## current_sq = I²  (use avg_current_sq from PowerPack for RMS-correct averaging)
func get_force(bolt_x: float, current_sq: float) -> float:
	return 0.5 * current_sq * get_dl_dx(bolt_x)

## ── Legacy shim (keeps sim_ctrl compiling if not yet updated) ─────────────────
func get_force_from_isq(current_sq: float) -> float:
	## Falls back to peak-force position (ξ slightly behind centre)
	return get_force(center_x - _coil_half * 0.5, current_sq)
