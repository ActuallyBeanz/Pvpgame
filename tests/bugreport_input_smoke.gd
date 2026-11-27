extends Node
## Types a report the way a player would (backtick, letters, backspace, Enter) and checks it saved;
## then opens one and cancels with Esc.
func _key(code: Key, uni := 0) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni if pressed else 0
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame


func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	await get_tree().process_frame
	var before := DirAccess.get_files_at(ProjectSettings.globalize_path("res://_reports")).size() if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://_reports")) else 0
	await _key(KEY_QUOTELEFT, 96)
	print("[t] open after backtick: ", BugReporter._open, " input enabled: ", GameConfig.gameplay_input_enabled)
	for ch in "wallx":
		await _key(OS.find_keycode_from_string(ch.to_upper()), ch.unicode_at(0))
	await _key(KEY_BACKSPACE)
	print("[t] note: '", BugReporter._note, "'")
	await _key(KEY_ENTER)
	for i in 10:
		await get_tree().process_frame
	var after := DirAccess.get_files_at(ProjectSettings.globalize_path("res://_reports")).size()
	print("[t] closed: ", not BugReporter._open, " input enabled: ", GameConfig.gameplay_input_enabled, " new files: ", after - before)
	await _key(KEY_QUOTELEFT, 96)
	print("[t] reopen: ", BugReporter._open)
	await _key(KEY_ESCAPE)
	print("[t] Esc closed: ", not BugReporter._open)
	get_tree().quit()
