extends Resource
## All materials + reaction rules. Edit res://data/registry/world_rules.tres in the
## Inspector to add a material or change how fire / frost / blunt hits behave.

@export var materials: Array[Resource] = []      ## MaterialDef
@export var reactions: Array[Resource] = []      ## ReactionDef
@export var fire_hit_heat := 30.0                ## heat a fire-element hit adds
@export var element_colors: Dictionary[String, Color] = {
	"fire": Color(1.0, 0.55, 0.15), "frost": Color(0.55, 0.85, 1.0), "shock": Color(1.0, 0.95, 0.4),
}
