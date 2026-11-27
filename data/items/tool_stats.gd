extends Resource
## Tuning for the world tools (one resource type; each tool uses its own group).
##   Galeleaf Fan   (action_tag "fan")   : LMB = gust (Wind Waker Deku Leaf swing), hold Jump in the air = glide
##   Sandspire Staff (action_tag "staff") : hold LMB = aim, release = raise a sand pillar there
##   Rimecaller Rod (action_tag "rod")   : hold LMB = aim, release = ice platform on water / frost blast on land
##   Snapjaw Trap   (action_tag "trap")  : LMB = set a trap at your feet (it is its own ammo)

@export_group("Aim")
@export var max_range := 16.0
@export var cooldown := 0.6
@export var lock_on_range := 14.0
@export var aim_fov := 55.0
@export var aim_distance := 3.0
@export var aim_shoulder := 0.9
@export var aim_move_speed_mult := 0.7

@export_group("Fan: gust + glide")
@export var gust_range := 10.0
@export var gust_angle_deg := 45.0
@export var gust_push := 11.0               ## m/s shove on players / bombs
@export var gust_recoil := 3.0             ## m/s the swing pushes YOU back
@export var glide_fall_speed := 1.6         ## Deku Leaf: slow fall
@export var glide_speed := 6.0
@export var glide_time := 6.0               ## seconds of glide per landing (refills on the ground)

@export_group("Staff: sand pillar")
@export var pillar_height := 4.0
@export var pillar_size := 1.8
@export var pillar_rise_time := 0.45
@export var pillar_life := 14.0
@export var max_pillars := 3

@export_group("Rod: ice")
@export var ice_size := 3.2
@export var ice_life := 22.0
@export var ice_melt_near_fire := 3.0       ## seconds left once a flame touches it
@export var max_ice := 6
@export var frost_range := 6.0
@export var frost_damage := 10.0
@export var frost_slow := 2.5               ## seconds a frost blast slows players

@export_group("Trap")
@export var trap_arm_time := 1.0
@export var trap_damage := 25.0
@export var trap_root_time := 1.6
@export var trap_radius := 0.65
