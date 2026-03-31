extends CanvasLayer

## HUD — ARM / FIRE controls wired to MCU.
## Works for any stage_count; shows aggregated stage status instead of
## per-stage rows (impractical for 20 stages).

@onready var _mcu:      Node = $"../MCU"
@onready var _sim_ctrl: Node = $"../SimCtrl"

var _btn_arm:    Button
var _btn_fire:   Button
var _status_lbl: Label
var _count_lbl:  Label
var _vel_lbl:    Label

const _COLORS := {
	"SAFE":     Color(0.55, 0.55, 0.55),
	"CHARGING": Color(1.00, 0.75, 0.00),
	"ARMED":    Color(0.00, 0.85, 0.00),
	"FIRING":   Color(1.00, 0.35, 0.00),
	"DRAINING": Color(0.20, 0.65, 1.00),
	"FAULT":    Color(1.00, 0.10, 0.10),
}

func _ready() -> void:
	_build_ui()
	if _mcu:
		_mcu.mcu_stage_charging.connect(func(_s): _refresh_count())
		_mcu.mcu_stage_armed.connect(   func(_s): _refresh_count())
		_mcu.mcu_stage_fired.connect(   func(_s): _refresh_count())
		_mcu.mcu_stage_drained.connect( func(_s): _refresh_count())
		_mcu.mcu_stage_safe.connect(    func(_s): _refresh_count())
		_mcu.mcu_fault.connect(_on_fault)
		_mcu.mcu_ready.connect(_on_mcu_ready)
		print("HUD: connected to MCU  stages=%d" % _mcu.stage_count)
	else:
		push_error("HUD: MCU node not found at ../MCU")

func _physics_process(_delta: float) -> void:
	_refresh_count()
	_refresh_velocity()

## ── Button callbacks ─────────────────────────────────────────────────────────

func _on_arm_pressed() -> void:
	_btn_arm.disabled  = true
	_btn_fire.disabled = true
	_status_lbl.text   = "CHARGING…"
	_status_lbl.add_theme_color_override("font_color", _COLORS["CHARGING"])
	if _mcu: _mcu.arm_request()

func _on_fire_pressed() -> void:
	if _btn_fire.disabled: return
	_btn_fire.disabled = true
	_status_lbl.text   = "FIRING"
	_status_lbl.add_theme_color_override("font_color", _COLORS["FIRING"])
	if _mcu: _mcu.fire_request()

## ── MCU signal handlers ──────────────────────────────────────────────────────

func _on_mcu_ready() -> void:
	_btn_fire.disabled = false
	_status_lbl.text   = "ARMED — FIRE!"
	_status_lbl.add_theme_color_override("font_color", _COLORS["ARMED"])

func _on_fault(stage: int, reason: String) -> void:
	_btn_arm.disabled  = false
	_btn_fire.disabled = true
	_status_lbl.text   = "FAULT S%d: %s" % [stage, reason]
	_status_lbl.add_theme_color_override("font_color", _COLORS["FAULT"])

func show_muzzle_velocity(v_ms: float) -> void:
	_status_lbl.text = "MUZZLE  %.1f m/s" % v_ms
	_status_lbl.add_theme_color_override("font_color", Color.CYAN)

func _refresh_velocity() -> void:
	if not _vel_lbl: return
	var vx:  float = _sim_ctrl.get_bolt_vx()          if (_sim_ctrl and _sim_ctrl.has_method("get_bolt_vx"))          else 0.0
	var vt:  float = _mcu.target_velocity_ms           if (_mcu     and "target_velocity_ms" in _mcu)                  else 50.0
	_vel_lbl.text  = "%.1f / %.0f m/s" % [vx, vt]
	var frac: float = clamp(vx / maxf(vt, 1.0), 0.0, 1.0)
	_vel_lbl.add_theme_color_override("font_color",
		Color(1.0 - frac, 0.4 + frac * 0.6, frac))

## ── Stage counter refresh ─────────────────────────────────────────────────────

func _refresh_count() -> void:
	if not _mcu: return
	var n:        int = _mcu.stage_count
	var armed_n:  int = 0
	var safe_n:   int = 0
	var firing_n: int = 0
	var chg_n:    int = 0
	for i in range(n):
		match _mcu.get_stage_state_name(i):
			"ARMED":                   armed_n  += 1
			"SAFE":                    safe_n   += 1
			"FIRING", "DRAINING":      firing_n += 1
			"CHARGING":                chg_n    += 1

	if firing_n > 0:
		_count_lbl.text = "%d/%d FIRING" % [firing_n, n]
		_count_lbl.add_theme_color_override("font_color", _COLORS["FIRING"])
	elif armed_n == n:
		_count_lbl.text = "%d/%d ARMED" % [n, n]
		_count_lbl.add_theme_color_override("font_color", _COLORS["ARMED"])
	elif safe_n == n:
		_count_lbl.text = "%d/%d SAFE" % [n, n]
		_count_lbl.add_theme_color_override("font_color", _COLORS["SAFE"])
		_btn_arm.disabled  = false
		_btn_fire.disabled = true
		_status_lbl.text   = "SAFE"
		_status_lbl.add_theme_color_override("font_color", _COLORS["SAFE"])
	elif chg_n > 0:
		_count_lbl.text = "%d/%d charging" % [chg_n, n]
		_count_lbl.add_theme_color_override("font_color", _COLORS["CHARGING"])
	else:
		_count_lbl.text = "%d/%d ARMED" % [armed_n, n]
		_count_lbl.add_theme_color_override("font_color", _COLORS["CHARGING"])

## ── Keyboard ─────────────────────────────────────────────────────────────────

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

## ── UI construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_status_lbl = _make_label("SAFE", 20)
	_status_lbl.add_theme_color_override("font_color", _COLORS["SAFE"])
	vbox.add_child(_status_lbl)

	_count_lbl = _make_label("0/0 SAFE", 16)
	_count_lbl.add_theme_color_override("font_color", _COLORS["SAFE"])
	vbox.add_child(_count_lbl)

	_vel_lbl = _make_label("0.0 / 50 m/s", 16)
	_vel_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.0))
	vbox.add_child(_vel_lbl)

	var spc := Control.new()
	spc.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spc)

	_btn_arm = _make_button("ARM  [A]", 22, _on_arm_pressed)
	vbox.add_child(_btn_arm)

	_btn_fire = _make_button("FIRE  [F]", 22, _on_fire_pressed)
	_btn_fire.disabled = true
	vbox.add_child(_btn_fire)

func _make_label(text: String, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl

func _make_button(text: String, font_size: int, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 56)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.pressed.connect(cb)
	return btn
