extends Resource
## All statuses + how elements give them + element-on-status reactions.
## Edit res://data/status/status_rules.tres to add / tune - no code changes.

@export var statuses: Array[Resource] = []             ## StatusDef
@export var reactions: Array[Resource] = []            ## StatusReaction
## element -> status it gives on hit ("water" -> "wet"). "" / missing = none.
@export var element_status: Dictionary[String, String] = {}
## element -> seconds (overrides the status's default for that element)
@export var element_duration: Dictionary[String, float] = {}
@export var wet_from_water := 6.0          ## seconds of Wet left after you leave water (refreshed while in it)

var _by_id: Dictionary = {}


func get_status(id: String) -> Resource:
	if _by_id.is_empty():
		for s in statuses:
			if s:
				_by_id[s.id] = s
	return _by_id.get(id)
