extends CanvasLayer

## Real-time oscilloscope overlay — tracks the ACTIVE stage.
## Channels: Vc (cap voltage), I (coil current), F (force), x (position),
##           v (velocity), v_tgt (target velocity from MCU profile).
## Tab key toggles visibility.

@export var max_samples:  int   = 512
@export var panel_width:  int   = 420
@export var panel_height: int   = 320
@export var bg_color:     Color = Color(0.06, 0.06, 0.08, 0.88)

var _channels: Array = []
var _panel:    Panel
var _visible:  bool  = true

var ch_vc:   int = -1
var ch_i:    int = -1
var ch_f:    int = -1
var ch_x:    int = -1
var ch_v:    int = -1
var ch_vtgt: int = -1

func _ready() -> void:
	_build_panel()
	ch_vc   = _add_channel("Vc",    Color(0.2,  0.6,  1.0),  300.0)
	ch_i    = _add_channel("I",     Color(1.0,  0.7,  0.1),  200.0)
	ch_f    = _add_channel("F",     Color(1.0,  0.3,  0.2),  500.0)
	ch_x    = _add_channel("x",     Color(0.3,  1.0,  0.5),   10.0)
	ch_v    = _add_channel("v",     Color(0.5,  1.0,  0.5),   60.0)
	ch_vtgt = _add_channel("v_tgt", Color(1.0,  1.0,  0.35),  60.0)
	_rebuild_legend()
	print("TelemetryGraph ready — Tab to toggle")

## Called by SimCtrl each physics frame with active-stage data.
func push_sample(vc: float, i_rms: float, f: float,
				 x: float, v: float, v_tgt: float) -> void:
	_push(ch_vc,   vc)
	_push(ch_i,    i_rms)
	_push(ch_f,    f)
	_push(ch_x,    x)
	_push(ch_v,    v)
	_push(ch_vtgt, v_tgt)
	if _visible and _panel:
		_panel.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_visible = not _visible
			if _panel: _panel.visible = _visible
			get_viewport().set_input_as_handled()

func _add_channel(lbl: String, color: Color, scale: float) -> int:
	var buf: Array = []
	buf.resize(max_samples)
	buf.fill(0.0)
	_channels.append({"label": lbl, "color": color, "scale": scale,
					   "samples": buf, "write_idx": 0})
	return _channels.size() - 1

func _push(ch: int, value: float) -> void:
	if ch < 0 or ch >= _channels.size(): return
	var c: Dictionary = _channels[ch]
	c["samples"][c["write_idx"]] = value
	c["write_idx"] = (c["write_idx"] + 1) % max_samples

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.position      = Vector2(10, 80)
	_panel.size          = Vector2(panel_width, panel_height)
	var style            := StyleBoxFlat.new()
	style.bg_color       = bg_color
	style.border_color   = Color(0.3, 0.3, 0.35, 1.0)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.draw.connect(_on_panel_draw)
	add_child(_panel)

func _rebuild_legend() -> void:
	var x_off: float = panel_width - 10.0
	for i in range(_channels.size() - 1, -1, -1):
		var lbl := Label.new()
		lbl.text = _channels[i]["label"]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", _channels[i]["color"])
		lbl.position = Vector2(x_off - 40, 4 + i * 14)
		_panel.add_child(lbl)

func _on_panel_draw() -> void:
	if _channels.is_empty(): return
	var pw: float = float(panel_width)
	var ph: float = float(panel_height) - 4.0
	var n:  int   = max_samples

	for row in range(5):
		var y: float = 4.0 + ph * row / 4.0
		_panel.draw_line(Vector2(0, y), Vector2(pw, y),
				Color(0.25, 0.25, 0.27, 0.6), 1.0)

	for ch_idx in range(_channels.size()):
		var c:     Dictionary = _channels[ch_idx]
		var buf:   Array      = c["samples"]
		var w_idx: int        = c["write_idx"]
		var scale: float      = c["scale"]
		var color: Color      = c["color"]
		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(n)
		for k in range(n):
			var si:  int   = (w_idx + k) % n
			var val: float = buf[si]
			var px:  float = pw * k / float(n - 1)
			var py:  float = ph + 4.0 - clamp(val / scale, 0.0, 1.0) * ph
			pts[k] = Vector2(px, py)
		_panel.draw_polyline(pts, color, 1.2)
