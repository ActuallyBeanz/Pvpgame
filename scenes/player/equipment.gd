extends Node
## Player equipment: owned weapons (slots), the current weapon + ammo, draw/holster,
## and per-weapon-type use:
##   action_tag "shoot" (bow):  hold LMB to draw & aim, release to fire
##   action_tag "throw" (boomerang): LMB throws; homes in on your focus lock target
## Owner-authoritative for its own state (synced via the player's $Sync);
## pickups are granted by the host (see scenes/items/pickup.gd).
## Inventory: 9 hotbar slots (keys 1-9) + bag slots. Tab opens the bag: drag items
## between any slots (move_item). Only weapons on the hotbar can be equipped.
## Controls: 1-9 pick weapon (inventory open + hovering a slot: put it on that hotbar
## slot) · Q draw/holster · LMB use · E pick up · Tab inventory

signal changed

const ArrowScene := preload("res://scenes/weapons/arrow_projectile.tscn")
const BoomerangScene := preload("res://scenes/weapons/boomerang_projectile.tscn")
const BoomerangAim := preload("res://scenes/player/boomerang_aim.gd")
const Melee := preload("res://scenes/player/melee.gd")
const HookTool := preload("res://scenes/player/hook_tool.gd")
const Motor := preload("res://scenes/player/movement_motor.gd")
const FX := preload("res://systems/components/element_fx.gd")

@export var pickup_radius := 2.2
@export var holster_swap_delay := 0.25     ## when the model moves hand <-> back during the anim
@export var inventory_size := 9             ## hotbar slots (keys 1-9)
@export var bag_size := 18                  ## extra slots shown when the inventory (Tab) is open
@export var lit_arrow_burn_time := 8.0     ## a lit nocked arrow burns out after this (OoT deku-stick style)
@export var nock_forward := 0.62           ## nocked arrow tip distance in front of the bow hand

# Synced to everyone through player.tscn > Sync.
var sync_weapon_id := ""
var sync_drawn := false
var sync_aiming := false
var sync_thrown := false                   ## boomerang is out of your hand
var sync_arrow_element := ""               ## nocked arrow lit by holding it in a fire ("fire")
var sync_shield_id := ""                   ## shield worn on the off hand (separate from weapon slots)
var sync_blocking := false                 ## shield raised (F)
var sync_hook_phase := 0                   ## HookTool.Phase: grapple claw idle / out / back / pulling
var sync_hook_tip := Vector3.ZERO          ## grapple claw position while it's out

var weapons: Array[String] = []            ## owned weapon ids, hotbar order (owner only)
var inventory: Array[String] = []          ## item id per slot, "" = empty (owner only): [0, inventory_size) = hotbar, then bag
var ui_hover_slot := -1                    ## set by the inventory UI: slot under the mouse (-1 = none)
var ammo: Dictionary = {}                  ## item id -> total count across all its stacks (derived from slot_counts)
var slot_counts: Array[int] = []           ## stack size per inventory slot (stackables; weapons/shields = 1)
var charge := 0.0                          ## 0..1 bow draw progress
var nearest_pickup: Node3D

var _player: CharacterBody3D
var _model: Node3D
var _weapon_vis: Node3D
var _worn_vis: Node3D
var _applied := ""                         ## last visual state applied
var _cooldown := 0.0
var _swap_timer := -1.0
var _drawing := false
var _boomerang: Node3D
var _need_redraw := false                  ## a roll cancelled the bow draw: release LMB first
var _nock_vis: Node3D                      ## arrow shown on the string while aiming
var _nock_flames: Node3D
var _lit_timer := 0.0


var _boom_aim: Node
var _boom_aiming := false
var melee: Node
var hook: Node                              ## grapple tool logic (scenes/player/hook_tool.gd)
var bomb: Node                              ## Blastgourd bombs (scenes/player/bomb_tool.gd)
const BombTool := preload("res://scenes/player/bomb_tool.gd")
const ToolsScript := preload("res://scenes/player/tools.gd")
var tools: Node                             ## fan / staff / rod / trap (scenes/player/tools.gd)
const PickupDropScene := preload("res://scenes/items/pickup.tscn")
var _shield_vis: Node3D


func _ready() -> void:
	_player = get_parent()
	inventory.resize(inventory_size + bag_size)
	inventory.fill("")
	slot_counts.resize(inventory.size())
	slot_counts.fill(0)
	_boom_aim = BoomerangAim.new()
	_boom_aim.name = "BoomerangAim"
	add_child(_boom_aim)
	_boom_aim.setup(_player)
	melee = Melee.new()
	melee.name = "Melee"
	add_child(melee)
	melee.setup(self, _player)
	hook = HookTool.new()
	hook.name = "Hook"
	add_child(hook)
	hook.setup(self, _player)
	bomb = BombTool.new()
	bomb.name = "Bomb"
	add_child(bomb)
	bomb.setup(self, _player)
	tools = ToolsScript.new()
	tools.name = "Tools"
	add_child(tools)
	tools.setup(self, _player)


