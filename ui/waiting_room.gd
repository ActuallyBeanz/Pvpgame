extends Control
## Waiting Room: set display name + color, toggle ready, host starts the match.
## All edits go through Lobby.submit_profile(); the roster shown is always the
## host's authoritative copy.

@onready var name_edit: LineEdit = %NameEdit
@onready var color_row: HBoxContainer = %ColorRow
@onready var swatch: ColorRect = %Swatch
@onready var player_list: ItemList = %PlayerList
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var info_label: Label = %InfoLabel

var _color_buttons: Array[Button] = []
var _selected_color := 0


func _ready() -> void:
	name_edit.max_length = GameConfig.settings.name_max_length
	name_edit.text = str(Lobby.local_profile.name)
	_selected_color = int(Lobby.local_profile.color)
	_build_color_buttons()

	name_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	name_edit.focus_exited.connect(_submit)
	ready_button.toggled.connect(func(_on: bool) -> void: _submit())
	start_button.pressed.connect(Lobby.start_match)
	leave_button.pressed.connect(func() -> void: NetworkManager.leave())
	Lobby.roster_changed.connect(_refresh)

	var is_host := multiplayer.is_server()
	start_button.visible = is_host
	ready_button.visible = not is_host  # host is "ready" when they press Start
	if is_host:
		start_button.grab_focus()
	_refresh()


func _build_color_buttons() -> void:
	var colors := GameConfig.settings.player_colors
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 28)
		b.tooltip_text = "Color %d" % (i + 1)
		var box := StyleBoxFlat.new()  # shared by all states so the border shows everywhere
		box.bg_color = colors[i]
		box.set_corner_radius_all(4)
		for state_name in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state_name, box)
		b.pressed.connect(_on_color_picked.bind(i))
		color_row.add_child(b)
		_color_buttons.append(b)
	_update_color_selection()


func _on_color_picked(index: int) -> void:
	_selected_color = index
	_update_color_selection()
	_submit()


func _update_color_selection() -> void:
	for i in _color_buttons.size():
		var box := _color_buttons[i].get_theme_stylebox("normal") as StyleBoxFlat
		box.set_border_width_all(3 if i == _selected_color else 0)
		box.border_color = Color.WHITE
	swatch.color = GameConfig.color_for(_selected_color)


func _submit() -> void:
	if not Lobby.is_waiting():
		return
	Lobby.submit_profile(name_edit.text, _selected_color, ready_button.button_pressed)
	Lobby.save_profile()  # remember name + color for next time


func _refresh() -> void:
	if not is_inside_tree():
		return
	player_list.clear()
	var me := multiplayer.get_unique_id()
	var ids := Lobby.players.keys()
	ids.sort()
	for id: int in ids:
		var e: Dictionary = Lobby.players[id]
		var tags := ""
		if id == 1:
			tags += "  [host]"
		if id == me:
			tags += "  (you)"
		var ready_mark := "✔" if (e.ready or id == 1) else "·"
		var who := str(e.get("model", "")).trim_prefix(Lobby.MODEL_PREFIX).replace("_", " ").capitalize()
		var idx := player_list.add_item("%s  %s  ·  %s%s" % [ready_mark, e.name, who, tags])
		player_list.set_item_custom_fg_color(idx, GameConfig.color_for(e.color))
		player_list.set_item_selectable(idx, false)

	var mine := Lobby.local_entry()
	if not mine.is_empty():
		ready_button.set_pressed_no_signal(mine.ready)
	ready_button.text = "Ready ✔" if ready_button.button_pressed else "Ready?"
	start_button.disabled = not Lobby.can_start()
	info_label.text = "%d / %d players%s" % [
		Lobby.players.size(), GameConfig.settings.max_players, _host_hint()]


func _host_hint() -> String:
	if not multiplayer.is_server():
		return ""
	var ips: PackedStringArray = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			ips.append(ip)
	if ips.is_empty():
		return ""
	return "   ·   friends join at: %s  (port %d)" % [", ".join(ips), GameConfig.settings.port]
