class_name ClientPreferences
extends Resource

## Client-only settings. Read on startup, saved by an explicit UI action;
## never read from disk on the simulation tick. Audio keeps its identity so
## active RoundSounds listeners see changes through the same resource.
const FILE_PATH := "user://client_settings.cfg"
# Current Panorama settings_kbmouse sensitivity widget bounds.
const MIN_SENSITIVITY := 0.1
const MAX_SENSITIVITY := 8.0
const MUSIC_FIELDS: Array[StringName] = [
	&"music_volume", &"round_start", &"round_action", &"round_end", &"mvp",
	&"map_objective", &"ten_second_warning", &"death_camera", &"menu_music",
]
var sensitivity := 2.0
var audio := AudioSettings.new()
static var _current: ClientPreferences


static func current() -> ClientPreferences:
	if _current == null:
		_current = read_file(FILE_PATH)
	return _current


static func read_file(path: String) -> ClientPreferences:
	var result := ClientPreferences.new()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return result
	result.sensitivity = _number(config.get_value("input", "sensitivity", result.sensitivity),
		result.sensitivity, MIN_SENSITIVITY, MAX_SENSITIVITY)
	for field in MUSIC_FIELDS:
		result.audio.set(field, _number(config.get_value("music", field, result.audio.get(field)),
			result.audio.get(field), 0.0, 1.0))
	return result


static func _number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)


func copy() -> ClientPreferences:
	var result := ClientPreferences.new()
	result.apply_from(self)
	return result


func apply_from(other: ClientPreferences) -> void:
	sensitivity = _number(other.sensitivity, 2.0, MIN_SENSITIVITY, MAX_SENSITIVITY)
	var defaults := AudioSettings.new()
	for field in MUSIC_FIELDS:
		audio.set(field, _number(other.audio.get(field), defaults.get(field), 0.0, 1.0))


func save_file(path: String = FILE_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("input", "sensitivity", sensitivity)
	for field in MUSIC_FIELDS:
		config.set_value("music", field, audio.get(field))
	return config.save(path)
