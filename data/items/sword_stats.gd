extends Resource
## Sword tuning (Dawnsteel Blade). OoT-flavoured: tap LMB for a 3-hit combo, thrust
## when focus-locked (OoT Z-target stab), hold LMB after a swing to charge a spin attack.
## Animations are KayKit clips, time-scaled to the durations below.

@export_group("Combo (tap LMB)")
@export var combo_anims: Array[StringName] = [&"1H_Melee_Attack_Slice_Horizontal", &"1H_Melee_Attack_Slice_Diagonal", &"1H_Melee_Attack_Chop"]
@export var combo_damage: PackedFloat32Array = [12.0, 12.0, 20.0]
@export var combo_duration: PackedFloat32Array = [0.42, 0.42, 0.55]  ## seconds per swing
@export var hit_window := Vector2(0.22, 0.62)   ## part of a swing (0-1) that can hit
@export var combo_window := 0.35                ## press again within this after a swing to chain
@export var reach := 2.0                        ## metres from your chest
@export var arc_deg := 150.0                    ## swing arc in front of you
@export var swing_move_mult := 0.35             ## movement speed while swinging

@export_group("Thrust (tap LMB while focus-locked)")
@export var stab_anim := &"1H_Melee_Attack_Stab"
@export var stab_damage := 16.0
@export var stab_duration := 0.5
@export var stab_reach := 2.5
@export var stab_arc_deg := 50.0

@export_group("Spin attack (hold LMB)")
@export var spin_charge_time := 0.8             ## hold this long after a swing to charge
@export var charge_pose := &"2H_Melee_Idle"
@export var charge_move_mult := 0.45
@export var spin_anim := &"2H_Melee_Attack_Spin"
@export var spin_damage := 28.0
@export var spin_radius := 2.9
@export var spin_duration := 0.7

@export_group("Hit")
@export var slash_action := "slash"             ## WorldRules tag (wood takes 1.2x from slash)
@export var stab_action := "pierce"
@export var lock_on_range := 15.0
@export var trail_color := Color(0.55, 0.95, 1.0, 0.85)
