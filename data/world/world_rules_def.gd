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
	"emberfog": Color(1.0, 0.45, 0.25), "muddlehaze": Color(0.7, 0.5, 0.95), "rimemist": Color(0.6, 0.9, 1.0),
	"stormdrop": Color(0.75, 0.85, 1.0), "chainspark": Color(1.0, 0.95, 0.5), "steamburst": Color(0.92, 0.92, 0.95),
	"sunburst": Color(1.0, 0.95, 0.7), "mendingdew": Color(0.45, 1.0, 0.6),
}
## What each element does - shown in item tooltips and the arrow wheel. Keep it short.
@export var element_info: Dictionary[String, String] = {
	"fire": "Sets targets Burning (damage over time). Lights wood, melts ice.",
	"frost": "Chills (slower). A Wet target gets Frozen in place. Puts out Burning.",
	"shock": "Stuns briefly. x1.75 damage on Wet targets (Electrocuted!).",
	"water": "Splash makes everyone close Wet and puts out fires. Sets up shock.",
	"smoke": "Thick smoke cloud (~6 m, 7 s). Nobody can lock on through it.",
	"flash": "Bright burst: dazzles everyone looking toward it (11 m).",
	"muddle": "Spore puff: anyone close is Confused (controls reversed, 3 s).",
	"light": "Leaves a light for 14 s and Reveals nearby players through walls.",
	"blast": "A full bomb explosion where it lands.",
	"emberfog": "Burning smoke cloud: anyone inside catches fire. Blocks lock-on.",
	"muddlehaze": "Lingering violet cloud (8 s): keeps anyone inside Confused.",
	"rimemist": "Wet + Chilled to everyone in 3.5 m (next frost = Frozen). Freezes water into a platform.",
	"stormdrop": "Soaks the area, then lightning strikes 0.8 s later (Electrocuted if still Wet).",
	"chainspark": "Lightning jumps between the 3 nearest players (12 shock each).",
	"steamburst": "No damage: shoves everyone away, puts out fires, clears Burning / Chilled / Frozen.",
	"sunburst": "Huge flash; anyone dazzled is also Revealed through walls.",
	"mendingdew": "Healing puddle for 6 s: 4 hp per second to anyone standing in it.",
}
