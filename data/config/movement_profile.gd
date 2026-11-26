extends Resource
## Movement feel. Defaults copy the *behaviour* of Ocarina of Time's player
## controller, studied from the zeldaret/oot decomp (z_player.c, z_player_lib.c).
## No code was copied; these are measured numbers turned into metric.
##
## OoT runs at 20 fps and measures distance in "units". To convert we use
##   1 unit = 7/120 m   ->  a full-stick run (6 units/frame) = 7 m/s,
## which matches the 7 m/s run speed the map was scaled for (map-design.md).
## Speeds:  u/frame * 20 * (7/120)        Accels:  u/frame^2 * 400 * (7/120)

@export_group("Ground")
## OoT run speed limit (6 u/f).
@export var run_speed := 7.0
## Not in OoT. Set to 1.0 for pure OoT feel.
@export var sprint_multiplier := 1.3
## Starting a sprint (sprint + direction) kicks off with a roll, then you sprint.
@export var sprint_starts_with_roll := true
## Speeding up: +2.0 u/f per frame (≈0.15 s to full run).
@export var accel := 46.7
## Slowing to a lower target / stick released: -1.5 u/f per frame.
@export var decel := 35.0
## Hard brake used when you flip the stick backwards (8 u/f per frame).
@export var brake_decel := 186.7
## Travel direction turn rate. OoT: 2000 binary-angle units/frame ≈ 220°/s; raised so
## the character follows camera swivels snappily.
@export var turn_rate_deg := 600.0
## Stick flipped more than this from travel direction: brake, then snap around.
@export var reverse_angle_deg := 135.0
## How fast the model catches up to the travel direction (visual only).
@export var facing_turn_rate_deg := 1080.0
## Uphill slowdown: speed -= this * clamp(sin(slope), 0, 0.6)^2.
@export var slope_slowdown := 9.33

@export_group("Analog stick")
## OoT ignores the inner third of the stick (20 of 60).
@export_range(0.0, 0.9) var stick_deadzone := 0.333
## OoT's "curved" response: slow tiptoe near the deadzone, ramps hard past half tilt.
@export var use_oot_stick_curve := true

@export_group("Air")
## Gravity: 1.0 u/f per frame.
@export var gravity := 23.3
## Terminal fall speed: 20 u/f.
@export var max_fall_speed := 23.3
## Air control. OoT has almost none (+0.05 u/f per frame ≈ 1.2 m/s²); here WASD pushes you
## around mid-air: a standing jump can drift up to air_drift_max_speed, a running jump keeps
## its speed and can be steered (≈ air_accel / speed rad/s). Sidehops/backflips stay committed.
@export var air_accel := 8.0
@export var air_drift_max_speed := 4.5
@export var air_decel := 2.33             ## momentum lost per second with no input

@export_group("Ledge auto-jump (OoT has no jump button)")
@export var auto_ledge_jump := true
## Only hop if the drop below is deeper than this (ignores steps/curbs).
@export var ledge_min_drop := 0.8
## Above 5.9 u/f: fixed hop 7.5 u/f. Below: 1.25 u/f + 0.2 * speed.
@export var ledge_full_hop_speed := 6.88
@export var ledge_full_hop_velocity := 8.75
@export var ledge_small_hop_base := 1.46
@export var ledge_small_hop_per_speed := 0.2

@export_group("Manual jump (battle royale addition)")
@export var allow_manual_jump := true
@export var jump_velocity := 8.75  ## same as a full ledge hop ≈1.6 m high
@export_range(0.0, 1.0) var jump_cut := 0.5  ## keep this much upward speed on early release
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Roll")
## Roll goes straight (no steering) at 1.5x your stick speed, never below 3 u/f.
@export var roll_speed_multiplier := 1.5
@export var roll_min_speed := 3.5
## 20 anim frames at 1.25x speed = 16 game frames.
@export var roll_duration := 0.8
## Steer the roll mid-way: toward the stick (camera-relative), or the camera if no stick.
@export var roll_follows_camera := true
@export var roll_steer_rate_deg := 360.0
## Dodge invulnerability window (starts on anim frame 8, lasts 10 frames).
@export var roll_iframe_start := 0.32
@export var roll_iframe_end := 0.82
## Rolling into a wall this fast knocks you back (OoT: speed >= 7 u/f, within 45°).
@export var bonk_min_speed := 8.17
@export var bonk_max_angle_deg := 45.0
@export var bonk_duration := 0.6
@export var bonk_decel := 46.7

