class_name GameSettings
extends Resource
## Central tunables. Edit res://data/config/default_settings.tres in the Inspector.
## Gameplay systems read these through the GameConfig autoload: never hardcode values.

@export_group("Network")
@export var port: int = 24565
@export var default_address: String = "127.0.0.1"
@export_range(2, 32) var max_players: int = 12
@export_range(1, 32) var min_players_to_start: int = 1
@export var require_all_ready: bool = true
@export_range(2.0, 60.0) var join_timeout_sec: float = 8.0

@export_group("Profile")
@export_range(3, 24) var name_max_length: int = 16
@export var player_colors: PackedColorArray = PackedColorArray([
	Color("2e8b57"), Color("d94f30"), Color("3a7bd5"), Color("e8b730"),
	Color("8e44ad"), Color("e67e22"), Color("1abc9c"), Color("ecf0f1"),
	Color("c0392b"), Color("34495e"), Color("ff6fae"), Color("7f8c8d"),
])

@export_group("Match")
@export_file("*.tscn") var match_scene: String = "res://scenes/match/test_arena.tscn"   ## fallback / smoke tests ("Host Test Arena")
@export_file("*.tscn") var island_scene: String = "res://scenes/match/island.tscn"   ## "Host (Island)"
## Test arena only. The real map uses spawn rules from the map config (M3).
@export var test_spawn_radius: float = 6.0
