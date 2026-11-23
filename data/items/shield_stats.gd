extends Resource
## Shield tuning (Gildcrest Shield). Raised while you hold focus (RMB) with the sword
## (or nothing) in hand, or with F (pad: RB) any time. Blocks arrows, boomerangs and
## sword hits from the front. Focus + LMB still swings / thrusts (the shield drops for
## the swing and comes back up); F + LMB = shield bash.

@export var block_anim := &"Blocking"
@export var block_hit_anim := &"Block_Hit"
@export var block_arc_deg := 140.0             ## frontal cone that is covered
@export var block_move_mult := 0.45            ## holding F
@export var raise_on_focus := true             ## RMB focus raises it (sword or empty hands)
@export var focus_guard_move_mult := 0.85      ## strafing behind the shield while focused
@export var raise_time := 0.08                 ## blocking starts this long after pressing

@export_group("Bash (LMB while blocking)")
@export var bash_anim := &"Block_Attack"
@export var bash_damage := 5.0
@export var bash_reach := 1.7
@export var bash_arc_deg := 90.0
@export var bash_duration := 0.45
@export var bash_cooldown := 0.5
