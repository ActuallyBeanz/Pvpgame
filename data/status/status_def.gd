extends Resource
## One status a player can have (Wet, Burning, Chilled...). Make a .tres per status and list it
## in res://data/status/status_rules.tres. Gameplay reads these fields - no code per status.

@export var id := ""
@export var display_name := ""
@export var color := Color.WHITE           ## HUD pill + effect colour
@export var duration := 5.0                ## default seconds (an element / source can override)

@export_group("While active")
@export var move_mult := 1.0               ## 0 = rooted (can't walk or jump)
@export var stuns := false                 ## can't act (attack / move input) while active
@export var invert_controls := false       ## confusion: movement input flipped
@export var dot_per_sec := 0.0             ## damage over time
@export var dot_kind := "fire"             ## damage kind for the DoT ("fire" = shield resist applies)
@export var reveals := false               ## glows through walls for every player
@export var screen_flash := false          ## owner: white-out overlay, fades with time left (uses strength)

@export_group("Rules")
@export var removes: PackedStringArray = []        ## getting this status clears these (Wet clears Burning)
@export var blocked_by: PackedStringArray = []     ## can't get this while you have one of these
@export var refresh := true                ## re-applying resets the timer (false = keeps the longer)

@export_group("Look")
@export_enum("none", "drip", "flames", "frost", "sparks", "swirl", "glow") var vfx := "none"
