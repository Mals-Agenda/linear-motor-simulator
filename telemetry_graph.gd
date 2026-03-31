extends CanvasLayer

## Real-time oscilloscope overlay.
## Displays per-stage voltage, current, force, plus bolt position and velocity.
## Attach to CrossbowRig scene alongside HUD.  Visible with Tab key toggle.
##
## Usage: SimCtrl or HUD calls push_sample() each physics frame.

@export var max_samples:  int   = 512   ## ring-buffer length
@export var panel_width:  int   = 420
@export var panel_height: int   = 320
@export var bg_color:     Color = Color(0.06, 0.06, 0.08, 0.88)

## ── Channels ──────────────────────────────────────────────────────────────────
## One entry per channel: { label, color, samples: Array[float], scale }
var _channels: Array = []

## Panel root
var _panel:    Panel
var _visible:  bool = true

## Channel indices (set in _ready, used by push_sample)
var ch_vc0: int = -1
var ch_vc1: int = -1
var ch_i0:  int = -1
var ch_i1:  int = -1
var ch_f0:  int = -1
var ch_f1:  int = -1
var ch_x:   int = -1
var ch_v:   int = -1

func _ready() -> void:
	_build_panel()
	## Register channels
	ch_vc0 = _add_channel("Vc0",  Color(0.2, 0.6, 1.0),  100.0)  ## voltage 0–100 V
	ch_vc1 = _add_channel("Vc1",  Color(0.4, 0.8, 1.0),  100.0)
	ch_i0  = _add_channel("I0",   Color(1.0, 0.7, 0.1),  200.0)  ## current 0–200 A
	ch_i1  = _add_channel("I1",   Color(1.0, 0.9, 0.2),  200.0)
	ch_f0  = _add_channel("F0",   Color(1.0, 0.3, 0.2),  500.0)  ## force 0–500 N
	ch_f1  = _add_channel("F1",   Color(1.0, 0.5, 0.3),  500.0)
	ch_x   = _add_channel("x",    Color(0.3, 1.0, 0.5),    3.0)  ## position 0–3 m
	ch_v   = _add_channel("v",    Color(0.6, 1.0, 0.6),   50.0)  ## velocity 0–50 m/s
	_rebuild_legend()
	print("TelemetryGraph ready — Tab to toggle")

## ── Public API ────────────────────────────────────────────────────────────────

## Call from SimCtrl._physics_process each frame
func push_sample(vc0: float, i0: float, f0: float,
				 vc1: float, i1: float, f1: float,
				 x:   float, v:  float) -> void:
	_push(ch_vc0, vc0)
	_push(ch_vc1, vc1)
	_push(ch_i0,  i0)
	_push(ch_i1,  i1)
	_push(ch_f0,  f0)
	_push(ch_f1,  f1)
	_push(ch_x,   x)
	_push(ch_v,   v)
	if _visible and _panel:
		_panel.queue_redraw()

## ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_visible = not _visible
			if _panel: _panel.visible = _visible
			get_viewport().set_input_as_handled()

## ── Internal ──────────────────────────────────────────────────────────────────

func _add_channel(label: String, color: Color, scale: float) -> int:
	var buf: Array = []
	buf.resize(max_samples)
	buf.fill(0.0)
	_channels.append({ "label": label, "color": color, "scale": scale,
						"samples": buf, "write_idx": 0 })
	return _channels.size() - 1

func _push(ch: int, value: float) -> void:
	if ch < 0 or ch >= _channels.size(): return
	var c: Dictionary = _channels[ch]
	c["samples"][c["write_idx"]] = value
	c["write_idx"] = (c["write_idx"] + 1) % max_samples

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.position           = Vector2(10, 80)   ## below HUD buttons
	_panel.size               = Vector2(panel_width, panel_height)
	_panel.self_modulate      = bg_color

	var style := StyleBoxFlat.new()
	style.bg_color            = bg_color
	style.border_color        = Color(0.3, 0.3, 0.35, 1.0)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)

	_panel.draw.connect(_on_panel_draw)
	add_child(_panel)

func _rebuild_legend() -> void:
	## Small colored labels in the top-right of the panel
	var x_off: float = panel_width - 10.0
	for i in range(_channels.size() - 1, -1, -1):
		var lbl := Label.new()
		lbl.text = _channels[i]["label"]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", _channels[i]["color"])
		lbl.position = Vector2(x_off - 36, 4 + i * 14)
		_panel.add_child(lbl)

func _on_panel_draw() -> void:
	if _channels.is_empty(): return

	var pw: float = float(panel_width)
	var ph: float = float(panel_height) - 4.0
	var n:  int   = max_samples

	## Background grid
	for row in range(5):
		var y: float = 4.0 + ph * row / 4.0
		_panel.draw_line(Vector2(0, y), Vector2(pw, y), Color(0.25, 0.25, 0.27, 0.6), 1.0)

	## Each channel
	for ch_idx in range(_channels.size()):
		var c:     Dictionary = _channels[ch_idx]
		var buf:   Array      = c["samples"]
		var w_idx: int        = c["write_idx"]
		var scale: float      = c["scale"]
		var color: Color      = c["color"]

		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(n)
		for k in range(n):
			var sample_idx: int   = (w_idx + k) % n
			var val:        float = buf[sample_idx]
			var px:         float = pw * k / float(n - 1)
			var py:         float = ph + 4.0 - clamp(val / scale, 0.0, 1.0) * ph
			pts[k] = Vector2(px, py)

		_panel.draw_polyline(pts, color, 1.2)
