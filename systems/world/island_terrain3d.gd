extends Node3D
## The island's ground, now a Terrain3D terrain you can sculpt and paint in the editor
## (select the Terrain3D node: sculpt / paint / foliage tools in the toolbar).
## This node answers the questions gameplay asks the ground (same API as the old PNG terrain):
##   height_at(x, z), biome_at(x, z), slope_deg(x, z), half_w()
## Biome = the texture painted there (paint "snow" and the scatter / loot rules treat it as snow).
## Built once from the old PNGs by tools/map/build_island_terrain.tscn.

## Texture layers in Terrain3D order. 0..11 are biomes, 12..14 cliff rock (overlay on slopes).
const LAYERS: Array[String] = ["grass", "forest", "snow", "ash", "sand", "beach", "path", "plaza", "bed",
	"lava", "ice", "mesa", "rock", "basalt", "redrock"]
const BIOMES: Array[String] = ["grass", "forest", "snow", "ash", "sand", "beach", "path", "plaza", "bed",
	"lava", "ice", "mesa"]
const CLIFF_OF := { "ash": "basalt", "lava": "basalt", "sand": "redrock", "mesa": "redrock" }
## biome.png paint colours (the old generator) - only used by the converter
const PALETTE := {
	"grass": Color8(96, 168, 70), "forest": Color8(64, 128, 52), "snow": Color8(232, 238, 248),
	"ash": Color8(78, 66, 64), "sand": Color8(226, 188, 118), "beach": Color8(238, 214, 160),
	"path": Color8(176, 140, 96), "plaza": Color8(168, 162, 150), "bed": Color8(104, 96, 82),
	"lava": Color8(255, 96, 24), "ice": Color8(176, 220, 245), "mesa": Color8(204, 140, 84),
}

@export var h_min := -8.0                  ## what "off the map" counts as
@export var map_half := 256.0              ## half the terrain width in metres

var t3d: Node                              ## the Terrain3D node (child)


func _ready() -> void:
	build()


## Kept for the match script (the old terrain built itself here).
func build() -> void:
	if t3d:
		return
	for c in get_children():
		if c.get_class() == "Terrain3D":
			t3d = c
	if t3d == null:
		push_error("island_terrain3d: no Terrain3D child")
		return
	t3d.collision_mode = 3                       # Full / Game: the whole island collides (far projectiles too)


func half_w() -> float:
	return map_half - 0.5


func height_at(x: float, z: float) -> float:
	if t3d == null:
		return h_min
	var h: float = t3d.data.get_height(Vector3(x, 0.0, z))
	return h if not is_nan(h) else h_min


func biome_at(x: float, z: float) -> String:
	if t3d == null or absf(x) > map_half or absf(z) > map_half:
		return ""
	var id: int = t3d.data.get_control_base_id(Vector3(x, 0.0, z))
	return LAYERS[id] if id >= 0 and id < LAYERS.size() else "grass"


func slope_deg(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return rad_to_deg(atan(Vector2(dx, dz).length() * 0.5))


static func nearest_biome(c: Color) -> String:
	var best := "grass"
	var bd := 1e9
	for k: String in PALETTE:
		var p: Color = PALETTE[k]
		var dd := (c.r - p.r) * (c.r - p.r) + (c.g - p.g) * (c.g - p.g) + (c.b - p.b) * (c.b - p.b)
		if dd < bd:
			bd = dd
			best = k
	return best
