class_name SpriteSheet
extends RefCounted

## One of CS2's effect textures, and its sprite sheet where it has one: the
## sequences of frames a flame, a puff of steam or of smoke plays, each
## frame the rectangle of the texture it is drawn with (in UV).
##
## scripts/extract_assets.sh effects writes them under assets/effects/ by
## the texture's own path (materials/particle/fire_gas/fire_gas_batch_b_top
## .png), with <name>.sheet.json beside a sheet (scripts/effect_textures.gd).
## Read once, the first time asked for, and kept.

const DIR := "res://assets/effects"

static var _loaded := {}

var texture: Texture2D
## Each sequence's frames, as Rect2s in UV.
var sequences: Array[Array] = []
## Whether a sequence stops on its last frame (true) or loops.
var clamped: Array[bool] = []
## How long each frame of each sequence shows, where the sheet says (a frame
## can show for none: the steam's last); every frame alike where not.
var times: Array[PackedFloat32Array] = []
## The frame rectangles flattened into a one-row float texture, for a
## batched renderer to interpolate frames with different atlas rectangles.
## Created once at preparation; ordinary frame() users need none of it.
var _frame_metadata: Texture2D
var _frame_offsets := PackedInt32Array()
var _sequence_seconds := PackedFloat32Array()
var _frame_ends: Array[PackedFloat64Array] = []


## The texture at CS2's path (materials/... .vtex), with its sheet; null
## when it has not been extracted.
static func named(vtex_path: String) -> SpriteSheet:
	if _loaded.has(vtex_path):
		return _loaded[vtex_path]
	var base := DIR.path_join(vtex_path.get_basename())
	var sheet: SpriteSheet = null
	if ResourceLoader.exists(base + ".png"):
		sheet = SpriteSheet.new()
		sheet.texture = load(base + ".png") as Texture2D
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".sheet.json")) \
			if FileAccess.file_exists(base + ".sheet.json") else null
		if parsed is Dictionary:
			sheet.read(parsed)
	_loaded[vtex_path] = sheet
	return sheet


## Takes the sequences from a sheet.json's contents.
func read(parsed: Dictionary) -> void:
	sequences.clear()
	clamped.clear()
	times.clear()
	_frame_metadata = null
	_frame_offsets.clear()
	_sequence_seconds.clear()
	_frame_ends.clear()
	var offset := 0
	for sequence: Dictionary in parsed.get("sequences", []):
		var frames: Array[Rect2] = []
		for r: Array in sequence.get("frames", []):
			frames.append(Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]))
		sequences.append(frames)
		_frame_offsets.append(offset)
		offset += frames.size()
		clamped.append(bool(sequence.get("clamp", true)))
		var shown := PackedFloat32Array()
		for time: Variant in sequence.get("times", []):
			shown.append(float(time))
		times.append(shown if shown.size() == frames.size() else PackedFloat32Array())
		var seconds := 0.0
		var ends := PackedFloat64Array()
		for time in times[times.size() - 1]:
			seconds += maxf(time, 0.0)
			ends.append(seconds)
		_sequence_seconds.append(seconds)
		_frame_ends.append(ends)


## Current and next flat frame indices, and interpolation between them.
## Display times and zero-duration final frames follow frame(); a looping
## sequence interpolates its last frame back into the first.
func interpolation_data(seq: int, fraction: float) -> Vector3:
	if sequences.is_empty():
		return Vector3.ZERO
	var s := posmod(seq, sequences.size())
	var count := sequences[s].size()
	if count == 0:
		return Vector3.ZERO
	var offset := _frame_offsets[s]
	var shown: PackedFloat32Array = times[s] if s < times.size() else PackedFloat32Array()
	if shown.is_empty():
		var at := maxf(fraction, 0.0) * count if clamped[s] else fraction * count
		if clamped[s] and at >= count - 1:
			return Vector3(offset + count - 1, offset + count - 1, 0)
		var frame_index := floori(at)
		var index := clampi(frame_index, 0, count - 1) if clamped[s] else posmod(frame_index, count)
		return Vector3(offset + index, offset + (index + 1) % count, at - floorf(at))
	var total := _sequence_seconds[s]
	var into := maxf(fraction, 0.0) * total if clamped[s] else fraction * total
	if total <= 0.0 or (clamped[s] and into >= total):
		return Vector3(offset + count - 1, offset + count - 1, 0)
	if not clamped[s]:
		into = fposmod(into, total)
	var ends := _frame_ends[s]
	var low := 0
	var high := count
	# First end strictly after the requested stamp; duplicate ends skip
	# zero-duration frames exactly as the old duration walk did.
	while low < high:
		var middle := (low + high) >> 1
		if ends[middle] <= into:
			low = middle + 1
		else:
			high = middle
	if low >= count:
		return Vector3(offset + count - 1, offset + count - 1, 0)
	var before := ends[low - 1] if low > 0 else 0.0
	var next := mini(low + 1, count - 1) if clamped[s] else (low + 1) % count
	return Vector3(offset + low, offset + next, (into - before) / maxf(shown[low], 0.00000001))


## Each texel contains (u0, v0, u1, v1), without colour-space conversion.
## A plain texture has one whole-image frame. Call while loading the map.
func frame_metadata() -> Texture2D:
	if _frame_metadata != null:
		return _frame_metadata
	var count := 0
	for frames: Array in sequences:
		count += frames.size()
	var data := Image.create_empty(maxi(1, count), 1, false, Image.FORMAT_RGBAF)
	if count == 0:
		data.set_pixel(0, 0, Color(0, 0, 1, 1))
	var index := 0
	for frames: Array in sequences:
		for rectangle: Rect2 in frames:
			data.set_pixel(index, 0, Color(rectangle.position.x, rectangle.position.y, rectangle.end.x, rectangle.end.y))
			index += 1
	_frame_metadata = ImageTexture.create_from_image(data)
	return _frame_metadata


## The rectangle a sprite is drawn with: sequence seq (wrapped to those
## there are) at fraction of the way through its time (0 its first frame;
## past 1 a clamped sequence holds its last, a looping one goes round), each
## frame showing for its own display time. The whole texture when it is no
## sheet.
func frame(seq: int, fraction: float) -> Rect2:
	if sequences.is_empty():
		return Rect2(0.0, 0.0, 1.0, 1.0)
	var s := posmod(seq, sequences.size())
	var frames: Array = sequences[s]
	var shown: PackedFloat32Array = times[s] if s < times.size() else PackedFloat32Array()
	if shown.is_empty():
		var at := fraction * frames.size()
		return frames[clampi(floori(at), 0, frames.size() - 1) if clamped[s] else posmod(floori(at), frames.size())]
	var total := 0.0
	for time in shown:
		total += time
	var into := fraction * total
	if clamped[s]:
		if into >= total:
			return frames[frames.size() - 1]
	elif total > 0.0:
		into = fposmod(into, total)
	var until := 0.0
	for i in shown.size():
		until += shown[i]
		if into < until:
			return frames[i]
	return frames[frames.size() - 1]
