class_name RecoilPattern
extends RefCounted

## Loads and saves spray patterns as CSV.
##
## A pattern is a list of per-shot aim offsets in degrees, indexed by shot
## number. CS generates these from a per-weapon seed in the game's weapon data,
## which is not extractable, so ours are data files that get measured and
## refined rather than code that reproduces Valve's generator.
##
## That turns out to be the better arrangement anyway: measuring a pattern and
## dropping it in a file is a tighter loop than reverse-engineering a PRNG, and
## the file is directly comparable against a reference image.

const PATTERN_DIR := "res://reference/spray_patterns"

## Every pattern read, by its file, for the next weapon of the kind: one is
## built on every equip and every respawn, and each read the file from the
## disk again. Handed out as copies. A pattern copied over its file while the
## game runs is read at the next start.
static var _loaded := {}


static func load_pattern(weapon_name: String) -> PackedVector2Array:
	var path := PATTERN_DIR.path_join("%s.csv" % weapon_name)
	if not _loaded.has(path):
		_loaded[path] = load_from(path)
	return (_loaded[path] as PackedVector2Array).duplicate()


static func load_from(path: String) -> PackedVector2Array:
	var pattern := PackedVector2Array()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("No spray pattern at %s" % path)
		return pattern

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var fields := line.split(",")
		if fields.size() < 3:
			continue
		pattern.append(Vector2(float(fields[1]), float(fields[2])))
	file.close()
	return pattern


## Writes a pattern out in the same format, so a measured spray can go straight
## back into the file it came from. Each line of the note is a comment line.
static func save_to(path: String, pattern: PackedVector2Array, note: String = "") -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if not note.is_empty():
		for line in note.split("\n"):
			file.store_line("# %s" % line)
	file.store_line("# shot,x_degrees,y_degrees")
	for index in pattern.size():
		file.store_line("%d,%.4f,%.4f" % [
			index, pattern[index].x, pattern[index].y
		])
	file.close()
	return OK


## The offset for a shot, holding the last entry once the pattern runs out.
## CS patterns cover the magazine; anything past the end should not move.
static func offset_for(pattern: PackedVector2Array, shot_index: int) -> Vector2:
	if pattern.is_empty():
		return Vector2.ZERO
	return pattern[clampi(shot_index, 0, pattern.size() - 1)]
