extends Node

## On-screen HUD: ARM / FIRE buttons, per-stage status, cap charge bars, battery SOC.
## All UI built in code so no .tscn fiddling is needed when adding stages.

@onready var _mcu     = $"../MCU"
@onready var _pp0     = $"../PowerPack0"
@onready var _pp1     = $"../PowerPack1"
@onready var _battery = $"../Battery"

## Per-stage widget refs
var _stage_rect:   Array = []   ## ColorRect  — status colour
var _stage_slbl:   Array = []   ## Label       — state name
var _stage_vlbl:   Array = []   ## Label       — voltage
var _stage_bar:    Array = []   ## ProgressBar — charge fraction

## Global widgets
var _bat_bar:   ProgressBar
var _bat_lbl:   Label
var _mv_lbl:    Label
var _btn_arm:   Button
var _btn_fire:  Button

const COL_SAFE     := Color(0.40, 0.40, 0.40)
const COL_CHARGING := Color(0.95, 0.72, 0.00)
const COL_ARMED    := Color(0.10, 0.82, 0.10)
const COL_FIRING   := Color(1.00, 0.45, 0.00)
const COL_DRAINING := Color(0.20, 0.50, 1.00)
const COL_FAULT    := Color(0.85, 0.05, 0.05)

func _ready() -> void:
	_build_ui()
	if not _mcu: return
	_mcu.mcu_stage_armed.connect(_on_any_stage_change)
	_mcu.mcu_stage_fired.connect(_on_any_stage_change)
	_mcu.mcu_stage_drained.connect(_on_any_stage_change)
	_mcu.mcu_fault.connect(func(s, _r): _on_any_stage_change(s))
	if _mcu.has_signal("mcu_stage_charging"):
		_mcu.mcu_stage_charging.connect(_on_any_stage_change)
	if _mcu.has_signal("mcu_ready"):
		_mcu.mcu_ready.connect(_on_mcu_ready)

func _process(_delta: float) -> void:
	_refresh_stage_displays()
	_refresh_battery_display()

## ── UI construction ──────────────────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	match event.keycode:
		KEY_A: if not _btn_arm.disabled:  _on_arm_pressed()
		KEY_F: if not _btn_fire.disabled: _on_fire_pressed()
		KEY_SPACE: if not _btn_fire.disabled: _on_fire_pressed()

func _make_shortcut(keycode: Key) -> Shortcut:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	var sc := Shortcut.new()
	sc.events = [ev]
	return sc

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	## Title
	var title := Label.new()
	title.text = "EM CROSSBOW"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	## Stage indicators
	var stage_row := HBoxContainer.new()
	stage_row.add_theme_constant_override("separation", 14)
	vbox.add_child(stage_row)
	for i in range(2):
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 3)
		stage_row.add_child(sv)
		_add_stage_widget(sv, i)

	vbox.add_child(HSeparator.new())

	## Battery row
	var bat_row := HBoxContainer.new()
	bat_row.add_theme_constant_override("separation", 6)
	vbox.add_child(bat_row)
	var blbl := Label.new()
	blbl.text = "BAT"
	bat_row.add_child(blbl)
	_bat_bar = ProgressBar.new()
	_bat_bar.custom_minimum_size = Vector2(90, 14)
	_bat_bar.min_value = 0.0
	_bat_bar.max_value = 1.0
	_bat_bar.value     = 1.0
	_bat_bar.show_percentage = false
	bat_row.add_child(_bat_bar)
	_bat_lbl = Label.new()
	_bat_lbl.text = "42.0V 100%"
	_bat_lbl.add_theme_font_size_override("font_size", 11)
	bat_row.add_child(_bat_lbl)

	vbox.add_child(HSeparator.new())

	## Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_btn_arm = Button.new()
	_btn_arm.text = "ARM  [A]"
	_btn_arm.custom_minimum_size = Vector2(88, 36)
	_btn_arm.shortcut = _make_shortcut(KEY_A)
	_btn_arm.pressed.connect(_on_arm_pressed)
	btn_row.add_child(_btn_arm)

	_btn_fire = Button.new()
	_btn_fire.text = "FIRE  [F]"
	_btn_fire.custom_minimum_size = Vector2(88, 36)
	_btn_fire.shortcut = _make_shortcut(KEY_F)
	_btn_fire.disabled = true
	_btn_fire.pressed.connect(_on_fire_pressed)
	btn_row.add_child(_btn_fire)

	## Last-shot muzzle velocity
	_mv_lbl = Label.new()
	_mv_lbl.text = ""
	_mv_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_mv_lbl)

