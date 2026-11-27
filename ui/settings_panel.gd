extends PanelContainer
## Settings window (audio volumes, mouse sensitivity, invert Y). Built in code; used by the
## main menu and the pause menu. Changes apply and save immediately.

signal closed


func _ready() -> void:
	custom_minimum_size = Vector2(420, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_section(box, "Audio")
	for k in [["master", "Master"], ["music", "Music"], ["sfx", "Sound effects"], ["ambience", "Ambience"], ["ui", "Menus"]]:
		var key: String = k[0]
		_slider(box, k[1], 0.0, 1.0, 0.01, UserSettings.volumes[key], func(v: float) -> void: UserSettings.set_volume(key, v), true)
	_section(box, "Controls")
	_slider(box, "Mouse sensitivity", 0.2, 3.0, 0.05, UserSettings.mouse_mult, func(v: float) -> void: UserSettings.set_mouse_mult(v), false)
	var inv := CheckBox.new()
	inv.text = "Invert camera Y"
	inv.button_pressed = UserSettings.invert_y
	inv.toggled.connect(func(on: bool) -> void: UserSettings.set_invert_y(on))
	box.add_child(inv)
	var close := Button.new()
	close.text = "Back"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(func() -> void:
		hide()
		closed.emit())
	box.add_child(close)


func _section(box: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	box.add_child(l)


func _slider(box: Control, label: String, lo: float, hi: float, step: float, value: float, on_change: Callable, percent: bool) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(160, 24)
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(52, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := func(x: float) -> String: return ("%d%%" % roundi(x * 100.0)) if percent else ("%.2fx" % x)
	v.text = fmt.call(value)
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt.call(x)
		on_change.call(x))
	box.add_child(row)
