extends Node
## Element reactions test (host only, no player input):
##  1. arrow flies through the brazier -> catches fire -> sets crate Yard_1 burning
##  2. fire spreads along the crate chain (Yard_2, Yard_3) and melts ice Yard_4
##  3. two blunt (boomerang) hits shatter ice Yard_5
##  4. frost puts out a burning tree; a plain arrow barely scratches ice
##   godot --headless res://tests/reactions_smoke.tscn
## Run with a window to also save screenshots to res://logs/.

const ArrowScene := preload("res://scenes/weapons/arrow_projectile.tscn")
const BowStats := preload("res://data/items/bow_basic_stats.tres")

var _step := 0
var _t := 0.0
var _arrow: Node3D
var _seen_burning := {}
var _shots := DisplayServer.get_name() != "headless"


func _ready() -> void:
	if get_tree().current_scene == self:
		get_tree().root.add_child.call_deferred(get_script().new())
		return
	Lobby.local_profile = { "name": "Pyro", "color": 2 }
	Lobby.roster_changed.connect(func() -> void:
		if Lobby.can_start():
			Lobby.start_match.call_deferred())
	NetworkManager.host()


func _yard(i: int) -> Node:
	return get_tree().current_scene.get_node_or_null("Props/Yard_%d" % i)


func _r(i: int) -> Node:
	var y := _yard(i)
	return y.get_node("Reactive") if y else null


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return
	_t += delta
	if _t > 40.0:
		_done(false, "timeout at step %d (time %.1f)" % [_step, _t])
	var scene := get_tree().current_scene
	if scene == null or not scene.has_node("Props/Yard_0"):
		return
	for i in [1, 2, 3]:
		var r := _r(i)
		if r and r.burning:
			_seen_burning[i] = true
	match _step:
		0:
			if scene.has_node("Players/1"):
				Engine.time_scale = 3.0
				_r(4).destroyed.connect(func() -> void: _ice4_broke = true)
				_arrow = ArrowScene.instantiate()
				scene.add_child(_arrow)
				var from := Vector3(8, 2.1, 3.13)
				var to: Vector3 = _yard(1).global_position + Vector3(0, 0.85, 0)
				_arrow.launch(from, (to - from).normalized() * 60.0, BowStats, 20.0, RID())
				_next()
		1:
			if is_instance_valid(_arrow) and _arrow.element == "fire" and _r(1).burning:
				print("[react] arrow lit by brazier, crate burning (hp %.0f)" % _r(1).hp)
				_shot("01_crate_lit")
				_next()
			elif _t > 3.0:
				_done(false, "arrow lit=%s crate burning=%s" % [
					_arrow.element if is_instance_valid(_arrow) else "?", _r(1).burning if _r(1) else "gone"])
		2:
			if _t > 3.0 and not _shot_taken:
				_shot("02_spreading")
				_shot_taken = true
			if _yard(1) == null and _seen_burning.has(2) and _seen_burning.has(3) and _ice4_broke:
				print("[react] chain burned: crates 1-3 caught fire, ice block 4 melted (%.1fs)" % _t)
				_next()
		3:
			var ice := _r(5)
			var hp0: float = ice.hp
			ice.receive_hit(WorldRules.make_hit(8.0, "pierce"), false)
			var after_arrow: float = ice.hp
			print("[react] plain arrow on ice: %.0f -> %.0f" % [hp0, after_arrow])
			if hp0 - after_arrow > 5.0:
				_done(false, "arrow did too much to ice")
				return
			ice.receive_hit(WorldRules.make_hit(6.0, "blunt"), false)
			ice.receive_hit(WorldRules.make_hit(6.0, "blunt"), false)
			_next()
		4:
			if _r(5).dead and not _yard(5).visible:
				print("[react] two blunt hits shattered ice block 5")
				_next()
			elif _t > 1.0:
				_done(false, "ice 5 survived blunt hits (hp %.0f)" % _r(5).hp)
		5:
			var tree: Node = scene.get_node("Props/Tree_0/Reactive")
			tree.receive_hit(WorldRules.make_hit(0.0, "", "fire"), false)
			if not tree.burning:
				_done(false, "fire hit didn't ignite tree")
				return
			tree.receive_hit(WorldRules.make_hit(0.0, "", "frost"), false)
			if tree.burning:
				_done(false, "frost didn't extinguish tree")
				return
			print("[react] frost put out the burning tree (hp %.0f)" % tree.hp)
			_next()
		6:
			if not _r(5).dead and _yard(5).visible and _r(5).hp >= 40.0:
				print("[react] ice block 5 respawned (%.1fs)" % _t)
				_done(true, "reactions OK")
			elif _t > 8.0:
				_done(false, "ice 5 did not respawn")

var _shot_taken := false
var _ice4_broke := false


func _next() -> void:
	_step += 1
	_t = 0.0


func _shot(tag: String) -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	img.save_png("res://logs/react_%s.png" % tag)


func _done(ok: bool, msg: String) -> void:
	Engine.time_scale = 1.0
	print("[react] %s %s" % ["PASS" if ok else "FAIL", msg])
	get_tree().quit(0 if ok else 1)
	set_process(false)
