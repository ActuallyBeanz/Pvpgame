extends Node
## Autoload: WorldRules. Looks up materials / reactions and routes hits to Reactive
## props. Weapons build a hit with make_hit() and hand it to deliver_hit().

const RULES_PATH := "res://data/registry/world_rules.tres"
const FIRE_ZONE_LAYER := 8          ## physics layer 4: fire zones (braziers) that light arrows

var rules: Resource
var _materials: Dictionary = {}     # id -> MaterialDef


func _ready() -> void:
	rules = load(RULES_PATH)
	if rules == null:
		push_error("WorldRules: could not load %s" % RULES_PATH)
		return
	for m in rules.materials:
		if m:
			_materials[m.id] = m


func get_material(id: String) -> Resource:
	if not _materials.has(id):
		push_warning("WorldRules: unknown material '%s'" % id)
		return null
	return _materials[id]


## hit: { damage, action, element, heat, dir }
func make_hit(damage: float, action: String, element := "", dir := Vector3.ZERO) -> Dictionary:
	var heat: float = rules.fire_hit_heat if element == "fire" else 0.0
	if element != "" and damage > 0.0:
		damage += rules.element_bonus_damage
	return { "damage": damage, "action": action, "element": element, "heat": heat, "dir": dir }


func hit_tags(hit: Dictionary) -> PackedStringArray:
	var t := PackedStringArray()
	for k in ["action", "element"]:
		if str(hit.get(k, "")) != "":
			t.append(str(hit[k]))
	return t


func damage_mult(material_id: String, tags: PackedStringArray) -> float:
	var m := 1.0
	for r in rules.reactions:
		if r and (r.material == material_id or r.material == "*") and tags.has(r.tag):
			m *= r.damage_mult
	return m


func effects(material_id: String, tags: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rules.reactions:
		if r and r.effect != "none" and (r.material == material_id or r.material == "*") and tags.has(r.tag):
			out.append(r.effect)
	return out


func element_color(element: String) -> Color:
	return rules.element_colors.get(element, Color.WHITE)


## The Reactive component on (or above) a collider, or null.
func reactive_of(col: Object) -> Node:
	var n := col as Node
	while n:
		if n.has_meta("reactive"):
			var r: Variant = n.get_meta("reactive")
			return r if is_instance_valid(r) else null
		n = n.get_parent()
	return null


## Called by projectiles on every peer. cosmetic = remote copy (feedback only).
func deliver_hit(col: Object, hit: Dictionary, cosmetic: bool) -> bool:
	var handled := false
	if col and col.has_method("react_to_hit_info"):
		col.react_to_hit_info(hit, cosmetic)
		handled = true
	elif col and col.has_method("react_to_hit"):
		col.react_to_hit(float(hit.damage), hit.dir, cosmetic)
		handled = true
	var r := reactive_of(col)
	if r:
		r.receive_hit(hit, cosmetic)
		handled = true
	return handled


## Fire zone (lit brazier etc.) crossed by the segment from -> to, if any.
func fire_zone_on_segment(world: World3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, FIRE_ZONE_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.hit_from_inside = true
	var res := world.direct_space_state.intersect_ray(q)
	return not res.is_empty() and (res.collider as Node).has_meta("fire_zone")


## Is this point inside a fire zone (brazier / torch flame)? Used to light a drawn arrow.
func fire_zone_at(world: World3D, point: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = point
	q.collision_mask = FIRE_ZONE_LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r in world.direct_space_state.intersect_point(q, 4):
		if (r.collider as Node).has_meta("fire_zone"):
			return true
	return false
