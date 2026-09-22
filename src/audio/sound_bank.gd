class_name SoundBank
extends RefCounted

## The game's sounds, as scripts/extract_assets.sh sounds leaves them: one
## audio file per sound, a few numbered variants to a set (ak47_01 to _04,
## sand_01 to _12). A set is asked for by the path its variants share, and
## found once. Without the extraction there are no sounds, and the game
## plays on in silence.

const ROOT := "res://assets/sounds/sounds"

static var _sets := {}
static var _randomizers := {}


static func available() -> bool:
	return DirAccess.dir_exists_absolute(ROOT)


## Every variant of a set: the audio files in the set's directory whose
## names start with its stem, sorted. "player/footsteps/sand_" is the
## twelve sand footsteps; "weapons/ak47/ak47_draw" is the one draw.
static func variants(stem: String) -> Array[AudioStream]:
	if _sets.has(stem):
		return _sets[stem]
	var streams: Array[AudioStream] = []
	var directory := ROOT.path_join(stem.get_base_dir())
	var prefix := stem.get_file()
	var dir := DirAccess.open(directory)
	if dir != null:
		var files := dir.get_files()
		files.sort()
		for file in files:
			if not file.begins_with(prefix):
				continue
			var extension := file.get_extension().to_lower()
			if extension not in ["wav", "mp3", "ogg"]:
				continue
			# Only the set itself: "sand_01", not "sand_wet_01".
			var rest := file.get_basename().trim_prefix(prefix)
			if not (rest.is_empty() or rest.is_valid_int() or rest.begins_with("_")):
				continue
			var stream := load(directory.path_join(file)) as AudioStream
			if stream != null:
				streams.append(stream)
	_sets[stem] = streams
	return streams


## One of a set's variants, at random, or null for an empty set.
static func pick(stem: String, rng: RandomNumberGenerator) -> AudioStream:
	var streams := variants(stem)
	if streams.is_empty():
		return null
	return streams[rng.randi_range(0, streams.size() - 1)]


## A set as one stream that plays a different variant, at a slightly
## different pitch, each time it is played: what a player holds so that
## shots can overlap without the stream being swapped under them. Null
## for an empty set.
static func randomizer(stem: String) -> AudioStreamRandomizer:
	if _randomizers.has(stem):
		return _randomizers[stem]
	var streams := variants(stem)
	var random: AudioStreamRandomizer = null
	if not streams.is_empty():
		random = AudioStreamRandomizer.new()
		random.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		random.random_pitch = 1.05
		for stream in streams:
			random.add_stream(-1, stream)
	_randomizers[stem] = random
	return random
