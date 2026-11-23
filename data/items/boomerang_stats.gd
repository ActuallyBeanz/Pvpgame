extends Resource
## Boomerang tuning (Gyrewing). Defaults follow OoT's boomerang (En_Boom in the
## zeldaret/oot decomp): 12 u/frame ≈ 14 m/s, flies out for 20 frames (1 s) then
## homes back to you, passes through walls on the way back, caught within ~2.3 m,
## bounces back early if it hits something.

@export_group("Flight")
@export var speed := 14.0                 ## m/s, out and back
@export var out_time := 1.0               ## seconds before it turns around (range ≈ speed * out_time)
@export var max_flight_time := 4.0        ## safety: force-return/despawn
@export var catch_radius := 2.3
@export var hit_radius := 0.25            ## sphere swept along the path
@export var spin_speed := 30.0            ## rad/s (visual)
@export var cooldown := 0.2               ## after catching before you can throw again

@export_group("Homing (OoT: steer harder the closer it gets)")
## Fraction of the remaining angle closed per OoT frame = clamp((near - dist) / near, min, 1).
@export var steer_near_distance := 11.7   ## 200 units
@export var steer_min := 0.12

@export_group("Targeting")
@export var lock_on_range := 20.0         ## focus (RMB) locks on to targets within this
@export var homes_on_lock := true         ## fly to the locked target instead of the crosshair

@export_group("Hit")
@export var damage := 6.0
@export var stun_time := 1.5              ## for future enemies/players
@export var aim_move_speed_mult := 1.0
