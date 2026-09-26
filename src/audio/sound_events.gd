class_name SoundEvents
extends Node

## Plays CS2's sound events the way CS2's csgo_mega stack does, on the
## client, per frame: the shared player the grenade, round and low-ammo
## sounds are built on (reference/playtest-2026-09-25.md, issues 19 to 21).
##
## The events are reference/sounds/sound_events.json, generated from CS2's
## own .vsndevts text by scripts/sound_events.sh; the mixgroups are the
## buses of default_bus_layout.tres, generated with it. What a start does,
## in the stack's order (reference/research/audio-engine.md 1.3):
##
## - Who hears it: an event tagged localplayeronly only when the source is
##   the listener's own player (options.local).
## - Blocks: a start is refused while the same event (from the same source,
##   when block_match_entity) started within block_duration and
##   block_distance; block_other refuses events whose names hold
##   block_other_name for a while (inferred from the field names).
## - Instance limit: past instance_limit copies from one source, the oldest
##   stops (with its fade).
## - Children: the events in soundevent_01 start with it (a gunshot's
##   distant layer), at the same place.
## - Random volume and pitch, drawn once; a file picked at random, never the
##   same one twice running.
## - After its delay, it plays on the mixgroup's bus. A placed sound is an
##   AudioStreamPlayer3D with Godot's own falloff and low-pass off; its
##   volume is the event's curves at the listener's distance, set every
##   frame, and its panning the unfiltered-stereo curve (1 at your own gun
##   plays it as plain stereo). A UI sound, or one started with no place,
##   plays flat.
## - A sound started at a node follows it (a molotov's loop in flight); a
##   loop plays until stop() or its self_destruct_time; a stop fades by the
##   event's fade curve, or over voice_fade_out_time.
##
## Not modelled yet: occlusion, reverb, the mix layers (the ducking; their
## numbers are in the table), doppler, the impact-speed and velocity
## curves, and the music kit's priorities and stop flags (issue 21).
##
## Sounds are views (CLAUDE.md): a view calls start() from _process, on
## what the GameWorld's events handed out, never from inside the tick. The
## table and the files are read when the view is made (load_events), so a
## start reads nothing from the disk. Without the extraction every start
## still runs its rules and keeps its voice (voices()), and nothing sounds.

const TABLE := "res://reference/sounds/sound_events.json"
## Where scripts/extract_assets.sh sounds leaves CS2's sounds/ folder.
const SOUNDS_ROOT := "res://assets/sounds/"
const EXTENSIONS := ["wav", "mp3", "ogg"]
const SILENT_DB := -80.0

static var _table := {}
static var _names_by_lower := {}
static var _events := {}
static var _streams := {}
## Files read at a start because nothing loaded them beforehand. A view
## that loads its events when it is made keeps this at 0.
static var late_loads := 0

## Whose ears: the listener's position. Unset, the viewport's camera.
var listener: Node3D
## Volume convars by name (snd_roundend_volume): what an event with a
## volume_convar is scaled by. A missing one is 1.0.
var convars := {}
## Seconds a voice with no file to play (no extraction) is kept, so a check
## can watch the limits and fades without assets. 0 ends it on the next
## frame.
var silent_length := 0.0
var rng := RandomNumberGenerator.new()

var _now := 0.0
var _next_id := 1
var _voices: Array[Voice] = []
## [event name lower-cased, source, position, until], the blocks set by
## starts; [substring, position, distance, until] for block_other.
var _blocks: Array = []
var _other_blocks: Array = []
var _last_pick := {}


class Voice:
	var id: int
	var event: SoundEvent
	var source: int
	var position: Vector3
	var placed: bool
	var follow: Node3D
	var starts_at: float
	var started := false
	var volume_offset: float
	var pitch: float
	var suppressed: bool
	var stopped_at := -1.0
	## When it is over by itself (its file's length), and when its
	## self_destruct_time stops it (with a fade).
	var ends_at := INF
	var stops_at := INF
	var ended := false
	var player: Node
	var gain := 0.0


