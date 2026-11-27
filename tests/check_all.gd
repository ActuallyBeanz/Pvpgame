extends Node
## Headless sanity check: compiles every script and loads every scene / resource under res://
## (skips addons/, oot-main/, tww-main/). Run:
##   Godot_console.exe --headless --path . res://tests/check_all.tscn
## (as a scene so the autoloads - GameConfig, ItemDB, WorldRules... - exist)
## Errors print as usual; the summary line says how many files failed to load.

const SKIP := ["res://addons", "res://oot-main", "res://tww-main", "res://.godot", "res://art_src"]


func _ready() -> void:
	var files: Array[String] = []
	_walk("res://", files)
	var bad := 0
	for f in files:
		var r := ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_REUSE)
		if r == null:
			bad += 1
			print("CHECK FAIL: ", f)
		elif r is GDScript and not (r as GDScript).can_instantiate() and not f.ends_with("check_all.gd") and not f.ends_with("check_all.tscn"):
			bad += 1
			print("CHECK FAIL (script): ", f)
	print("CHECK DONE: %d files, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)


func _walk(dir: String, out: Array[String]) -> void:
	for s in SKIP:
		if dir.begins_with(s):
			return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)
