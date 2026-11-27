extends RefCounted
## Lava hurt-zones are Area3Ds on the fire-zone layer with meta "lava" (made by LavaFlow /
## LavaPool). Health asks lava_at(); arrows crossing them light up; standing in them sets you
## Burning (fire contact) on top of the lava damage.


static func make_box(parent: Node, xf: Transform3D, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = "LavaZone"
	a.collision_layer = WorldRules.FIRE_ZONE_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.set_meta("fire_zone", true)
	a.set_meta("lava", true)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	a.add_child(cs)
	parent.add_child(a)
	a.transform = xf
	return a


static func lava_at(world: World3D, point: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = point
	q.collision_mask = WorldRules.FIRE_ZONE_LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r in world.direct_space_state.intersect_point(q, 4):
		if (r.collider as Node).has_meta("lava"):
			return true
	return false
