extends OmniLight3D
## Gentle fire flicker. Energy wobbles around its starting value.

@export var amount := 0.35
@export var speed := 11.0

var _base := 1.0
var _t := 0.0


func _ready() -> void:
	_base = light_energy
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta * speed
	light_energy = _base * (1.0 + amount * (sin(_t) * 0.6 + sin(_t * 2.3 + 1.7) * 0.4))
