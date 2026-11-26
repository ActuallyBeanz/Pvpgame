extends Resource
## Blastgourd Bomb tuning (OoT bombs): LMB pulls out a lit bomb and holds it overhead, LMB again
## throws it; Q / roll sets it down. The fuse keeps burning in your hands.

@export var fuse_time := 4.0                ## OoT bombs: ~4 s, flashing faster near the end
@export var throw_speed := 9.0
@export var throw_up := 5.0
@export var drop_speed := 1.0
@export var gravity := 18.0
@export var bounce := 0.35
@export var friction := 3.0                 ## m/s² rolling slowdown on the ground
@export var blast_radius := 3.6
@export var blast_damage := 40.0            ## at the centre, falling off to 40 % at the edge
@export var chain_radius := 3.0             ## other bombs this close go off too
@export var lock_on_range := 12.0