## The whole table: {"source", "defaults", "mixgroups", "mixlayers",
## "events"}. Read once, the first time anything asks.
static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		if parsed is Dictionary:
			_table = parsed
			for name in (_table.get("events", {}) as Dictionary):
				_names_by_lower[String(name).to_lower()] = name
		else:
			push_error("SoundEvents: cannot read %s" % TABLE)
	return _table


## An event by name, in any case (vdata spells Default.nearlyempty, the
## events Default.NearlyEmpty), with its type's defaults under its own
## fields; null if there is none.
static func find(event_name: String) -> SoundEvent:
	var key := String(_names_by_lower.get(event_name.to_lower(), "")) if not table().is_empty() else ""
	if key.is_empty():
		return null
	if _events.has(key):
		return _events[key]
	var own: Dictionary = table().events[key]
	var type := String(own.get("type", "csgo_mega"))
	var fields: Dictionary = (table().defaults.get(type, {}) as Dictionary).duplicate()
	fields.merge(own, true)
	var event := SoundEvent.from_fields(key, fields)
	_events[key] = event
	return event


static func has_event(event_name: String) -> bool:
	return find(event_name) != null


## The bus a mixgroup plays on: its own, or Master (CS2's All, and any
## group the layout lacks).
static func bus_for(mixgroup: String) -> StringName:
	return StringName(mixgroup) if AudioServer.get_bus_index(mixgroup) > 0 else &"Master"


