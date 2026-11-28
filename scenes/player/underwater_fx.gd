extends CanvasLayer
## Local player only (added by CameraRig.activate): when the CAMERA dips under the water surface,
## tint / wobble the screen and muffle the world's sound (Audio.set_underwater).

const SHADER := preload("res://assets/shaders/underwater.gdshader")

var camera: Camera3D
var _rect: ColorRect


func _ready() -> void:
	layer = -1                                   # under the HUD
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_rect.material = m
	_rect.visible = false
	add_child(_rect)


func _process(_delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var p := camera.global_position
	var under := Water.level_at(p) > p.y + 0.03
	if under != _rect.visible:
		_rect.visible = under
		Audio.set_underwater(under)


func _exit_tree() -> void:
	if _rect and _rect.visible:
		Audio.set_underwater(false)
