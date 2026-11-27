extends Node
## Autoload: Audio. Plays sounds by id, never by file path.
##   Audio.play_at("bow.fire", pos)          3D one-shot at a position
##   Audio.play("ui.select")                 flat (or 3D at the listener if spatial)
##   Audio.attach_loop("boomerang.spin", n)  looping 3D sound riding on a node
##   Audio.play_ambience("amb.field")        one background loop at a time
## Sounds are cosmetic and local: every peer plays them from events it already sees
## (synced state, RPCs it already receives), so audio never adds network traffic.
## Every Button in the game gets hover/press sounds automatically (see _hook_button).

## Emitted for every sound started (tests, debug overlays).
signal played(id: String)

const REGISTRY_PATH := "res://data/registry/sounds.tres"
const BUSES: Array[StringName] = [&"Music", &"SFX", &"Ambience", &"UI"]

@export var voices_3d := 32
@export var voices_flat := 8
@export var bus_volumes_db: Dictionary[StringName, float] = {
	&"Music": -6.0, &"SFX": 0.0, &"Ambience": -2.0, &"UI": -2.0,
}
@export var auto_button_sounds := true

var _defs: Dictionary = {}           # id -> SoundDef
var _last_pick: Dictionary = {}      # id -> last stream index (avoid instant repeats)
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_flat: Array[AudioStreamPlayer] = []
var _owner_id: Dictionary = {}       # player instance id -> sound id it is playing
var _ambience: AudioStreamPlayer
var _ambience_id := ""
var _loop_cache: Dictionary = {}     # stream -> looping copy


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_registry(REGISTRY_PATH)
	for i in voices_3d:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		add_child(p)
		_pool_3d.append(p)
	for i in voices_flat:
		var f := AudioStreamPlayer.new()
		add_child(f)
		_pool_flat.append(f)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Ambience"
	add_child(_ambience)
	if auto_button_sounds:
		get_tree().node_added.connect(_on_node_added)


func load_registry(path: String) -> void:
	var reg := load(path)
	if reg == null or not ("sounds" in reg):
		push_error("Audio: could not load %s" % path)
		return
	for id: String in reg.sounds:
		var d: Resource = reg.sounds[id]
		if d and not d.streams.is_empty():
			_defs[id] = d


func has_sound(id: String) -> bool:
	return _defs.has(id)


## Add or override an entry at runtime.
func register(id: String, def: Resource) -> void:
	_defs[id] = def