## Names with every child they start, each once.
static func with_children(names: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var queue := Array(names)
	while not queue.is_empty():
		var event := find(String(queue.pop_front()))
		if event == null or event.name in result:
			continue
		result.append(event.name)
		queue.append_array(Array(event.children))
	return result


## Reads the events' files, and their children's, now rather than at their
## first start. Call it when the view is made.
static func load_events(names: PackedStringArray) -> void:
	if not SoundBank.available():
		return
	for name in with_children(names):
		for file in find(name).files:
			_stream(file)


## A file's stream, read from the disk the first time; null if it was not
## extracted.
static func _stream(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var stream: AudioStream = null
	var base := SOUNDS_ROOT + file.get_basename()
	for extension in EXTENSIONS:
		if ResourceLoader.exists(base + "." + extension):
			stream = load(base + "." + extension) as AudioStream
			break
	_streams[file] = stream
	return stream


## Starts an event. at is where (a Vector3, or a Node3D to follow; null to
## play it flat); source is who makes it (a userid or an entity's id), for
## the limits and blocks. options: local (the source is the listener's own
## player), suppressed (a stealthy source: the silent reload). Returns the
## voice's id, or 0 if the event is not heard (unknown, someone else's
## localplayeronly sound, or blocked).
func start(event_name: String, at: Variant = null, source: int = -1, options := {}) -> int:
	var event := find(event_name)
	if event == null:
		return 0
	if event.local_player_only and not options.get("local", false):
		return 0
	var voice := Voice.new()
	voice.event = event
	voice.source = source
	if at is Node3D:
		voice.follow = at
		voice.position = (at as Node3D).global_position
		voice.placed = not event.is_ui_sound
	elif at is Vector3:
		voice.position = at
		voice.placed = not event.is_ui_sound
	if _blocked(event, source, voice.position):
		return 0
	_block(event, source, voice.position)
	if event.instance_limit > 0:
		var same := _voices.filter(func(v: Voice): return v.event == event and v.source == source and v.stopped_at < 0.0 and not v.ended)
		for i in range(0, same.size() - event.instance_limit + 1):
			_stop_voice(same[i])
	voice.id = _next_id
	_next_id += 1
	voice.volume_offset = rng.randf_range(event.volume_random_min, event.volume_random_max) if event.volume_random_max > event.volume_random_min else event.volume_random_min
	voice.pitch = event.pitch + (rng.randf_range(event.pitch_random_min, event.pitch_random_max) if event.pitch_random_max > event.pitch_random_min else event.pitch_random_min)
	voice.suppressed = options.get("suppressed", false)
	voice.starts_at = _now + event.delay
	_voices.append(voice)
	if event.delay <= 0.0:
		_begin(voice)
	for child in event.children:
		# At the same place either way: with set_child_position off, CS2's
		# child finds its own (the entity's, or a soundscape's), which here is
		# the same place.
		start(child, at, source, options)
	return voice.id


## Stops a voice, with its fade.
func stop(id: int) -> void:
	for voice in _voices:
		if voice.id == id:
			_stop_voice(voice)


## Stops every voice of an event, from one source or (-1) any.
func stop_event(event_name: String, source: int = -1) -> void:
	var event := find(event_name)
	for voice in _voices:
		if voice.event == event and (source == -1 or voice.source == source):
			_stop_voice(voice)


func is_playing(id: int) -> bool:
	for voice in _voices:
		if voice.id == id:
			return not voice.ended and voice.stopped_at < 0.0
	return false


## What is playing or waiting, for checks and debugging: one dictionary a
## voice, {id, event, source, position, started, stopped, gain, pitch,
## bus, has_player}. The position is the source's, before the event's offset.
func voices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for voice in _voices:
		if voice.ended:
			continue
		result.append({
			"id": voice.id, "event": voice.event.name, "source": voice.source, "position": voice.position,
			"started": voice.started, "stopped": voice.stopped_at >= 0.0,
			"gain": voice.gain, "bus": bus_for(voice.event.mixgroup),
			"has_player": voice.player != null, "pitch": voice.pitch,
		})
	return result


func _process(delta: float) -> void:
	advance(delta)


## Moves the player on by delta seconds: what _process does each frame.
func advance(delta: float) -> void:
	_now += delta
	var ears := _listener_position()
	for voice in _voices:
		if voice.ended:
			continue
		if not voice.started:
			if _now + 0.000001 < voice.starts_at:
				continue
			_begin(voice)
		if voice.follow != null:
			if is_instance_valid(voice.follow):
				voice.position = voice.follow.global_position
			else:
				voice.follow = null
		if _now >= voice.ends_at:
			voice.ended = true
			continue
		if _now >= voice.stops_at:
			_stop_voice(voice)
		_update(voice, ears)
	_forget_ended()


## When the voice starts to sound: picks the file and makes its player.
func _begin(voice: Voice) -> void:
	voice.started = true
	var event := voice.event
	if event.self_destruct_time >= 0.0:
		voice.stops_at = voice.starts_at + event.self_destruct_time
	var ears := _listener_position()
	var distance := _distance(voice, ears)
	# A sound that starts past its silent end and stays put is never heard:
	# no player (a far bot's shot plays only its distant layer).
	var out_of_reach := voice.placed and voice.follow == null and distance >= event.silent_beyond()
	var stream := _pick(event) if not out_of_reach else null
	if stream == null:
		voice.ends_at = _now + (0.0 if out_of_reach else silent_length)
		voice.gain = event.gain(distance, 0.0, voice.volume_offset, voice.suppressed, _convar(event))
		return
	var player: Node
	if voice.placed:
		var placed := AudioStreamPlayer3D.new()
		placed.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		# CS2 has no low-pass by distance; occlusion will be its own.
		placed.attenuation_filter_cutoff_hz = 20500.0
		placed.max_db = 24.0
		player = placed
	else:
		player = AudioStreamPlayer.new()
	player.set("stream", stream)
	player.set("bus", bus_for(event.mixgroup))
	player.set("pitch_scale", maxf(voice.pitch, 0.01))
	player.connect("finished", _on_finished.bind(voice))
	# Ended by its length too, not only by finished, which a paused or
	# silent (headless) mix never sends.
	if not _loops(stream) and stream.get_length() > 0.0:
		voice.ends_at = _now + stream.get_length() / maxf(voice.pitch, 0.01) + 0.05
	add_child(player)
	voice.player = player
	_update(voice, ears)
	player.call("play")


static func _loops(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		return bool(stream.get("loop"))
	return false


func _on_finished(voice: Voice) -> void:
	voice.ended = true


func _update(voice: Voice, ears: Vector3) -> void:
	var event := voice.event
	var distance := _distance(voice, ears)
	var level := event.gain(distance, _now - voice.starts_at, voice.volume_offset, voice.suppressed, _convar(event))
	if voice.stopped_at >= 0.0:
		var since := _now - voice.stopped_at
		level *= event.fade_at(since)
		if since >= event.fade_length():
			voice.ended = true
	voice.gain = level
	if voice.player == null:
		return
	voice.player.set("volume_db", linear_to_db(level) if level >= event.voice_culling_threshold else SILENT_DB)
	if voice.player is AudioStreamPlayer3D:
		var placed := voice.player as AudioStreamPlayer3D
		if placed.is_inside_tree():
			placed.global_position = voice.position + event.position_offset
		placed.panning_strength = 1.0 - event.stereo_at(distance)


func _stop_voice(voice: Voice) -> void:
	if voice.ended or voice.stopped_at >= 0.0:
		return
	if not voice.started or voice.player == null:
		voice.ended = true
		return
	voice.stopped_at = _now


func _forget_ended() -> void:
	var kept: Array[Voice] = []
	for voice in _voices:
		if voice.ended:
			if voice.player != null:
				voice.player.queue_free()
				voice.player = null
		else:
			kept.append(voice)
	_voices = kept
	_blocks = _blocks.filter(func(block: Array): return float(block[3]) > _now)
	_other_blocks = _other_blocks.filter(func(block: Array): return float(block[3]) > _now)


func _pick(event: SoundEvent) -> AudioStream:
	if event.files.is_empty() or not SoundBank.available():
		return null
	var streams: Array[AudioStream] = []
	var picks: Array[int] = []
	for i in event.files.size():
		if not _streams.has(event.files[i]):
			late_loads += 1
		var stream := _stream(event.files[i])
		if stream != null:
			streams.append(stream)
			picks.append(i)
	if streams.is_empty():
		return null
	# random_exclusive: never the file played last, when there is another.
	var choice := rng.randi_range(0, streams.size() - 1)
	if streams.size() > 1 and picks[choice] == int(_last_pick.get(event.name, -1)):
		choice = (choice + 1 + rng.randi_range(0, streams.size() - 2)) % streams.size()
	_last_pick[event.name] = picks[choice]
	return streams[choice]


func _blocked(event: SoundEvent, source: int, at: Vector3) -> bool:
	var lower := event.name.to_lower()
	if event.block_matching_events:
		for block in _blocks:
			if block[0] == lower and float(block[3]) > _now \
					and (not event.block_match_entity or int(block[1]) == source) \
					and at.distance_to(block[2]) <= event.block_distance:
				return true
	for block in _other_blocks:
		if float(block[3]) > _now and lower.contains(String(block[0])) and at.distance_to(block[1]) <= float(block[2]):
			return true
	return false


func _block(event: SoundEvent, source: int, at: Vector3) -> void:
	if event.block_duration > 0.0:
		_blocks.append([event.name.to_lower(), source, at, _now + event.block_duration])
	if event.block_other and not event.block_other_name.is_empty():
		_other_blocks.append([event.block_other_name.to_lower(), at, event.block_other_distance, _now + event.block_other_duration])


func _convar(event: SoundEvent) -> float:
	return float(convars.get(event.volume_convar, 1.0)) if not event.volume_convar.is_empty() else 1.0


func _distance(voice: Voice, ears: Vector3) -> float:
	if not voice.placed:
		return 0.0
	return (voice.position + voice.event.position_offset).distance_to(ears)


func _listener_position() -> Vector3:
	if listener != null and is_instance_valid(listener) and listener.is_inside_tree():
		return listener.global_position
	var viewport := get_viewport() if is_inside_tree() else null
	var camera := viewport.get_camera_3d() if viewport != null else null
	return camera.global_position if camera != null else Vector3.ZERO
