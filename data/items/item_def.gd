extends Resource
## One item type (weapon, ammo, ...). Create .tres files from this in data/items/
## and register them in data/registry/items.tres. Everything here is tweakable in
## the Inspector; gameplay code reads it, never hardcodes it.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""    ## tooltip text (effects / how to use); recipes + element info are added automatically
@export_enum("weapon", "ammo", "shield", "material") var kind := "weapon"   ## shield: off hand. material: stacks in the bag (reagents, food, ore, bombs...)
@export var model_id := ""                 ## AssetRegistry id used in hands / on back
@export var pickup_model_id := ""          ## AssetRegistry id shown on the ground (blank = model_id)
@export var pickup_scale := 1.0             ## ground model size (small gatherables read better bigger)

@export_group("Hotbar icon")
@export var icon: Texture2D                ## optional hand-made icon; blank = rendered from the model
@export var icon_model_id := ""            ## model to photograph (blank = pickup model, then model_id)
@export var icon_rotation_deg := Vector3(0, 0, 0)  ## pose for the photo (camera looks down -Z)
@export var icon_roll_deg := 0.0           ## then tilt in the picture (-45 = long items diagonal)

@export_group("Weapon")
@export var stats: Resource                ## e.g. BowStats (data/items/bow_stats.gd)
@export var ammo_item_id := ""             ## which ammo item this weapon uses
@export var starting_ammo := 0             ## ammo granted when first picked up
@export var aim_anim := &"1H_Ranged_Aiming"
@export var shoot_anim := &"1H_Ranged_Shoot"
@export var draw_anim := &"Use_Item"       ## upper-body anim when drawing/holstering

@export_group("Hand (drawn)")
@export_enum("handslot_r", "handslot_l") var hand_slot := "handslot_r"
@export var hand_position := Vector3.ZERO
@export var hand_rotation_deg := Vector3.ZERO

@export_group("Back (holstered)")
@export var back_position := Vector3(0.0, 0.25, -0.45)
@export var back_rotation_deg := Vector3.ZERO

@export_group("Extra worn model (e.g. quiver)")
@export var worn_model_id := ""
@export var worn_position := Vector3.ZERO
@export var worn_rotation_deg := Vector3.ZERO

@export_group("Ammo")
@export var amount := 0                    ## how much a pickup of this ammo gives
@export var max_carry := 30
@export var ammo_family := ""              ## special ammo: the base ammo it replaces ("arrows" for fire arrows...)
@export var speed_mult := 1.0              ## special ammo flight: launch speed x
@export var gravity_mult := 1.0            ## special ammo flight: gravity x (bomb arrows lob)
@export var damage_mult := 1.0
@export var aim_lift_deg := 0.0            ## shot leaves this many degrees above the crosshair (lobs)
@export var explosive := false             ## blows up where it lands (bomb arrows)
@export var fuse_time := 0.0               ## > 0: lit when you start drawing; held too long = boom in hand

@export_group("Tags")
@export var element := ""
@export var heal := 0.0                     ## food: right-click > Eat restores this much health
@export var category := ""                 ## reagent / food / ore / throwable / trap / tool (crafting + loot tables)
@export var material := "wood"
@export var action_tag := "shoot"