func is_local() -> bool:
	return is_multiplayer_authority()


func weapon() -> Resource:
	return ItemDB.get_item(sync_weapon_id) if sync_weapon_id != "" else null


func stats() -> Resource:
	var w := weapon()
	return w.stats if w else null


func weapon_type() -> String:
	var w := weapon()
	return w.action_tag if w else ""


func ammo_count() -> int:
	var w := weapon()
	return int(ammo.get(w.ammo_item_id, 0)) if w and w.ammo_item_id != "" else 0


func is_aiming() -> bool:
	return sync_aiming and weapon_type() in ["shoot", "throw", "hook", "staff", "rod"]


func move_speed_mult() -> float:
	var s := stats()
	var m: float = s.aim_move_speed_mult if is_aiming() and s and "aim_move_speed_mult" in s else 1.0
	return m * melee.move_mult()


## A two-handed weapon (greatsword, hammer) is out: the shield stays on your back.
func two_handed_drawn() -> bool:
	var s := stats()
	return sync_drawn and s != null and "two_handed" in s and s.two_handed


func shield_item() -> Resource:
	return ItemDB.get_item(sync_shield_id) if sync_shield_id != "" else null


## Sword swings / spin charge / raised shield: face where the camera looks
## (unless focus-locked, which faces the target).
func wants_face_camera() -> bool:
	return melee.busy() or sync_blocking


## Weapon-specific lock-on range (0 = use the focus default). Every weapon can lock on;
## only weapons whose stats say homes_on_lock fly to the target by themselves.
func lock_on_range() -> float:
	var s := stats()
	return float(s.lock_on_range) if s and "lock_on_range" in s else 0.0


# ---------------------------------------------------------------- items
## Called on the owner when the host grants a pickup.
func receive_item(item_id: String, amount: int) -> void:
	var it := ItemDB.get_item(item_id)
	if it == null:
		return
	if it.kind == "weapon":
		var fresh := not inventory.has(item_id)
		if fresh and not _store(item_id):
			print("[equipment] inventory full, can't carry %s" % item_id)
			return
		# amount 0 = a world pickup (starting ammo), > 0 = a dropped stack, < 0 = dropped, no bonus
		var extra: int = it.starting_ammo if amount == 0 else maxi(amount, 0)
		_add_ammo(it.ammo_item_id, extra)
		if fresh and sync_weapon_id == "" and hotbar_index(item_id) >= 0:
			_equip(item_id)
	elif it.kind == "ammo" or it.kind == "material":
		var left := _add_ammo(item_id, maxi(amount, 1), it.kind == "material")
		if left > 0:
			print("[equipment] inventory full, %d %s left behind" % [left, item_id])
	elif it.kind == "shield":
		if _store(item_id):
			sync_shield_id = item_id
			_applied = ""
	print("[equipment] got %s x%d | ammo %s" % [item_id, amount, ammo])
	changed.emit()


# ---------------------------------------------------------------- stacks
## Stackable = counted items (ammo, materials, and weapons that are their own ammo, like bombs).
func is_stackable(item_id: String) -> bool:
	var it := ItemDB.get_item(item_id) if item_id != "" else null
	return it != null and (it.kind == "ammo" or it.kind == "material" or (it.kind == "weapon" and it.ammo_item_id == item_id))


func stack_max(item_id: String) -> int:
	var it := ItemDB.get_item(item_id)
	return maxi(1, it.max_carry) if it else 1


func count_in_slot(slot: int) -> int:
	if slot < 0 or slot >= inventory.size() or inventory[slot] == "":
		return 0
	return slot_counts[slot] if is_stackable(inventory[slot]) else 1


func _sync_totals() -> void:
	ammo.clear()
	# a stack that hits 0 is gone (bombs included)
	var removed := false
	for i in inventory.size():
		if inventory[i] != "" and is_stackable(inventory[i]) and slot_counts[i] <= 0:
			inventory[i] = ""
			slot_counts[i] = 0
			removed = true
	if removed:
		_rebuild_weapons()
		if sync_weapon_id != "" and not inventory.has(sync_weapon_id) and not _weapon_busy():
			_unequip()
	for i in inventory.size():
		var id := inventory[i]
		if id != "" and is_stackable(id):
			ammo[id] = int(ammo.get(id, 0)) + slot_counts[i]


