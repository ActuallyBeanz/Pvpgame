extends Resource
## Bow tuning. Edit data/items/bow_basic_stats.tres (or the bow item) in the Inspector.

@export_group("Draw")
@export var draw_time := 0.9                       ## seconds to full draw
@export var min_charge_to_fire := 0.15             ## releasing earlier cancels the shot
@export var charge_curve: Curve                    ## optional: shapes power over draw time
@export var fire_cooldown := 0.35
@export var aim_move_speed_mult := 0.55            ## movement speed while drawing/aiming

@export_group("Arrow Flight")
@export var min_speed := 20.0                      ## m/s at minimum draw
@export var max_speed := 60.0                      ## m/s at full draw
@export var gravity := 9.8                         ## m/s² — higher = more drop (9.8 = real)
@export var drag := 0.08                           ## velocity lost per second (fraction)
@export var lifetime := 6.0                        ## seconds before a flying arrow vanishes
@export var stick_time := 12.0                     ## seconds an arrow stays stuck in things
@export var spread_uncharged_deg := 3.0
@export var spread_charged_deg := 0.25

@export_group("Damage")
@export var min_damage := 8.0
@export var max_damage := 35.0
@export var headshot_mult := 1.5

@export_group("Camera")
@export var aim_fov := 52.0
@export var aim_distance := 2.7
@export var aim_shoulder := 1.05


func charge_to_power(charge: float) -> float:
	charge = clampf(charge, 0.0, 1.0)
	return charge_curve.sample(charge) if charge_curve else charge * (2.0 - charge)  # ease-out


func launch_speed(charge: float) -> float:
	return lerpf(min_speed, max_speed, charge_to_power(charge))


func damage(charge: float) -> float:
	return lerpf(min_damage, max_damage, charge_to_power(charge))


func spread_deg(charge: float) -> float:
	return lerpf(spread_uncharged_deg, spread_charged_deg, charge_to_power(charge))
