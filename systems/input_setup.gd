extends RefCounted
## Registers default input actions at startup (only if they don't already exist,
## so bindings you set in Project Settings > Input Map always win).

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"pause": [KEY_ESCAPE],
	"inventory": [KEY_TAB],
	"toggle_camera": [KEY_V],
	"toggle_weapon": [KEY_Q],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"weapon_4": [KEY_4],
	"weapon_5": [KEY_5],
	"weapon_6": [KEY_6],
	"weapon_7": [KEY_7],
	"weapon_8": [KEY_8],
	"weapon_9": [KEY_9],
	"roll": [KEY_CTRL, KEY_C],
	"interact": [KEY_E],
	"block": [KEY_F],
	"ammo_wheel": [KEY_R],              # hold: arrow-type wheel
}
const MOUSE := {
	"attack": MOUSE_BUTTON_LEFT,
	"focus": MOUSE_BUTTON_RIGHT,   # hold: OoT-style Z-target / lock-on
}
const PAD_BUTTONS := {
	"jump": JOY_BUTTON_A,
	"sprint": JOY_BUTTON_LEFT_STICK,
	"pause": JOY_BUTTON_START,
	"inventory": JOY_BUTTON_BACK,
	"toggle_camera": JOY_BUTTON_RIGHT_STICK,
	"toggle_weapon": JOY_BUTTON_Y,
	"roll": JOY_BUTTON_B,
	"cycle_weapon": JOY_BUTTON_DPAD_RIGHT,
	"interact": JOY_BUTTON_X,
	"block": JOY_BUTTON_RIGHT_SHOULDER,
	"ammo_wheel": JOY_BUTTON_DPAD_UP,
}
## action -> [axis, direction]
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"focus": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}


static func apply() -> void:
	var actions: Array = KEYS.keys() + MOUSE.keys() + PAD_BUTTONS.keys() + PAD_AXES.keys()
	for action: String in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key: int in KEYS.get(action, []):
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key  # layout-independent (WASD stays WASD on AZERTY)
			InputMap.action_add_event(action, ev)
		if MOUSE.has(action):
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE[action]
			InputMap.action_add_event(action, mb)
		if PAD_BUTTONS.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = PAD_BUTTONS[action]
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, jm)