## Use up `n` of a stackable item (arrows, bombs...), from the last stacks first. A weapon
## Emptied stacks free their slot (a used-up bomb stack disappears; if it was in your hand
## you put your hands down once the last one has been thrown).
func consume(item_id: String, n: int) -> void:
	var i := inventory.size() - 1
	while i >= 0 and n > 0:
		if inventory[i] == item_id:
			var take := mini(n, slot_counts[i])
			slot_counts[i] -= take
			n -= take
			if slot_counts[i] <= 0:
				inventory[i] = ""
				slot_counts[i] = 0
		i -= 1
	_sync_totals()
	changed.emit()


## Put an item in the first free slot, hotbar first, then the bag (no-op if already
## carried). false = full.
func _store(item_id: String) -> bool:
	if inventory.has(item_id):
		return true
	var free := inventory.find("")
	if free < 0:
		return false
	inventory[free] = item_id
	slot_counts[free] = 0 if is_stackable(item_id) else 1
	_rebuild_weapons()
	return true


## Materials go to the bag first so they don't crowd weapons off the hotbar.
func _store_bag_first(item_id: String) -> bool:
	if inventory.has(item_id):
		return true
	for i in range(inventory_size, inventory.size()):
		if inventory[i] == "":
			inventory[i] = item_id
			return true
	return _store(item_id)


## Weapons on the hotbar, in slot order (cycle_weapon / ownership for equipping).
func _rebuild_weapons() -> void:
	weapons.clear()
	for i in inventory_size:
		var id := inventory[i]
		var it := ItemDB.get_item(id) if id != "" else null
		if it and it.kind == "weapon":
			weapons.append(id)


## Hotbar slot holding this item, or -1 (in the bag / not carried).
func hotbar_index(item_id: String) -> int:
	var i := inventory.find(item_id)
	return i if i >= 0 and i < inventory_size else -1


func is_hotbar_slot(slot: int) -> bool:
	return slot >= 0 and slot < inventory_size


## Inventory UI: move the item in `from` to `to` (swaps if `to` is taken). Moving the
## equipped weapon off the hotbar unequips it. Refused while that weapon is out of
## your hand (boomerang flying, grapple chain out). Owner only.
func move_item(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= inventory.size() or to >= inventory.size():
		return false
	var a := inventory[from]
	var b := inventory[to]
	if a == "":
		return false
	if a == b and is_stackable(a):
		# same item: merge the stacks (whatever doesn't fit stays behind)
		var add := mini(slot_counts[from], stack_max(a) - slot_counts[to])
		if add <= 0:
			return false
		slot_counts[to] += add
		slot_counts[from] -= add
		if slot_counts[from] <= 0:
			inventory[from] = ""
			slot_counts[from] = 0
		_sync_totals()
		changed.emit()
		return true
	var leaves_hotbar := (a == sync_weapon_id and not is_hotbar_slot(to)) \
		or (b == sync_weapon_id and not is_hotbar_slot(from))
	if sync_weapon_id != "" and leaves_hotbar and _weapon_busy():
		return false
	inventory[from] = b
	inventory[to] = a
	var ca := slot_counts[from]
	slot_counts[from] = slot_counts[to]
	slot_counts[to] = ca
	_rebuild_weapons()
	if sync_weapon_id != "" and hotbar_index(sync_weapon_id) < 0:
		_unequip()
	changed.emit()
	return true


## Split `n` off a stack into the first empty slot (bag first). Owner only.
func split_stack(slot: int, n: int) -> bool:
	var id := inventory[slot] if slot >= 0 and slot < inventory.size() else ""
	if id == "" or not is_stackable(id) or n <= 0 or n >= slot_counts[slot]:
		return false
	var free := _free_slot(true)
	if free < 0:
		return false
	inventory[free] = id
	slot_counts[free] = n
	slot_counts[slot] -= n
	_sync_totals()
	changed.emit()
	return true


## Throw `n` of the item in `slot` on the ground in front of you (n <= 0 = the whole stack).
## Every peer spawns the same named pickup, so anyone can grab it. Owner only.
var _drop_seq := 0
func drop_item(slot: int, n: int = 0, scatter := false) -> bool:
	var id := inventory[slot] if slot >= 0 and slot < inventory.size() else ""
	if id == "":
		return false
	var it := ItemDB.get_item(id)
	if (id == sync_weapon_id or id == sync_shield_id) and _weapon_busy() and not scatter:
		return false
	var amount := 0
	if is_stackable(id):
		var have := slot_counts[slot]
		amount = have if n <= 0 else mini(n, have)
		slot_counts[slot] -= amount
		if slot_counts[slot] <= 0:
			inventory[slot] = ""
			slot_counts[slot] = 0
	else:
		inventory[slot] = ""
		slot_counts[slot] = 0
		amount = -1                              # dropped gear: no starting-ammo bonus on re-pickup
	if id == sync_weapon_id and not inventory.has(id):
		_unequip()
	if id == sync_shield_id and not inventory.has(id):
		sync_shield_id = ""
		sync_blocking = false
		_applied = ""
	_rebuild_weapons()
	_sync_totals()
	changed.emit()
	var fwd: Vector3 = -_player.model_root.global_basis.z
	var at: Vector3 = _player.global_position + fwd * 1.3
	if scatter:   # death: spill everything around where you fell
		var a := randf() * TAU
		at = _player.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.6, 2.2)
	_drop_seq += 1
	rpc_drop.rpc("Drop_%d_%d" % [multiplayer.get_unique_id(), _drop_seq], id, amount, at)
	Audio.play("ui.select", -4.0, 0.8)
	return true


