extends Resource
## All materials + reaction rules. Edit res://data/registry/world_rules.tres in the
## Inspector to add a material or change how fire / frost / blunt hits behave.

@export var materials: Array[Resource] = []      ## MaterialDef
@export var reactions: Array[Resource] = []      ## ReactionDef
@export var fire_hit_heat := 30.0                ## heat a fire-element hit adds
@export var element_bonus_damage := 4.0          ## extra damage on any elemental hit (fire arrow, lit boomerang)
@export var arrows_light_in_flight := true       ## OoT: an arrow flying through a lit torch becomes a fire arrow
@export var element_colors: Dictionary[String, Color] = {
	"fire": Color(1.0, 0.55, 0.15), "frost": Color(0.55, 0.85, 1.0), "shock": Color(1.0, 0.95, 0.4),
	"blast": Color(1.0, 0.38, 0.12),
	"water": Color(0.35, 0.6, 1.0), "smoke": Color(0.6, 0.6, 0.64), "flash": Color(1.0, 1.0, 0.85),
	"muddle": Color(0.75, 0.45, 1.0), "light": Color(1.0, 0.92, 0.55),
}
