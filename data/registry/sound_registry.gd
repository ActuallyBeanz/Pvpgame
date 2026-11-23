extends Resource
## Sound registry: sound_id -> SoundDef (data/audio/sound_def.gd).
## Edit res://data/registry/sounds.tres. Ids: <category>.<name>[.<variant>],
## e.g. player.footstep.grass, bow.fire, ui.select. No JSON.

@export var sounds: Dictionary[String, Resource] = {}
