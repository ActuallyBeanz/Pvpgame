extends Node
## Player options (autoload "UserSettings"), saved to user://settings.cfg.
## Volumes are 0..1 sliders on top of the mix in Audio.bus_volumes_db; mouse_mult scales
## CameraRig.mouse_sensitivity.

signal changed

const PATH := "user://settings.cfg"
const VOLUME_KEYS := ["master", "music", "sfx", "ambience", "ui"]
const BUS := { "master": &"Master", "music": &"Music", "sfx": &"SFX", "ambience": &"Ambience", "ui": &"UI" }

var volumes := { "master": 0.8, "music": 0.8, "sfx": 1.0, "ambience": 0.8, "ui": 0.8 }
var mouse_mult := 1.0                       ## 0.2 .. 3.0
var invert_y := false


func _ready() -> void:
	load_settings()
	apply.call_deferred()                    # after Audio has created its buses


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in VOLUME_KEYS:
		volumes[k] = clampf(float(cf.get_value("audio", k, volumes[k])), 0.0, 1.0)
	mouse_mult = clampf(float(cf.get_value("controls", "mouse_mult", mouse_mult)), 0.2, 3.0)
	invert_y = bool(cf.get_value("controls", "invert_y", invert_y))


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in VOLUME_KEYS:
		cf.set_value("audio", k, volumes[k])
	cf.set_value("controls", "mouse_mult", mouse_mult)
	cf.set_value("controls", "invert_y", invert_y)
	cf.save(PATH)


func apply() -> void:
	for k in VOLUME_KEYS:
		var bus: StringName = BUS[k]
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var base: float = 0.0 if k == "master" else float(Audio.bus_volumes_db.get(bus, 0.0))
		var v: float = volumes[k]
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, base + linear_to_db(maxf(v, 0.001)))
	changed.emit()


func set_volume(key: String, v: float) -> void:
	volumes[key] = clampf(v, 0.0, 1.0)
	apply()
	save_settings()


func set_mouse_mult(v: float) -> void:
	mouse_mult = clampf(v, 0.2, 3.0)
	save_settings()
	changed.emit()


func set_invert_y(on: bool) -> void:
	invert_y = on
	save_settings()
	changed.emit()
