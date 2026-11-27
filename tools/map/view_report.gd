extends Node
## Re-renders every bug report in _reports/ that hasn't been viewed yet: the reporter's own camera,
## then 4 views orbiting the spot (front/right/back/left, 45 deg down) and one straight down.
## Saves _reports/<id>_view_<n>.png. Run NOT headless:
##   Godot.exe --path . res://tools/map/view_report.tscn --resolution 1280x720
## Pass -- <id> to redo one report.

const DIR := "res://_reports"


func _ready() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]
	var dir := ProjectSettings.globalize_path(DIR)
	var todo := []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("report_") and f.ends_with(".md"):
			var id := f.trim_suffix(".md")
			if (only == "" and not FileAccess.file_exists(dir.path_join(id + "_view_0.png"))) or only == id:
				todo.append(id)
	for id: String in todo:
		await _view(dir, id)
	print("[view] done: %d reports" % todo.size())
	get_tree().quit()


func _vec(line: String, key: String) -> Vector3:
	var i := line.find(key + " (")
	if i < 0:
		return Vector3.INF
	var j := line.find(")", i)
	var parts := line.substr(i + key.length() + 2, j - i - key.length() - 2).split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _view(dir: String, id: String) -> void:
	var text := FileAccess.get_file_as_string(dir.path_join(id + ".md"))
	var scene_path := ""
	var cam_pos := Vector3.INF
	var cam_dir := Vector3.FORWARD
	var focus := Vector3.INF
	for line in text.split("\n"):
		if line.begins_with("- scene: "):
			scene_path = line.substr(9).strip_edges()
		elif line.begins_with("- camera:"):
			cam_pos = _vec(line, "pos")
			cam_dir = _vec(line, "looking")
		elif line.begins_with("- player:"):
			focus = _vec(line, "pos")
	if scene_path == "" or cam_pos == Vector3.INF:
		print("[view] %s: no scene/camera in report" % id)
		return
	if focus == Vector3.INF:
		focus = cam_pos + cam_dir * 8.0
	var world: Node = load(scene_path).instantiate()
	add_child(world)
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	var shots := [[cam_pos, cam_pos + cam_dir]]
	for k in 4:
		var a := TAU * k / 4.0
		shots.append([focus + Vector3(sin(a) * 9.0, 7.0, cos(a) * 9.0), focus + Vector3.UP])
	shots.append([focus + Vector3(0.01, 22.0, 0), focus])
	for n in shots.size():
		cam.global_position = shots[n][0]
		cam.look_at(shots[n][1], Vector3.UP)
		for i in 25:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(dir.path_join("%s_view_%d.png" % [id, n]))
	print("[view] %s: %d views" % [id, shots.size()])
	world.queue_free()
	cam.queue_free()
	await get_tree().process_frame