@rpc("authority", "call_local", "reliable")
func rpc_drop(node_name: String, id: String, amount: int, at: Vector3) -> void:
	var scene := get_tree().current_scene
	var root := scene.get_node_or_null("Dropped")
	if root == null:
		root = Node3D.new()
		root.name = "Dropped"
		scene.add_child(root)
	var pu := PickupDropScene.instantiate()
	pu.name = node_name
	pu.item_id = id
	pu.amount = amount
	root.add_child(pu)
	pu.global_position = at


## Bomb thrown / set down: if that was the last one, put your hands down.
func after_bomb_released() -> void:
	if sync_weapon_id != "" and not inventory.has(sync_weapon_id):
		_unequip()
		changed.emit()


func _weapon_busy() -> bool:
	return sync_thrown or (hook != null and hook.busy()) or (bomb != null and bomb.busy())


# ---------------------------------------------------------------- bare hands
@export var punch_cooldown := 0.45
@export var punch_reach := 1.1
@export var punch_damage := 3.0
@export var punches_per_wood := 2          ## punch a tree this many times for 1 Wood
@export var punch_damage_tree := 1.0        ## trees break eventually (they have ~40 hp)
var _punch_cd := 0.0


func _update_punch(delta: float) -> void:
	_punch_cd = maxf(0.0, _punch_cd - delta)
	if not Input.is_action_just_pressed("attack") or _punch_cd > 0.0 or _player.motor.action_locked():
		return
	_punch_cd = punch_cooldown
	if _model:
		_model.play_action(&"Unarmed_Melee_Attack_Punch_A", 0.4)
	rpc_punch_anim.rpc()
	var fwd: Vector3 = -_player.model_root.global_basis.z
	var centre := _player.global_position + Vector3.UP * 1.0 + fwd * punch_reach * 0.7
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), centre)
	q.collision_mask = 3
	q.exclude = [_player.get_rid()]
	for r in _player.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var col: Object = r.collider
		if col == null or not (col is Node3D):
			continue
		var node := col as Node3D
		if is_tree(node):
			_punch_tree(node, centre)
			return
		if col.has_method("react_to_hit_info") or col.has_method("react_to_hit") or WorldRules.reactive_of(col) != null:
			WorldRules.deliver_hit(col, WorldRules.make_hit(punch_damage, "blunt", "", fwd), false)
			Audio.play_at("target.hit", centre, -4.0, 1.3)
			return
	Audio.play_at("sword.swing", centre, -8.0, 1.6)


## Is this a tree? (grapple-able wooden body: the island trees and the oak scene)
static func is_tree(n: Object) -> bool:
	return n is Node3D and (n as Node3D).is_in_group("hook_targets") and str((n as Node3D).get_meta("material", "")) == "wood"


## Hitting a tree knocks loose Wood: every `hits_per_wood` hits gives 1 (punches: 2, any weapon: 1).
## Counts live on the tree; the tree itself takes the hit's damage and breaks when it runs out.
func harvest_tree(n: Object, at: Vector3, hits_per_wood: int) -> void:
	if not is_local() or not is_tree(n):
		return
	var tree := n as Node3D
	var hits: int = int(tree.get_meta("wood_hits", 0)) + 1
	tree.set_meta("wood_hits", hits)
	FX.burst(at, get_tree().current_scene, Color(0.4, 0.62, 0.25), 6, 0.05, 2.5)
	if hits % maxi(1, hits_per_wood) == 0:
		receive_item("wood", 1)
		Audio.play("item.get", -6.0, 1.25)


func _punch_tree(tree: Node3D, at: Vector3) -> void:
	Audio.play_at("wood.hit", at, 0.0, randf_range(0.9, 1.1))
	WorldRules.deliver_hit(tree, WorldRules.make_hit(punch_damage_tree, "blunt", "", -_player.model_root.global_basis.z), false)
	harvest_tree(tree, at, punches_per_wood)


@rpc("authority", "call_remote", "unreliable")
func rpc_punch_anim() -> void:
	if _model:
		_model.play_action(&"Unarmed_Melee_Attack_Punch_A", 0.4)


