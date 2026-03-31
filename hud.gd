extends CanvasLayer

## HUD — ARM / FIRE controls wired to MCU state machine.
## Node path assumptions (both are children of CrossbowRig):
##   ../MCU        → mcu.gd
##   ../PowerPack0 → power_pack.gd  (stage 0)
##   ../PowerPack1 → power_pack.gd  (stage 1)

@onready var _mcu: Node = $"../MCU"
@onready var _pp0: Node = $"../PowerPack0"
@onready var _pp1: Node = $"../PowerPack1"

var _btn_arm:    Button
var _btn_fire:   Button
var _status_lbl: Label
var _stage_lbl:  Array = []    ## [Label] per stage
var _charge_bar: Array = []    ## [ProgressBar] per stage

const _COLORS := {
	"SAFE":     Color(0.55, 0.55, 0.55),
	"CHARGING": Color(1.00, 0.75, 0.00),
	"ARMED":    Color(0.00, 0.85, 0.00),
	"FIRING":   Color(1.00, 0.35, 0.00),
	"DRAINING": Color(0.20, 0.65, 1.00),
	"FAULT":    Color(1.00, 0.10, 0.10),
}

## ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	if _mcu:
		_mcu.mcu_stage_charging.connect(_on_stage_charging)
		_mcu.mcu_stage_armed.connect(_on_stage_armed)
		_mcu.mcu_stage_fired.connect(_on_stage_fired)
		_mcu.mcu_stage_drained.connect(_on_stage_drained)
		_mcu.mcu_stage_safe.connect(_on_stage_safe)
		_mcu.mcu_fault.connect(_on_fault)
		_mcu.mcu_ready.connect(_on_mcu_ready)
		print("HUD: connected to MCU")
	else:
		push_error("HUD: MCU node not found — check ../MCU path")

func _physics_process(_delta: float) -> void:
	## Poll cap charge fractions every frame for smooth progress bars
	_update_charge_bar(0, _pp0)
	_update_charge_bar(1, _pp1)

func _update_charge_bar(i: int, pp: Node) -> void:
	if i >= _charge_bar.size() or not _charge_bar[i]: return
	var frac: float = pp.get_charge_fraction() if (pp and pp.has_method("get_charge_fraction")) else 0.0
	_charge_bar[i].value = frac * 100.0

## ── Button callbacks ─────────────────────────────────────────────────────────

func _on_arm_pressed() -> void:
	print("HUD: ARM pressed")
	_btn_arm.disabled = true
	_btn_fire.disabled = true
	_status_lbl.text = "CHARGING…"
	_status_lbl.add_theme_color_override("font_color", _COLORS["CHARGING"])
	if _mcu:
		_mcu.arm_request()
	else:
		push_error("HUD: _mcu is null — cannot arm")

func _on_fire_pressed() -> void:
	if _btn_fire.disabled: return
	print("HUD: FIRE pressed")
	_btn_fire.disabled = true
	_status_lbl.text = "FIRING"
	_status_lbl.add_theme_color_override("font_color", _COLORS["FIRING"])
	if _mcu:
		_mcu.fire_request()
	else:
		push_error("HUD: _mcu is null — cannot fire")

## ── MCU signal handlers ──────────────────────────────────────────────────────

func _on_stage_charging(stage: int) -> void:
	_set_stage_display(stage, "CHARGING")

func _on_stage_armed(stage: int) -> void:
	_set_stage_display(stage, "ARMED")

func _on_stage_fired(stage: int) -> void:
	_set_stage_display(stage, "FIRING")

func _on_stage_drained(stage: int) -> void:
	_set_stage_display(stage, "DRAINING")

func _on_stage_safe(stage: int) -> void:
	_set_stage_display(stage, "SAFE")
	## Re-enable ARM only when all stages are back to SAFE
	var all_safe := true
	if _mcu:
		for i in range(2):
			if _mcu.get_stage_state_name(i) != "SAFE":
				all_safe = false
				break
	if all_safe:
		_btn_arm.disabled = false
		_btn_fire.disabled = true
		_status_lbl.text = "SAFE"
		_status_lbl.add_theme_color_override("font_color", _COLORS["SAFE"])

func _on_mcu_ready() -> void:
	_btn_fire.disabled = false
	_status_lbl.text = "ARMED — ready to fire"
	_status_lbl.add_theme_color_override("font_color", _COLORS["ARMED"])
	print("HUD: all stages ARMED — FIRE enabled")

func _on_fault(stage: int, reason: String) -> void:
	_set_stage_display(stage, "FAULT")
	_btn_arm.disabled = false
	_btn_fire.disabled = true
	_status_lbl.text = "FAULT S%d: %s" % [stage, reason]
	_status_lbl.add_theme_color_override("font_color", _COLORS["FAULT"])

## ── Keyboard input ───────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return
	match event.keycode:
		KEY_A:
			if not _btn_arm.disabled:
				_on_arm_pressed()
				get_viewport().set_input_as_handled()
		KEY_F, KEY_SPACE:
			if not _btn_fire.disabled:
				_on_fire_pressed()
				get_viewport().set_input_as_handled()

## ── Public interface (called by MCU) ─────────────────────────────────────────

func show_muzzle_velocity(v_ms: float) -> void:
	_status_lbl.text = "MUZZLE  %.1f m/s" % v_ms
	_status_lbl.add_theme_color_override("font_color", Color.CYAN)

## ── Helpers ──────────────────────────────────────────────────────────────────

func _set_stage_display(stage: int, state_name: String) -> void:
	if stage >= _stage_lbl.size() or not _stage_lbl[stage]: return
	var lbl: Label = _stage_lbl[stage]
	var col: Color = _COLORS.get(state_name, Color.WHITE)
	lbl.text = "S%d: %s" % [stage, state_name]
	lbl.add_theme_color_override("font_color", col)

## ── UI construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	## Status line
	_status_lbl = _make_label("SAFE", 20)
	_status_lbl.add_theme_color_override("font_color", _COLORS["SAFE"])
	vbox.add_child(_status_lbl)

	## Per-stage rows
	for i in range(2):
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(hbox)

		var lbl := _make_label("S%d: SAFE" % i, 16)
		lbl.custom_minimum_size = Vector2(140, 0)
		lbl.add_theme_color_override("font_color", _COLORS["SAFE"])
		hbox.add_child(lbl)
		_stage_lbl.append(lbl)

		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(160, 22)
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value     = 0.0
		bar.show_percentage = false
		hbox.add_child(bar)
		_charge_bar.append(bar)

	## Spacer
	var spc := Control.new()
	spc.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spc)

	## ARM button
	_btn_arm = _make_button("ARM  [A]", 22, _on_arm_pressed)
	vbox.add_child(_btn_arm)

	## FIRE button
	_btn_fire = _make_button("FIRE  [F]", 22, _on_fire_pressed)
	_btn_fire.disabled = true
	vbox.add_child(_btn_fire)

func _make_label(text: String, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl

func _make_button(text: String, font_size: int, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 56)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.pressed.connect(callback)
	return btn
