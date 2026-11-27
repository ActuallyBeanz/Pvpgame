@tool
extends Node3D
## A wooden bridge between its two child markers "A" and "B" (drag them onto the banks in the
## editor; it rebuilds live). Gentle arch, deck meets the ground flush at both ends (no step),
## posts + rails both sides, lantern posts at the ends, trestle piers down to the river bed.
## Collision: one smooth walkway per deck section + low side rails (you can't fall off by
## accident, you can jump over them). Pieces come from art_src/props/make_props_bridge.py.

const DECK := preload("res://assets/models/props/bridge_deck.glb")
const POST := preload("res://assets/models/props/bridge_post.glb")
const RAIL := preload("res://assets/models/props/bridge_rail.glb")
const PIER := preload("res://assets/models/props/bridge_pier.glb")
const LANTERN := preload("res://assets/models/props/bridge_lantern.glb")

@export var width := 4.0                   ## the deck model is 4 m wide (scaled to this)
@export var arch := 0.06                   ## rise in the middle, as a share of the length
@export var max_rise := 1.8
@export var lanterns := true
@export var terrain_path: NodePath = ^"../../Terrain"
@export var rebuild_now := false:          ## tick to force a rebuild
	set(v):
		_last = ""

var _built: Node3D
var _last := ""


func _process(_delta: float) -> void:
	var a := get_node_or_null("A") as Node3D
	var b := get_node_or_null("B") as Node3D
	if a == null or b == null:
		return
	var key := "%s|%s|%s|%s|%s" % [a.position, b.position, width, arch, lanterns]
	if key != _last:
		_last = key
		_rebuild(a.position, b.position)


func _ground(p: Vector3) -> float:
	var t := get_node_or_null(terrain_path)
	if t and t.has_method("height_at"):
		var g := global_transform * p
		return t.height_at(g.x, g.z) - global_position.y
	return -50.0


func _deck_point(a: Vector3, b: Vector3, t: float) -> Vector3:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var rise := minf(length * arch, max_rise)
	return a.lerp(b, t) + Vector3.UP * rise * 4.0 * t * (1.0 - t)


func _rebuild(a: Vector3, b: Vector3) -> void:
	if _built:
		_built.free()
	_built = Node3D.new()
	_built.name = "_Built"
	add_child(_built)
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	if flat < 1.0:
		return
	var body := StaticBody3D.new()
	body.name = "Walkway"
	body.set_meta("material", "wood")
	body.add_to_group("hook_targets")
	_built.add_child(body)
	var n := maxi(2, ceili(flat))
	var sx := width / 4.0
	for i in n:
		var p0 := _deck_point(a, b, float(i) / n)
		var p1 := _deck_point(a, b, float(i + 1) / n)
		var d := p1 - p0
		var bs := Basis.looking_at(d.normalized(), Vector3.UP)
		var mid := (p0 + p1) * 0.5
		var seg := Transform3D(bs, mid)
		_piece(DECK, seg * Transform3D(Basis().scaled(Vector3(sx, 1.0, d.length())), Vector3.ZERO))
		# walkway collision: a slab whose top is the deck surface
		_box(body, seg * Transform3D(Basis(), Vector3(0, -0.1, 0)), Vector3(width, 0.2, d.length() + 0.05))
		for side in [-1.0, 1.0]:
			var off := Vector3(side * (width * 0.5 - 0.1), 0, 0)
			_piece(RAIL, seg * Transform3D(Basis().scaled(Vector3(1, 1, d.length())), off))
			_box(body, seg * Transform3D(Basis(), off + Vector3(0, 0.55, 0)), Vector3(0.15, 1.1, d.length()))
			if i % 2 == 0:
				_piece(POST, Transform3D(bs, p0 + bs * off))
		# trestle pier where the bed is far below
		if i > 0 and i < n - 1 and i % 4 == 2:
			var bed := _ground(mid)
			var depth := mid.y - bed
			if depth > 1.2 and bed > -40.0:
				_piece(PIER, Transform3D(Basis.looking_at(Vector3(d.x, 0, d.z).normalized(), Vector3.UP) * Basis().scaled(Vector3(sx, depth, 1.0)), mid + Vector3.DOWN * 0.24))
	var last := Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), b)
	for side in [-1.0, 1.0]:
		_piece(POST, last * Transform3D(Basis(), Vector3(side * (width * 0.5 - 0.1), 0, 0)))
	if lanterns:
		var dir := (b - a)
		dir.y = 0.0
		dir = dir.normalized()
		var right := dir.cross(Vector3.UP).normalized()
		_lantern(a - dir * 0.4 + right * (width * 0.5 + 0.35), dir)
		_lantern(b + dir * 0.4 - right * (width * 0.5 + 0.35), -dir)


func _lantern(at: Vector3, facing: Vector3) -> void:
	# the lantern's arm points +Z in the model: turn it toward the deck centre line
	var right := facing.cross(Vector3.UP).normalized()
	var t := Transform3D(Basis.looking_at(right, Vector3.UP), at)
	_piece(LANTERN, t)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.45)
	l.light_energy = 1.6
	l.omni_range = 9.0
	_built.add_child(l)
	l.position = at + Vector3.UP * 2.1 + (t.basis * Vector3(0, 0, 0.65))


func _piece(ps: PackedScene, xf: Transform3D) -> void:
	var n := ps.instantiate() as Node3D
	_built.add_child(n)
	n.transform = xf


func _box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	cs.transform = xf