## Put the current weapon away completely (nothing in hand or on the back).
func _unequip() -> void:
	melee.cancel()
	_release(false)
	_cancel_boomerang_aim()
	if hook:
		hook.cancel()
	if bomb:
		bomb.cancel()
	sync_weapon_id = ""
	sync_drawn = false
	sync_aiming = false
	_applied = ""
	if _player.camera_rig:
		_player.camera_rig.set_aim(false)


## Add `n` of a stackable item: tops up existing stacks, then starts new ones (bag first for
## materials, hotbar first otherwise). Returns how many didn't fit.
func _add_ammo(ammo_id: String, n: int, bag_first := false) -> int:
	if ammo_id == "" or n <= 0 or ItemDB.get_item(ammo_id) == null:
		return 0
	var cap := stack_max(ammo_id)
	for i in inventory.size():
		if n <= 0:
			break
		if inventory[i] == ammo_id:
			var add := mini(n, cap - slot_counts[i])
			if add > 0:
				slot_counts[i] += add
				n -= add
	while n > 0:
		var free := _free_slot(bag_first)
		if free < 0:
			break
		inventory[free] = ammo_id
		slot_counts[free] = mini(n, cap)
		n -= slot_counts[free]
	_rebuild_weapons()
	_sync_totals()
	return n


func _free_slot(bag_first: bool) -> int:
	if bag_first:
		for i in range(inventory_size, inventory.size()):
			if inventory[i] == "":
				return i
	return inventory.find("")


## Switch to a weapon you own and draw it.
func _equip(item_id: String) -> void:
	melee.cancel()
	if item_id == sync_weapon_id:
		_set_drawn(not sync_drawn)
		return
	_release(false)
	hook.cancel()
	sync_weapon_id = item_id
	sync_drawn = false
	_applied = ""
	_set_drawn(true)
	changed.emit()


# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if _model == null:
		_find_model()
	if is_local():
		_local_update(delta)
	if _swap_timer >= 0.0:
		_swap_timer -= delta
		if _swap_timer < 0.0:
			_applied = ""  # force visual refresh now
	_refresh_visuals()
	_update_nock(delta)
	if _model:
		var w := weapon()
		var sh := shield_item()
		var on_chain := sync_hook_phase != HookTool.Phase.IDLE and weapon_type() == "hook"
		if sync_blocking and sh:
			_model.set_aiming(true, sh.stats.block_anim, &"")
		else:
			# grapple: the arm stays pointed out while the chain is out
			# two-handed weapons (greatsword, hammer) are carried in both hands (their aim_anim pose)
			_model.set_aiming((sync_aiming or on_chain or two_handed_drawn()) and sync_drawn, w.aim_anim if w else &"", w.shoot_anim if w else &"")
	hook.update_visuals()


