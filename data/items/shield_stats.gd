extends Resource
## Shield tuning (Gildcrest Shield). Hold F (pad: RB) to raise it, OoT-style:
## blocks arrows, boomerangs and sword hits from the front. LMB while blocking = bash.

@export var block_anim := &"Blocking"
@export var block_hit_anim := &"Block_Hit"
@export var block_arc_deg := 140.0             ## frontal cone that is covered
@export var block_move_mult := 0.45
@export var raise_time := 0.08                 ## blocking starts this long after pressing

@export_group("Bash (LMB while blocking)")
@export var bash_anim := &"Block_Attack"
@export var bash_damage := 5.0
@export var bash_reach := 1.7
@export var bash_arc_deg := 90.0
@export var bash_duration := 0.45
@export var bash_cooldown := 0.5