# ---------------------------------------------------------------- playback
## volume_db / pitch are added on top of the SoundDef's own values.
## Returns the 3D voice playing it (null for non-spatial sounds) so a caller can stop it early.
func play_at(id: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	var d: Resource = _defs.get(id)
	if d == null:
		_warn_missing(id)
		return null
	if not d.spatial:
		play(id, volume_db, pitch)
		return null
	var p := _voice_3d(id, d)
	p.global_position = pos
	_start(p, id, d, volume_db, pitch)
	p.max_distance = d.max_distance
	p.unit_size = maxf(1.0, d.max_distance / 8.0)
	return p


func play(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	var d: Resource = _defs.get(id)
	if d == null:
		_warn_missing(id)
		return
	if d.spatial:  # a 3D sound with no position: play it at the listener
		var cam := get_viewport().get_camera_3d()
		if cam:
			play_at(id, cam.global_position, volume_db, pitch)
			return
	var p := _voice_flat(id, d)
	_start(p, id, d, volume_db, pitch)


## Looping (or long) 3D sound that follows `node` and stops when it is freed.
func attach_loop(id: String, node: Node3D, volume_db := 0.0) -> AudioStreamPlayer3D:
	var d: Resource = _defs.get(id)
	if d == null or node == null:
		_warn_missing(id)
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = _pick(id, d)
	p.bus = d.bus
	p.volume_db = d.volume_db + volume_db
	p.max_distance = d.max_distance
	p.unit_size = maxf(1.0, d.max_distance / 8.0)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.autoplay = true
	node.add_child(p)
	played.emit(id)
	return p


func play_ambience(id: String, fade := 1.5) -> void:
	if id == _ambience_id and _ambience.playing:
		return
	var d: Resource = _defs.get(id)
	if d == null:
		_warn_missing(id)
		return
	_ambience_id = id
	_ambience.stream = _pick(id, d)
	_ambience.volume_db = -40.0
	_ambience.play()
	played.emit(id)
	create_tween().tween_property(_ambience, "volume_db", d.volume_db, fade)


func stop_ambience(fade := 1.0) -> void:
	_ambience_id = ""
	if not _ambience.playing:
		return
	var tw := create_tween()
	tw.tween_property(_ambience, "volume_db", -40.0, fade)
	tw.tween_callback(_ambience.stop)


func set_bus_volume(bus: StringName, db: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, db)


# ---------------------------------------------------------------- internals
func _start(p: Node, id: String, d: Resource, volume_db: float, pitch: float) -> void:
	p.stream = _pick(id, d)
	p.bus = d.bus
	p.volume_db = d.volume_db + volume_db
	p.pitch_scale = randf_range(d.pitch_min, d.pitch_max) * pitch
	_owner_id[p.get_instance_id()] = id
	p.play()
	played.emit(id)


func _pick(id: String, d: Resource) -> AudioStream:
	var n: int = d.streams.size()
	var i := randi() % n
	if n > 1 and i == _last_pick.get(id, -1):
		i = (i + 1 + randi() % (n - 1)) % n
	_last_pick[id] = i
	var s: AudioStream = d.streams[i]
	return _looped(s) if d.loop else s


func _looped(s: AudioStream) -> AudioStream:
	if not (s is AudioStreamWAV) or (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return s
	if not _loop_cache.has(s):
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
		_loop_cache[s] = w
	return _loop_cache[s]


func _voice_3d(id: String, d: Resource) -> AudioStreamPlayer3D:
	return _voice(_pool_3d, id, d) as AudioStreamPlayer3D


func _voice_flat(id: String, d: Resource) -> AudioStreamPlayer:
	return _voice(_pool_flat, id, d) as AudioStreamPlayer


## Free voice if there is one; if this id is at its voice cap, or the pool is full,
## reuse the voice that has played longest.
func _voice(pool: Array, id: String, d: Resource) -> Node:
	var same: Array = []
	var free_voice: Node = null
	var oldest: Node = pool[0]
	for p in pool:
		if not p.playing:
			if free_voice == null:
				free_voice = p
			continue
		if _owner_id.get(p.get_instance_id(), "") == id:
			same.append(p)
		if p.get_playback_position() > oldest.get_playback_position() or not oldest.playing:
			oldest = p
	if same.size() >= d.max_voices:
		var o: Node = same[0]
		for p in same:
			if p.get_playback_position() > o.get_playback_position():
				o = p
		o.stop()
		return o
	if free_voice:
		return free_voice
	oldest.stop()
	return oldest


func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, &"Master")
		set_bus_volume(b, bus_volumes_db.get(b, 0.0))


var _warned: Dictionary = {}
func _warn_missing(id: String) -> void:
	if not _warned.has(id):
		_warned[id] = true
		push_warning("Audio: no sound registered for '%s'" % id)


# ---------------------------------------------------------------- UI buttons
func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		_hook_button.call_deferred(n)


func _hook_button(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.has_meta(&"_audio_hooked"):
		return
	b.set_meta(&"_audio_hooked", true)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			play("ui.hover"))
	var text: String = str(b.get("text")).to_lower() if "text" in b else ""
	var back: bool = text.contains("leave") or text.contains("back") or text.contains("cancel") \
		or text.contains("quit")
	if b is OptionButton:
		(b as OptionButton).item_selected.connect(func(_i: int) -> void: play("ui.select"))
	b.pressed.connect(func() -> void: play("ui.back" if back else "ui.select"))
