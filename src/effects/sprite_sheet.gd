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
	for sequence: Dictionary in parsed.get("sequences", []):
		var frames: Array[Rect2] = []
		for r: Array in sequence.get("frames", []):
			frames.append(Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]))
		sequences.append(frames)
		clamped.append(bool(sequence.get("clamp", true)))
		var shown := PackedFloat32Array()
		for time: Variant in sequence.get("times", []):
			shown.append(float(time))
		times.append(shown if shown.size() == frames.size() else PackedFloat32Array())


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
