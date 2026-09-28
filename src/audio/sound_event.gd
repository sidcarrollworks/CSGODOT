class_name SoundEvent
extends RefCounted

## One of CS2's sound events, as reference/sounds/sound_events.json holds
## it: the event's own fields over its type's defaults. What a CS2 sound is
## and how the csgo_mega stack turns these fields into a level is
## reference/research/audio-engine.md section 1; this keeps the fields that
## stack reads, and the arithmetic, as pure functions a check can call.
##
## Read the way the stack reads them (audio-engine.md 1.3):
## - A level is the event's volume (plus its random offset, drawn once at
##   the start), times the distance curve at the listener's distance, times
##   the time curve at the time played, times a volume convar's value. The
##   mixgroup's level is the bus's (default_bus_layout.tres).
## - A curve is straight between its points and holds its end values past
##   either end (audio-engine.md 1.2, inferred; Local check A2).
## - A stealthy source (the silent reload) divides the distance by the
##   falloff multiplier and multiplies the level by the volume multiplier.
## - The unfiltered-stereo curve says how much of the sound plays as plain
##   stereo rather than placed: 1 at your own gun, 0 past 300 units.

## The name as the table spells it (Weapon_AK47.Single).
var name: String
## The stack: csgo_mega for almost every sound, csgo_music for the kit.
var type: String
## The files a start picks from, as CS2 names them
## (sounds/weapons/ak47/ak47_01.vsnd).
var files: PackedStringArray
var volume: float
var volume_random_min: float
var volume_random_max: float
var pitch: float
var pitch_random_min: float
var pitch_random_max: float
var mixgroup: String
## Seconds from the start to the sound.
var delay: float
## [[units, share], ...], empty when the event does not fall off.
var distance_curve: Array
var stereo_curve: Array
## [[seconds, share], ...] from the start, empty when unused.
var time_curve: Array
## [[seconds, share], ...] from a stop, empty for the plain fade.
var fadetime_curve: Array
var distance_multiplier: float
## Copies of this event one source may play at once; 0 for no limit. A
## start past it stops the oldest.
var instance_limit: int
var block_matching_events: bool
var block_match_entity: bool
var block_duration: float
var block_distance: float
var block_other: bool
var block_other_name: String
var block_other_duration: float
var block_other_distance: float
## Events started with this one (a gunshot's distant layer), when
## enable_child_events is set.
var children: PackedStringArray
var set_child_position: bool
## In Godot's axes (Y up): CS2's [x, y, z] as (x, z, -y).
var position_offset: Vector3
var is_ui_sound: bool
## Heard only by the player who makes it (draws, inspects): the event's
## metadata says "localplayeronly".
var local_player_only: bool
## Seconds after which the sound stops by itself; negative for never.
var self_destruct_time: float
var voice_fade_out_time: float
var voice_culling_threshold: float
var suppression_enable: bool
var suppression_volume_multiplier: float
var suppression_falloff_multiplier: float
## The convar that scales it (snd_roundend_volume), or empty.
var volume_convar: String
## The file's own length, when the table gives it.
var duration: float
var ducking_bypass: float
var dsp_bypass: float
## Every field, for what the typed ones above leave out (the music kit's
## stop flags and sync points, occlusion, reverb).
var fields: Dictionary


static func from_fields(event_name: String, event_fields: Dictionary) -> SoundEvent:
	var event := SoundEvent.new()
	event.name = event_name
	event.fields = event_fields
	event.type = String(event_fields.get("type", "csgo_mega"))
	var list: Variant = event_fields.get("vsnd_files_track_01", event_fields.get("vsnd_files", []))
	event.files = PackedStringArray(list if list is Array else [list])
	event.volume = _number(event_fields, "volume", 1.0)
	event.volume_random_min = _number(event_fields, "volume_random_min", 0.0)
	event.volume_random_max = _number(event_fields, "volume_random_max", 0.0)
	event.pitch = _number(event_fields, "pitch", 1.0)
	event.pitch_random_min = _number(event_fields, "pitch_random_min", 0.0)
	event.pitch_random_max = _number(event_fields, "pitch_random_max", 0.0)
	event.mixgroup = String(event_fields.get("mixgroup", "All"))
	event.delay = _number(event_fields, "delay", 0.0)
	event.distance_curve = _curve(event_fields, "distance_volume_mapping_curve", "use_distance_volume_mapping_curve")
	event.stereo_curve = _curve(event_fields, "distance_unfiltered_stereo_mapping_curve", "use_distance_unfiltered_stereo_mapping_curve")
	event.time_curve = _curve(event_fields, "time_volume_mapping_curve", "use_time_volume_mapping_curve")
	event.fadetime_curve = _curve(event_fields, "fadetime_volume_mapping_curve", "use_fadetime_volume_mapping_curve")
	event.distance_multiplier = _number(event_fields, "distance_multiplier", 1.0)
	event.instance_limit = int(_number(event_fields, "instance_limit", 0.0))
	event.block_matching_events = _flag(event_fields, "block_matching_events")
	event.block_match_entity = _flag(event_fields, "block_match_entity")
	event.block_duration = _number(event_fields, "block_duration", 0.0)
	event.block_distance = _number(event_fields, "block_distance", 0.0)
	event.block_other = _flag(event_fields, "block_other")
	event.block_other_name = String(event_fields.get("block_other_name", ""))
	event.block_other_duration = _number(event_fields, "block_other_duration", 0.0)
	event.block_other_distance = _number(event_fields, "block_other_distance", 0.0)
	if _flag(event_fields, "enable_child_events"):
		var child_list: Variant = event_fields.get("soundevent_01", [])
		event.children = PackedStringArray(child_list if child_list is Array else [child_list])
	event.set_child_position = _flag(event_fields, "set_child_position", true)
	var offset: Array = event_fields.get("position_offset", [0.0, 0.0, 0.0])
	if offset.size() == 3:
		event.position_offset = Vector3(float(offset[0]), float(offset[2]), -float(offset[1]))
	event.is_ui_sound = _flag(event_fields, "is_ui_sound")
	var metadata: Variant = event_fields.get("metadata", [])
	event.local_player_only = metadata is Array and "localplayeronly" in metadata
	event.self_destruct_time = _number(event_fields, "self_destruct_time", -1.0)
	event.voice_fade_out_time = _number(event_fields, "voice_fade_out_time", 0.2)
	event.voice_culling_threshold = _number(event_fields, "voice_culling_threshold", 0.001)
	event.suppression_enable = _flag(event_fields, "suppression_enable")
	event.suppression_volume_multiplier = _number(event_fields, "suppression_volume_multiplier", 1.0)
	event.suppression_falloff_multiplier = _number(event_fields, "suppression_falloff_multiplier", 1.0)
	# The music stack scales every cue by its convar; csgo_mega only when
	# use_volume_convar is set.
	if event.type == "csgo_music" or _flag(event_fields, "use_volume_convar"):
		event.volume_convar = String(event_fields.get("volume_convar", ""))
	event.duration = _number(event_fields, "vsnd_duration", 0.0)
	event.ducking_bypass = _number(event_fields, "ducking_bypass", 0.0)
	event.dsp_bypass = _number(event_fields, "dsp_bypass", 0.0)
	return event


