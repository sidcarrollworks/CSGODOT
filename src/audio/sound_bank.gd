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
## Whether the extraction is there, looked for once: 1 yes, 0 no, -1 not
## looked yet. Every footstep node asks on every tick, and every shot twice,
## and a look at the disk takes a fifth of a millisecond (through the assets
## junction), which on dust2 with ten players was a quarter of the tick.
static var _available := -1


static func available() -> bool:
	if _available < 0:
		_available = 1 if DirAccess.dir_exists_absolute(ROOT) else 0
	return _available == 1


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


## Loads sets now rather than the first time each plays: a set is read
## from the disk the first time it is asked for, which in play is a hitch of
## a few milliseconds, and tens with the files not yet in the disk's cache.
static func load_sets(stems: PackedStringArray) -> void:
	if not available():
		return
	for stem in stems:
		if not stem.is_empty():
			randomizer(stem)


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
	var random := _random_over(variants(stem))
	_randomizers[stem] = random
	return random


## The same over several stems' variants together: a set named file by
## file (a gun's shots, ak47_01 to _04 but not ak47-1). Kept by the stems
## joined, so asking again builds nothing.
static func randomizer_of(stems: PackedStringArray) -> AudioStreamRandomizer:
	var key := ",".join(stems)
	if _randomizers.has(key):
		return _randomizers[key]
	# A stem's variants take in names that go on from it (ak47_boltpull has
	# ak47_boltpull_01), which may be named too: each once.
	var streams: Array[AudioStream] = []
	for stem in stems:
		for stream in variants(stem):
			if not streams.has(stream):
				streams.append(stream)
	var random := _random_over(streams)
	_randomizers[key] = random
	return random


static func _random_over(streams: Array[AudioStream]) -> AudioStreamRandomizer:
	if streams.is_empty():
		return null
	var random := AudioStreamRandomizer.new()
	random.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	random.random_pitch = 1.05
	for stream in streams:
		random.add_stream(-1, stream)
	return random
