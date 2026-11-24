extends Resource
## Grapple tool tuning (Grappleclaw = short, Skytether = long). Works like OoT's
## hookshot / longshot: the claw flies straight out, latches onto anything hookable
## (group "hook_targets": trees, training dummies, the grapple pillar) and reels you in
## to it; anything else knocks it back. Long version = same tool, double the reach.

@export_group("Chain")
@export var max_range := 14.0             ## claw flies this far before reeling back
@export var fire_speed := 40.0            ## m/s outward
@export var retract_speed := 55.0         ## m/s back to the launcher after a miss
@export var tip_radius := 0.15            ## sphere swept along the claw's path
@export var tip_model_id := "weapon.grapple.grappleclaw_tip"
@export var chain_link_spacing := 0.11    ## metres between chain links (visual)
@export var chain_color := Color(0.42, 0.44, 0.5)

@export_group("Pull")
@export var pull_speed := 20.0            ## m/s while being reeled in
@export var stop_distance := 0.75         ## stop this far out from the latch point (along its surface normal)
@export var hand_height := 1.3            ## latch point ends up at this height on your body
@export var arrive_hop := 4.5             ## upward kick when you reach it (lets you clear a ledge / trunk)
@export var arrive_push := 1.5            ## m/s pushed back off the surface on arrival
@export var max_pull_time := 2.5          ## safety: let go after this
@export var cooldown := 0.25

@export_group("Targeting")
@export var lock_on_range := 14.0         ## focus (RMB) lock range with this tool drawn
@export var homes_on_lock := true         ## tap LMB while locked: fire straight at the lock point

@export_group("Aim camera (hold LMB)")
@export var aim_fov := 50.0
@export var aim_distance := 2.4
@export var aim_shoulder := 0.85
@export var aim_move_speed_mult := 0.55
@export var dot_color_hit := Color(1.0, 0.2, 0.15)     ## aim dot: something hookable in range
@export var dot_color_miss := Color(1.0, 1.0, 1.0, 0.5)

@export_group("Hit")
@export var damage := 2.0                 ## the claw's bonk on dummies (utility tool, not a weapon)
