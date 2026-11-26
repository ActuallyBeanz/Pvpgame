extends Node
## Water bodies of the current map (autoload "Water"). Maps register their sea / lakes / lava
## here; swimming and anything else that cares asks level_at(). Pure data: no physics bodies,
## so it costs nothing on maps without water (the test arena).
##   kind "water": swimmable.  "frozen": solid ice on top (walkable).  "lava": hurts (later).

var sea_level := -INF                        ## -INF = no sea on this map
var bodies: Array[Dictionary] = []           ## { center: Vector2 (x,z), radius, level, kind }


func clear() -> void:
	sea_level = -INF
	bodies.clear()


func add_body(center_xz: Vector2, radius: float, level: float, kind := "water") -> void:
	bodies.append({ "center": center_xz, "radius": radius, "level": level, "kind": kind })


## Surface height of swimmable water over this spot (-INF = none). Doesn't check the ground:
## the caller compares its own feet / the terrain against it.
func level_at(pos: Vector3) -> float:
	var lvl := sea_level
	var p := Vector2(pos.x, pos.z)
	for b in bodies:
		if b.kind == "water" and p.distance_to(b.center) <= b.radius:
			lvl = maxf(lvl, b.level)
	return lvl


## How deep under the surface this point is (<= 0 = above water / no water).
func depth_at(pos: Vector3) -> float:
	var lvl := level_at(pos)
	return lvl - pos.y if lvl > -INF else 0.0


func kind_at(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	for b in bodies:
		if p.distance_to(b.center) <= b.radius and pos.y <= b.level + 0.5:
			return b.kind
	return "water" if sea_level > -INF and pos.y < sea_level else ""
