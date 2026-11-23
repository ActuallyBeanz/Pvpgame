extends Control
## Launch menu: pick your character, then Host or Join. Scene changes are handled by
## Lobby, not here. The character choice is saved (Lobby.save_profile) and remembered.

@export var preview_spin_speed := 0.6

@onready var address_edit: LineEdit = %AddressEdit
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var model_option: OptionButton = %ModelOption
@onready var prev_model: Button = %PrevModel
@onready var next_model: Button = %NextModel
@onready var model_spot: Node3D = %ModelSpot
@onready var preview_camera: Camera3D = %PreviewCamera
@onready var preview_light: DirectionalLight3D = %PreviewLight

var _model_ids: PackedStringArray = []


func _ready() -> void:
	address_edit.text = GameConfig.settings.default_address
	address_edit.placeholder_text = "host IP  (or IP:port)"
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	address_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	NetworkManager.join_failed.connect(_on_join_failed)
	status_label.text = Lobby.consume_message()
	_setup_character_picker()
	host_button.grab_focus()


func _process(delta: float) -> void:
	model_spot.rotate_y(preview_spin_speed * delta)


# ---------------------------------------------------------------- character picker
func _setup_character_picker() -> void:
	_model_ids = Lobby.character_models()
	for id in _model_ids:
		model_option.add_item(_pretty(id))
	model_option.item_selected.connect(_on_model_selected)
	prev_model.pressed.connect(func() -> void: _step_model(-1))
	next_model.pressed.connect(func() -> void: _step_model(1))
	preview_camera.look_at_from_position(Vector3(0.0, 1.2, -3.6), Vector3(0.0, 0.85, 0.0))
	preview_light.rotation_degrees = Vector3(-40.0, 150.0, 0.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	model_spot.get_parent().add_child(we)
	var idx := maxi(0, _model_ids.find(Lobby.local_model()))
	model_option.select(idx)
	_show_model(idx)


func _step_model(dir: int) -> void:
	if _model_ids.is_empty():
		return
	var i := wrapi(model_option.selected + dir, 0, _model_ids.size())
	model_option.select(i)
	_on_model_selected(i)


func _on_model_selected(i: int) -> void:
	Lobby.local_profile.model = _model_ids[i]
	Lobby.save_profile()
	_show_model(i)


func _show_model(i: int) -> void:
	for c in model_spot.get_children():
		c.queue_free()
	if i < 0 or i >= _model_ids.size():
		return
	var m := AssetRegistry.instantiate(_model_ids[i])
	var tag := m.get_node_or_null("NameTag")
	if tag:
		tag.visible = false
	model_spot.add_child(m)


static func _pretty(id: String) -> String:
	return id.trim_prefix(Lobby.MODEL_PREFIX).replace("_", " ").capitalize()


func _on_host_pressed() -> void:
	var err := NetworkManager.host()
	if err != OK:
		status_label.text = "Couldn't host on port %d (%s). Is another copy already hosting?" \
			% [GameConfig.settings.port, error_string(err)]


func _on_join_pressed() -> void:
	var text := address_edit.text.strip_edges()
	if text.is_empty():
		text = GameConfig.settings.default_address
	var address := text
	var port := -1
	if text.count(":") == 1:  # "ip:port" (plain IPv6 has several colons, so skip those)
		address = text.get_slice(":", 0)
		port = text.get_slice(":", 1).to_int()
	var err := NetworkManager.join(address, port)
	if err != OK:
		status_label.text = "Couldn't start connection (%s)." % error_string(err)
		return
	_set_busy(true)
	status_label.text = "Connecting to %s..." % text


func _on_join_failed(reason: String) -> void:
	_set_busy(false)
	status_label.text = reason


func _set_busy(busy: bool) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	address_edit.editable = not busy
