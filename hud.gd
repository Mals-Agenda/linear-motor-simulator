extends CanvasLayer

# Signals for UI state changes
signal arm_state_changed(armed: bool)
signal fire_requested

# Button references
var _btn_arm: Button
var _btn_fire: Button
var _lbl_status: Label

# State
var is_armed: bool = false
var can_fire: bool = false

func _ready() -> void:
	_create_ui()
	print("HUD initialized with buttons")

func _create_ui() -> void:
	# Create a margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	
	# Create main VBox for layout
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# Status label
	_lbl_status = Label.new()
	_lbl_status.text = "Status: DISARMED"
	_lbl_status.add_theme_font_size_override("font_size", 24)
vbox.add_child(_lbl_status)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
vbox.add_child(spacer)
	
	# ARM button
	_btn_arm = Button.new()
	_btn_arm.text = "ARM [A]"
	_btn_arm.custom_minimum_size = Vector2(200, 60)
	_btn_arm.add_theme_font_size_override("font_size", 20)
	_btn_arm.pressed.connect(_on_arm_pressed)
vbox.add_child(_btn_arm)
	
	# FIRE button
	_btn_fire = Button.new()
	_btn_fire.text = "FIRE [F]"
	_btn_fire.custom_minimum_size = Vector2(200, 60)
	_btn_fire.add_theme_font_size_override("font_size", 20)
	_btn_fire.disabled = true
	_btn_fire.pressed.connect(_on_fire_pressed)
vbox.add_child(_btn_fire)

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard support
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_A:
				_on_arm_pressed()
				get_tree().root.set_input_as_handled()
			KEY_F:
				_on_fire_pressed()
				get_tree().root.set_input_as_handled()
		
	# Touch support for Samsung Tab
	if event is InputEventScreenTouch and event.pressed:
		var touch_pos = event.position
		if _btn_arm and _btn_arm.get_rect().has_point(touch_pos):
			_on_arm_pressed()
		elif _btn_fire and _btn_fire.get_rect().has_point(touch_pos):
			_on_fire_pressed()

func _on_arm_pressed() -> void:
	is_armed = !is_armed
	can_fire = is_armed
	_btn_fire.disabled = !is_armed
	
	var status_text = "ARMED" if is_armed else "DISARMED"
	_lbl_status.text = "Status: %s" % status_text
	
	print("Crossbow %s" % status_text)
	arm_state_changed.emit(is_armed)
	_state_colour(status_text.to_lower())

func _on_fire_pressed() -> void:
	if is_armed and can_fire:
		print("FIRING!")
		fire_requested.emit()
		# Optionally disarm after firing
		is_armed = false
		_btn_fire.disabled = true
		_lbl_status.text = "Status: FIRED"
		_state_colour("fired")
	else:
		print("Cannot fire - crossbow not armed")

func _state_colour(state: String) -> void:
	"""Update UI colors based on state"""
	match state:
		"armed":
			_btn_arm.modulate = Color.GREEN
			_lbl_status.add_theme_color_override("font_color", Color.GREEN)
		"disarmed":
			_btn_arm.modulate = Color.RED
			_lbl_status.add_theme_color_override("font_color", Color.WHITE)
		"fired":
			_btn_fire.modulate = Color.YELLOW
			_lbl_status.add_theme_color_override("font_color", Color.YELLOW)