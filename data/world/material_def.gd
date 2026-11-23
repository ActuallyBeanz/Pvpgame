extends Resource
## One world material (wood, ice, stone...): how much punishment it takes and how
## it behaves with heat. Listed in res://data/registry/world_rules.tres.

@export var id := ""
@export var max_hp := 60.0                     ## <= 0 = indestructible

@export_group("Heat & fire")
@export var flammable := false
@export var ignite_heat := 10.0                ## heat needed to catch fire (a lit arrow gives ~30)
@export var cool_per_sec := 2.0                ## heat lost per second when not burning
@export var burn_dps := 6.0                    ## damage it takes per second while burning
@export var spread_radius := 3.0               ## burning: heats Reactives within this range
@export var spread_heat_per_sec := 5.0         ## heat given to each neighbour per second
@export var melts_from_heat := false
@export var melt_per_heat := 1.0               ## hp lost per point of heat (ice)

@export_group("Feedback")
@export_enum("splinter", "shatter", "crumble") var break_style := "splinter"
@export var debris_color := Color(0.55, 0.36, 0.2)
@export var hit_sound := "arrow.hit"
@export var break_sound := ""
