extends Node
## Autoload: GameConfig. Single access point for tunable settings + global input state.
## NOTE: scripts reference each other with preload(), not class_name, so the project
## runs even before the editor has rebuilt its global class cache.

const Settings := preload("res://data/config/game_settings.gd")
const InputSetup := preload("res://systems/input_setup.gd")
const SETTINGS_PATH := "res://data/config/default_settings.tres"

var settings: Settings = _load_settings()

## False while a menu/pause screen owns the mouse & keyboard.
var gameplay_input_enabled := true


func _ready() -> void:
	InputSetup.apply()


func _load_settings() -> Settings:
	var res := load(SETTINGS_PATH) as Settings
	if res == null:
		push_warning("GameConfig: %s missing, using defaults." % SETTINGS_PATH)
		res = Settings.new()
	return res


func color_for(index: int) -> Color:
	var colors := settings.player_colors
	if colors.is_empty():
		return Color.WHITE
	return colors[clampi(index, 0, colors.size() - 1)]
