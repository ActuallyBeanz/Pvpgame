extends Resource
## Model registry: model_id -> scene. Edit res://data/registry/models.tres in the
## Inspector (add a key, drag a .tscn/.glb onto the value). No JSON.
## Ids: <category>.<type>.<variant>, e.g. player.adventurer.knight

@export var models: Dictionary[String, PackedScene] = {}
