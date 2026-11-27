extends Resource
## Blastgourd Bomb tuning (OoT bombs): LMB pulls out a lit bomb and holds it overhead, LMB again
## throws it; Q / roll sets it down. The fuse keeps burning in your hands.

@export var fuse_time := 4.0                ## OoT bombs: ~4 s, flashing faster near the end
@export var throw_speed := 12.0
@export var throw_up := 0.0                 ## extra straight-up kick (0 = pure arc from the aim)
@export var throw_lift_deg := 28.0          ## the throw leaves this much above where the camera looks (lob)
@export var max_throw_pitch_deg := 75.0
@export var momentum_carry := 1.0           ## share of your own velocity the bomb keeps (run = further, jump = higher)
@export var arc_preview := true
@export var drop_speed := 1.0
@export var gravity := 14.0
@export var bounce := 0.35
@export var friction := 3.0                 ## m/s² rolling slowdown on the ground
@export var blast_radius := 3.6
@export var blast_damage := 40.0            ## at the centre, falling off to 40 % at the edge
@export var chain_radius := 3.0             ## other bombs this close go off too
@export var lock_on_range := 12.0
