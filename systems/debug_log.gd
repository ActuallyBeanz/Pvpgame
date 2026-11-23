extends Node
## Autoload: DebugLog (loads first). Copies every print, warning and error into a
## log file, plus a performance line every few seconds, so problems can be read
## without watching the console.
##   Editor / console exe runs -> <project>/logs/<date>_<time>_<pid>.log
##   Exported builds          -> user://logs/
## Keeps the newest `keep_files` logs. logs/ has a .gdignore so Godot ignores it.

@export var perf_interval := 5.0
@export var keep_files := 10
@export var spike_ms := 25.0   ## frames slower than this count as hitches

var log_path := ""
var _logger: FileLogger
var _perf_t := 0.0
var _frames := 0
var _worst_ms := 0.0
var _spikes := 0


class FileLogger extends Logger:
	var file: FileAccess
	var mutex := Mutex.new()
	var errors := 0
	var warnings := 0
	const KINDS := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]

	func _log_message(message: String, error: bool) -> void:
		write(("[stderr] " if error else "") + message.strip_edges(false, true))

	func _log_error(function: String, file_path: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
		var msg := "%s: %s\n    at: %s (%s:%d)" % [
			KINDS[clampi(error_type, 0, 3)], rationale if rationale != "" else code,
			function, file_path, line]
		for bt in script_backtraces:
			if bt and not bt.is_empty():
				msg += "\n" + bt.format(4, 4)
		write(msg)

	func write(text: String) -> void:
		mutex.lock()
		if file:
			file.store_line("[%8.2f] %s" % [Time.get_ticks_msec() / 1000.0, text])
			file.flush()
		mutex.unlock()


func _init() -> void:
	var dir := ProjectSettings.globalize_path("res://logs") if OS.has_feature("editor") \
		else ProjectSettings.globalize_path("user://logs")
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir + "/.gdignore"):
		FileAccess.open(dir + "/.gdignore", FileAccess.WRITE)
	_prune(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	log_path = "%s/%s_%d.log" % [dir, stamp, OS.get_process_id()]
	_logger = FileLogger.new()
	_logger.file = FileAccess.open(log_path, FileAccess.WRITE)
	OS.add_logger(_logger)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_logger.write("=== session start | Godot %s | %s | GPU: %s | screen %.0f Hz | physics %d tps | interpolation %s | args %s" % [
		Engine.get_version_info().string, OS.get_name(),
		RenderingServer.get_video_adapter_name(),
		DisplayServer.screen_get_refresh_rate(),
		Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/common/physics_interpolation", false),
		" ".join(OS.get_cmdline_user_args())])


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_frames += 1
	_worst_ms = maxf(_worst_ms, ms)
	if ms > spike_ms:
		_spikes += 1
	_perf_t += delta
	if _perf_t >= perf_interval:
		_logger.write("[perf] fps %d | worst frame %.1f ms | hitches>%.0fms %d | process %.2f ms | physics %.2f ms | draw calls %d | objects %d | scene %s" % [
			Engine.get_frames_per_second(), _worst_ms, spike_ms, _spikes,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			get_tree().current_scene.scene_file_path.get_file() if get_tree().current_scene else "-"])
		_perf_t = 0.0
		_worst_ms = 0.0
		_spikes = 0


func _exit_tree() -> void:
	_logger.write("=== session end | %d errors | %d warnings" % [_logger.errors, _logger.warnings])


func _prune(dir: String) -> void:
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".log"))
	files.sort()
	while files.size() >= keep_files:
		DirAccess.remove_absolute(dir + "/" + files.pop_front())