@export_group("Focus / Z-target strafing")
## While focused you face the focus direction and side-step. OoT Z-target speeds:
## ~0.9x moving toward it, 0.4x sideways, 0.3x backing away.
@export var focus_forward_mult := 0.9
@export var focus_side_mult := 0.4
@export var focus_back_mult := 0.3
## Stick changes of more than this brake to a stop first, then snap (OoT: 90°).
@export var focus_reverse_angle_deg := 90.0
## Small direction changes ease in (OoT: 10% of the gap per frame ≈ 2.1/s; snappier here).
@export var focus_heading_lerp := 8.0
## How fast your body turns to face the focus direction / locked target (≈440°/s).
@export var focus_facing_rate_deg := 900.0

@export_group("Focus hops (jump + side/back while focused = OoT's A while Z-targeting)")
## Sidehop: 8.5 u/f sideways, 3.5 u/f up. Backflip: 6 u/f back, 5.8 u/f up.
@export var sidehop_speed := 9.92
@export var sidehop_up := 4.08
@export var backflip_speed := 7.0
@export var backflip_up := 6.77
@export var hop_land_lag := 0.1            ## brief skid when a hop lands

@export_group("Ledges (OoT thresholds, scaled to a 1.85 m body)")
## Push into a ledge to get up it. OoT classes (adult): <18u step, <41u hop up,
## <59u climb, <79.4u tall climb, probed up to 111u. 1 unit ≈ 0.033 m of body height.
@export var ledge_min_height := 0.25       ## below this, normal walking handles it
@export var step_max := 0.6                ## instant step-up, no push needed
@export var hop_up_max := 1.35
@export var climb_max := 1.95
@export var tall_climb_max := 2.62
@export var climb_reach := 3.66            ## highest ledge you can pull yourself onto
@export var climb_push_time := 0.3         ## OoT: 6 frames of pushing into the wall
@export var step_duration := 0.15
@export var hop_up_duration := 0.35
@export var climb_duration := 0.6
@export var tall_climb_duration := 1.0
@export var climb_wall_angle_deg := 50.0   ## how directly you must push into the wall

@export_group("Ledge hang")
## Falling (or jumping) into a wall grabs its ledge if the top is within this band above your feet.
@export var grab_min := 0.3
@export var grab_max := 2.3
@export var hang_offset := 1.5             ## feet this far below the ledge top (hands on the lip for KayKit proportions)
@export var hang_grab_delay := 0.25        ## can't pull up / drop instantly after grabbing
@export var pull_up_duration := 0.8
@export var drop_regrab_delay := 0.4
## Backing off an edge while focused grabs it (OoT back-walk ledge grab).
@export var walkoff_grab_min_drop := 1.5

@export_group("Swimming (OoT-style)")
## Deep water (surface more than swim_enter_depth above your feet) = swim. No weapons while swimming.
@export var swim_enter_depth := 1.25
@export var swim_exit_depth := 1.0          ## shallower than this: you're standing again
@export var float_depth := 1.3              ## feet this far under the surface while floating (head out)
@export var swim_speed := 3.2
@export var swim_dash_speed := 6.0          ## hold Shift (sprint) to dash through the water
@export var swim_accel := 6.0
@export var swim_turn_rate_deg := 220.0
@export var dive_speed := 3.5               ## hold Roll (Ctrl) to swim down, Jump (Space) to swim up
@export var swim_up_speed := 4.0
@export var jump_out_velocity := 9.0        ## Space at the surface: hop out of the water
@export var jump_out_grace := 0.6           ## seconds you can't re-enter swimming after hopping out
@export var dive_swim_speed := 2.6
@export var buoyancy := 3.0                 ## m/s rising back to the surface
@export var breath_max := 8.0               ## seconds of air while your head is underwater
@export var breath_regen := 3.0             ## per second at the surface / on land
@export var head_height := 1.65
@export var climb_out_height := 2.8         ## swim into a bank this low (above the water) to climb out
@export var climb_out_up := 6.5
@export var climb_out_push := 3.0
@export var shallow_slow_start := 0.35      ## water deeper than this slows walking...
@export var shallow_min_mult := 0.6         ## ...down to this at waist depth