## A curve's share at x: straight between its points, held past either
## end; 1 for no curve.
static func curve_at(curve: Array, x: float) -> float:
	if curve.is_empty():
		return 1.0
	if x <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		if x <= float(curve[i][0]):
			var from: Array = curve[i - 1]
			var to: Array = curve[i]
			var span := float(to[0]) - float(from[0])
			if span <= 0.0:
				return float(to[1])
			return lerpf(float(from[1]), float(to[1]), (x - float(from[0])) / span)
	return float(curve[-1][1])


## The level at a distance from the listener, elapsed seconds after the
## start, before the mixgroup's: the stack's product (audio-engine.md 1.3,
## step 9) less the factors this build does not model (impact speed,
## velocity, surf). volume_offset is the start's random draw; convar the
## volume convar's value.
func gain(distance: float, elapsed: float = 0.0, volume_offset: float = 0.0, suppressed: bool = false, convar: float = 1.0) -> float:
	var stealthy := suppressed and suppression_enable
	var at := distance * distance_multiplier
	if stealthy and suppression_falloff_multiplier > 0.0:
		at /= suppression_falloff_multiplier
	var level := (volume + volume_offset) * curve_at(distance_curve, at) * curve_at(time_curve, elapsed) * convar
	if stealthy:
		level *= suppression_volume_multiplier
	return maxf(level, 0.0)


## How much plays as plain stereo at a distance: 1 unplaced, 0 fully placed.
func stereo_at(distance: float) -> float:
	return clampf(curve_at(stereo_curve, distance), 0.0, 1.0) if not stereo_curve.is_empty() else 0.0


## The share left seconds after a stop: the event's fade curve, or a
## straight fade over voice_fade_out_time.
func fade_at(seconds: float) -> float:
	if not fadetime_curve.is_empty():
		return clampf(curve_at(fadetime_curve, seconds), 0.0, 1.0)
	if voice_fade_out_time <= 0.0:
		return 0.0
	return clampf(1.0 - seconds / voice_fade_out_time, 0.0, 1.0)


## Seconds a stop takes to fall silent.
func fade_length() -> float:
	if not fadetime_curve.is_empty():
		return float(fadetime_curve[-1][0])
	return maxf(voice_fade_out_time, 0.0)


## The distance past which the event is silent for good (its curve ends at
## 0), or INF.
func silent_beyond() -> float:
	if distance_curve.is_empty() or float(distance_curve[-1][1]) > 0.0:
		return INF
	var end := float(distance_curve[-1][0])
	# Back to the first point of the silent tail.
	for i in range(distance_curve.size() - 1, -1, -1):
		if float(distance_curve[i][1]) > 0.0:
			break
		end = float(distance_curve[i][0])
	return end / distance_multiplier if distance_multiplier > 0.0 else INF


static func _number(source: Dictionary, field: String, fallback: float) -> float:
	var value: Variant = source.get(field, fallback)
	if value is bool:
		return 1.0 if value else 0.0
	if value is String:
		return value.to_float() if value.is_valid_float() else fallback
	return float(value)


static func _flag(source: Dictionary, field: String, fallback: bool = false) -> bool:
	var value: Variant = source.get(field, fallback)
	if value is String:
		return value == "true" or value == "1"
	return bool(value)


static func _curve(source: Dictionary, field: String, use_field: String) -> Array:
	if not _flag(source, use_field, false):
		return []
	var curve: Variant = source.get(field, [])
	return curve if curve is Array else []