func _local_update(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _player.sync_dead:
		_stop_combat_input()
		nearest_pickup = null
		return
	_update_nearest_pickup()
	if not GameConfig.gameplay_input_enabled:
		_stop_combat_input()
		return
	# Walking-around keys still work with the inventory open (pick up, hotbar keys).
	if Input.is_action_just_pressed("interact") and nearest_pickup:
		nearest_pickup.request_take()
	for i in inventory_size:
		if not Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			continue
		if GameConfig.inventory_open and ui_hover_slot >= 0:
			move_item(ui_hover_slot, i)   # hover an item + press 1-9: put it on that hotbar slot
		elif inventory[i] != "":
			var slot_item := ItemDB.get_item(inventory[i])
			if slot_item and slot_item.kind == "weapon" and not _weapon_busy():
				_equip(inventory[i])
		elif sync_weapon_id != "" and not _weapon_busy():
			_unequip()                # empty hotbar slot = bare hands (punch)
			changed.emit()
	if Input.is_action_just_pressed("cycle_weapon") and weapons.size() > 1 and not _weapon_busy():
		_equip(weapons[(weapons.find(sync_weapon_id) + 1) % weapons.size()])
	if not GameConfig.combat_input_enabled():
		_stop_combat_input()
		return
	if _player.motor.underwater():
		# under the surface: weapon away, lit arrow doused (at the surface you can still fight)
		_stop_combat_input()
		if sync_drawn and not _weapon_busy():
			_set_drawn(false)
		if sync_arrow_element != "":
			_extinguish_nock()
		return
	melee.update(delta)
	var w := weapon()
	if w == null:
		_update_punch(delta)          # bare hands: punch (trees give wood)
		return
	if Input.is_action_just_pressed("toggle_weapon") and not melee.busy() and not hook.busy() and not bomb.busy():
		_release(false)
		_set_drawn(not sync_drawn)
	if Input.is_action_just_pressed("attack") and not sync_drawn and (not sync_blocking or melee.focus_guard):
		_set_drawn(true)
		if w.action_tag == "slash":
			melee.queue_draw_slash()
		return
	match w.action_tag:
		"shoot":
			_update_bow(delta)
		"throw":
			_update_boomerang()
		"hook":
			hook.update(delta)
		"bomb":
			bomb.update(delta)
		"fan", "staff", "rod", "trap":
			tools.update(delta)


## Paused / inventory open: let go of everything that's held (draw, aim, charge, block).
func _stop_combat_input() -> void:
	_release(false)
	_cancel_boomerang_aim()
	melee.cancel()
	if hook:
		hook.stop_aim()
	if bomb:
		bomb.cancel()
	if tools:
		tools.stop()
	sync_aiming = false
	sync_blocking = false
	_player.camera_rig.set_aim(false)


func _update_bow(delta: float) -> void:
	var s := stats()
	var holding := Input.is_action_pressed("attack")
	# Rolling drops the arrow: no shooting mid-roll, and you have to redraw afterwards.
	if _player.motor.state == Motor.State.ROLL:
		if _drawing or charge > 0.0:
			_release(false)
		_need_redraw = _need_redraw or holding
		sync_aiming = false
		_player.camera_rig.set_aim(false, s)
		return
	if _need_redraw:
		if holding and not Input.is_action_just_pressed("attack"):
			sync_aiming = false
			_player.camera_rig.set_aim(false, s)
			return
		_need_redraw = false
	var wants_aim := sync_drawn and _swap_timer < 0.0 and holding
	sync_aiming = wants_aim
	if wants_aim and ammo_count() > 0 and _cooldown <= 0.0:
		_drawing = true
		charge = minf(1.0, charge + delta / s.draw_time)
	if _drawing and not holding:
		# Let go mid-backflip / sidehop: the shot fizzles (no firing out of a move).
		_release(charge >= s.min_charge_to_fire and not _player.motor.action_locked())
	_player.camera_rig.set_aim(sync_aiming, s)


func _release(fire: bool) -> void:
	if fire:
		_fire()
	_drawing = false
	charge = 0.0


func _set_drawn(on: bool) -> void:
	if on == sync_drawn:
		return
	if not on:
		melee.cancel()
	sync_drawn = on
	sync_aiming = false
	_swap_timer = holster_swap_delay
	var w := weapon()
	if _model and w:
		_model.play_action(w.draw_anim)
	changed.emit()


# ---------------------------------------------------------------- aiming helpers
## Where the crosshair points (camera ray), limited to max_dist from `origin`.
func _crosshair_point(origin: Vector3, max_dist: float) -> Vector3:
	var cam: Camera3D = _player.camera_rig.camera
	var space := _player.get_world_3d().direct_space_state
	var cam_from := cam.global_position
	var cam_dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(cam_from, cam_from + cam_dir * 500.0, 3)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	var p: Vector3 = hit.position if not hit.is_empty() else cam_from + cam_dir * 500.0
	if origin.distance_to(p) > max_dist:
		p = origin + (p - origin).normalized() * max_dist
	return p


func _hand_origin() -> Vector3:
	if _weapon_vis and sync_drawn:
		return _weapon_vis.global_position + Vector3.UP * 0.05
	return _player.global_position + Vector3.UP * 1.4


func _projectiles_root() -> Node:
	var scene := get_tree().current_scene
	var parent := scene.get_node_or_null("Projectiles")
	if parent == null:
		parent = Node3D.new()
		parent.name = "Projectiles"
		scene.add_child(parent)
	return parent


# ---------------------------------------------------------------- nocked arrow
## Shows the arrow on the string while aiming. Owner: if its tip is inside a fire
## (brazier / torch flame) it catches fire; the next shot is a fire arrow.
## Remote peers just draw it (and its flames) from the synced state.
func _update_nock(delta: float) -> void:
	var show := weapon_type() == "shoot" and sync_drawn and sync_aiming and _swap_timer < 0.0 \
		and (not is_local() or ammo_count() > 0)
	if is_local() and sync_arrow_element != "":
		_lit_timer -= delta
		if _lit_timer <= 0.0 or weapon_type() != "shoot" or not sync_drawn:
			_extinguish_nock()
	if not show:
		if _nock_vis:
			_nock_vis.queue_free()
			_nock_vis = null
			_nock_flames = null
		return
	if _nock_vis == null:
		_nock_vis = Node3D.new()
		_nock_vis.name = "NockedArrow"
		_nock_vis.top_level = true
		_nock_vis.add_child(AssetRegistry.instantiate(_ammo_model_id()))
		add_child(_nock_vis)
	var hand := _hand_origin()
	var dir: Vector3
	if is_local() and _player.camera_rig:
		dir = (_crosshair_point(hand, 1000.0) - hand).normalized()
	else:
		dir = -_player.model_root.global_basis.z
	var tip := hand + dir * nock_forward
	_nock_vis.global_position = tip
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	_nock_vis.look_at(tip + dir, up)
	if is_local() and sync_arrow_element == "" and (WorldRules.fire_zone_at(_player.get_world_3d(), tip) \
			or WorldRules.fire_zone_on_segment(_player.get_world_3d(), hand + dir * 0.3, tip + dir * 0.15)):
		sync_arrow_element = "fire"
		_lit_timer = lit_arrow_burn_time
		print("[bow] nocked arrow lit")
	var lit := sync_arrow_element == "fire"
	if lit and _nock_flames == null:
		_nock_flames = FX.flames(0.35, true)
		_nock_vis.add_child(_nock_flames)
		_nock_flames.position = Vector3(0, 0, 0.05)
		Audio.play_at("fire.ignite", tip, -6.0, 1.3)
	elif not lit and _nock_flames:
		_nock_flames.queue_free()
		_nock_flames = null


func _extinguish_nock() -> void:
	if sync_arrow_element == "":
		return
	sync_arrow_element = ""
	_lit_timer = 0.0
	if _nock_vis:
		FX.smoke_puff(_nock_vis.global_position, get_tree().current_scene, 0.4)


# ---------------------------------------------------------------- bow
func _fire() -> void:
	var w := weapon()
	var s := stats()
	if w == null or ammo_count() <= 0:
		return
	var origin := _hand_origin()
	var dir := (_crosshair_point(origin, 1000.0) - origin).normalized()
	dir = _apply_spread(dir, float(s.spread_deg(charge)))
	var vel: Vector3 = dir * s.launch_speed(charge)
	var dmg: float = s.damage(charge)
	consume(w.ammo_item_id, 1)
	_cooldown = s.fire_cooldown
	var element := sync_arrow_element
	sync_arrow_element = ""
	_lit_timer = 0.0
	_spawn_arrow(origin, vel, dmg, false, element)
	Audio.play_at("bow.fire", origin)
	if _model:
		_model.play_shoot()
	rpc_fire.rpc(origin, vel, element)
	print("[bow] fired charge %.2f speed %.1f m/s dmg %.0f ammo left %d" % [charge, vel.length(), dmg, ammo_count()])
	changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_fire(origin: Vector3, vel: Vector3, element: String) -> void:
	_spawn_arrow(origin, vel, 0.0, true, element)
	Audio.play_at("bow.fire", origin)
	if _model:
		_model.play_shoot()


func _spawn_arrow(origin: Vector3, vel: Vector3, dmg: float, cosmetic: bool, element := "") -> void:
	var arrow := ArrowScene.instantiate()
	arrow.model_id = _ammo_model_id()
	var ammo_it: Resource = ItemDB.get_item(weapon().ammo_item_id) if weapon() else null
	if ammo_it and ammo_it.material == "stone":
		arrow.hit_action = "blunt"
	arrow.cosmetic = cosmetic
	arrow.element = element
	_projectiles_root().add_child(arrow)
	arrow.launch(origin, vel, stats(), dmg, _player.get_rid())


## What the current weapon shoots (arrow, slingstone...): the ammo item's model.
func _ammo_model_id() -> String:
	var w := weapon()
	var a: Resource = ItemDB.get_item(w.ammo_item_id) if w and w.ammo_item_id != "" else null
	return a.model_id if a and a.model_id != "" else "weapon.arrow.basic"


func _apply_spread(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return dir
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var a := randf() * TAU
	var r := deg_to_rad(deg) * sqrt(randf())
	return (dir + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


# ---------------------------------------------------------------- boomerang
## Hold LMB: aim + sweep the crosshair over targets to pick them (red triangles).
## Release: throw. A quick tap while focus-locked throws straight at the lock target.
func _update_boomerang() -> void:
	var s := stats()
	var holding := Input.is_action_pressed("attack")
	var ready_to_throw: bool = sync_drawn and not sync_thrown and _cooldown <= 0.0 and _swap_timer < 0.0 \
		and not _player.motor.action_locked()   # no throwing out of a roll / backflip / sidehop
	if holding and ready_to_throw and (_boom_aiming or Input.is_action_just_pressed("attack")):
		if not _boom_aiming:
			_boom_aiming = true
			var homing: bool = "homes_on_lock" in s and s.homes_on_lock
			_boom_aim.begin(_player.focus.target if _player.focus.active and homing else null)
		sync_aiming = true
		_boom_aim.update(s.lock_on_range, s.max_targets)
		_player.camera_rig.set_aim(true, s)
		return
	if _boom_aiming and not holding:
		var picked: Array[Node3D] = _boom_aim.end()
		_boom_aiming = false
		sync_aiming = false
		_player.camera_rig.set_aim(false, s)
		if ready_to_throw:
			_throw(picked)
		return
	if not holding:
		_cancel_boomerang_aim()
	sync_aiming = false
	_player.camera_rig.set_aim(false, s)


func _cancel_boomerang_aim() -> void:
	if _boom_aiming:
		_boom_aim.end()
		_boom_aiming = false


func boomerang_selection() -> Array[Node3D]:
	return _boom_aim.selected if _boom_aiming else ([] as Array[Node3D])


func _throw(picked: Array[Node3D] = []) -> void:
	var w := weapon()
	var s := stats()
	var origin := _hand_origin()
	var aim: Vector3
	if not picked.is_empty():
		aim = picked[0].get_lock_point()
	else:
		aim = _crosshair_point(origin, s.speed * s.out_time)
	sync_thrown = true
	_cooldown = s.cooldown
	_applied = ""
	_spawn_boomerang(origin, aim, picked, false)
	if _model:
		_model.play_action(w.shoot_anim)
	var paths := PackedStringArray()
	for t in picked:
		paths.append(str(get_tree().current_scene.get_path_to(t)))
	rpc_throw.rpc(origin, aim, paths)
	print("[boomerang] thrown %s" % ("-> %s" % ", ".join(picked.map(func(t: Node) -> String: return t.name)) \
		if not picked.is_empty() else "free aim (%.1fm)" % origin.distance_to(aim)))


@rpc("authority", "call_remote", "reliable")
func rpc_throw(origin: Vector3, aim: Vector3, target_paths: PackedStringArray) -> void:
	var picked: Array[Node3D] = []
	for p in target_paths:
		var t := get_tree().current_scene.get_node_or_null(NodePath(p)) as Node3D
		if t:
			picked.append(t)
	_spawn_boomerang(origin, aim, picked, true)
	var w := weapon()
	if _model and w:
		_model.play_action(w.shoot_anim)


func _spawn_boomerang(origin: Vector3, aim: Vector3, picked: Array[Node3D], cosmetic: bool) -> void:
	var b := BoomerangScene.instantiate()
	b.cosmetic = cosmetic
	_projectiles_root().add_child(b)
	b.launch(origin, aim, picked, stats(), _player)
	if not cosmetic:
		_boomerang = b
		b.caught.connect(_on_boomerang_caught)


func _on_boomerang_caught() -> void:
	sync_thrown = false
	_applied = ""
	_boomerang = null
	changed.emit()


# ---------------------------------------------------------------- pickups
func _update_nearest_pickup() -> void:
	nearest_pickup = null
	var best := pickup_radius
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.taken:
			continue
		var d: float = (p as Node3D).global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			nearest_pickup = p


# ---------------------------------------------------------------- visuals
func _find_model() -> void:
	var root: Node3D = _player.get("model_root")
	if root and root.get_child_count() > 0 and root.get_child(0).has_method("get_attach_point"):
		_model = root.get_child(0)


func _refresh_visuals() -> void:
	if _model == null:
		return
	var shield_in_hand := sync_blocking or (sync_drawn and weapon_type() == "slash" and not two_handed_drawn())
	var state := "%s|%s|%s|%s|%s" % [sync_weapon_id, sync_drawn, sync_thrown, sync_shield_id, shield_in_hand]
	if state == _applied or (_swap_timer >= 0.0 and not sync_blocking):
		return
	_applied = state
	for v in [_weapon_vis, _worn_vis, _shield_vis]:
		if is_instance_valid(v):
			v.queue_free()
	_weapon_vis = null
	_worn_vis = null
	_shield_vis = null
	var sh := shield_item()
	if sh:
		if shield_in_hand:
			_shield_vis = _attach(sh.model_id, sh.hand_slot, sh.hand_position, sh.hand_rotation_deg)
		else:
			_shield_vis = _attach(sh.model_id, "chest", sh.back_position, sh.back_rotation_deg)
	var w := weapon()
	if w == null:
		return
	if sync_thrown:
		pass  # it's flying: nothing in hand or on the back
	elif sync_drawn:
		_weapon_vis = _attach(w.model_id, w.hand_slot, w.hand_position, w.hand_rotation_deg)
	else:
		_weapon_vis = _attach(w.model_id, "chest", w.back_position, w.back_rotation_deg)
	if w.worn_model_id != "":
		_worn_vis = _attach(w.worn_model_id, "chest", w.worn_position, w.worn_rotation_deg)
	if _player.camera_rig and _player.camera_rig.first_person:
		_player.call("_on_view_changed", true)  # keep FP shadow-only look


func _attach(model_id: String, slot: String, pos: Vector3, rot_deg: Vector3) -> Node3D:
	var point: Node3D = _model.get_attach_point(slot)
	if point == null:
		return null
	var vis := AssetRegistry.instantiate(model_id)
	vis.position = pos
	vis.rotation_degrees = rot_deg
	point.add_child(vis)
	return vis