func _add_stage_widget(parent: VBoxContainer, i: int) -> void:
	var header := Label.new()
	header.text = "STAGE %d" % i
	header.add_theme_font_size_override("font_size", 12)
	parent.add_child(header)

	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(88, 16)
	rect.color = COL_SAFE
	parent.add_child(rect)
	_stage_rect.append(rect)

	var slbl := Label.new()
	slbl.text = "SAFE"
	slbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(slbl)
	_stage_slbl.append(slbl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(88, 10)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value     = 0.0
	bar.show_percentage = false
	parent.add_child(bar)
	_stage_bar.append(bar)

	var vlbl := Label.new()
	vlbl.text = "0.0 V"
	vlbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(vlbl)
	_stage_vlbl.append(vlbl)

## ── Display refresh (called each _process frame) ─────────────────────────────

func _refresh_stage_displays() -> void:
	var pps: Array = [_pp0, _pp1]
	for i in range(2):
		var pp = pps[i]
		if not pp: continue
		## Voltage + charge fraction
		var v: float    = pp.get_voltage() if pp.has_method("get_voltage") else 0.0
		var frac: float = pp.get_charge_fraction() if pp.has_method("get_charge_fraction") else 0.0
		if i < _stage_vlbl.size(): _stage_vlbl[i].text = "%.1f V" % v
		if i < _stage_bar.size():  _stage_bar[i].value = frac
		## State colour
		if _mcu:
			var sname: String = _mcu.get_stage_state_name(i)
			if i < _stage_rect.size():
				_stage_rect[i].color = _state_colour(sname)
				_stage_slbl[i].text  = sname

func _refresh_battery_display() -> void:
	if not _battery: return
	var soc: float = _battery.get_soc()
	var v:   float = _battery.get_voltage()
	_bat_bar.value = soc
	_bat_lbl.text  = "%.1fV %d%%" % [v, int(soc * 100.0)]

func _state_colour(state_name: String) -> Color:
	match state_name:
		"CHARGING": return COL_CHARGING
		"ARMED":    return COL_ARMED
		"FIRING":   return COL_FIRING
		"DRAINING": return COL_DRAINING
		"FAULT":    return COL_FAULT
		_:          return COL_SAFE

## ── Signal handlers ──────────────────────────────────────────────────────────

func _on_any_stage_change(_stage: int) -> void:
	pass   ## _refresh_stage_displays() picks it up next frame

func _on_mcu_ready() -> void:
	_btn_fire.disabled = false
	_btn_arm.disabled  = true

func _on_arm_pressed() -> void:
	print("HUD: ARM pressed")
	if _mcu:
		_mcu.arm_request()
	else:
		push_error("HUD: _mcu is null — check node path ../MCU")
	_btn_arm.disabled  = true
	_btn_fire.disabled = true

func _on_fire_pressed() -> void:
	print("HUD: FIRE pressed")
	if _mcu:
		_mcu.fire_request()
	else:
		push_error("HUD: _mcu is null — check node path ../MCU")
	_btn_fire.disabled = true
	_btn_arm.disabled  = false   ## allow re-arming for next shot

## Called by MCU when muzzle velocity is computed
func show_muzzle_velocity(v_mps: float) -> void:
	_mv_lbl.text = "Muzzle: %.1f m/s" % v_mps
