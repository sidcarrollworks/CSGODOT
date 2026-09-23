class_name MapOverview
extends RefCounted

## A map's radar as the game draws it: an overview image, 1024 pixels square,
## and a KeyValues text beside it (resource/overviews/<map>.txt) saying where
## the image lies over the map: the Source X and Y of its top-left corner
## (`pos_x`, `pos_y`) and how many units one pixel covers (`scale`).
## scripts/extract_assets.sh radar fetches both. Across the image is Source's
## +X, down it Source's -Y, as the HLTV overviews have always had it; the
## text also marks where the loading screen puts each spawn and bomb site,
## as fractions of the image, which the dust2 checks hold this to.

## The side of the overview image, in pixels, that `scale` is for.
const IMAGE_SIZE := 1024.0

## The image's top-left corner in Source's X and Y.
var top_left: Vector2
## Units of map to a pixel of the image.
var scale: float = 1.0
var zoom: float = 1.0
## What the text marks ("CTSpawn", "TSpawn", "bombA", "bombB"): where on the
## image, 0 to 1 across and down.
var markers: Dictionary = {}
## Every key the text has, as it wrote it.
var keys: Dictionary = {}
## Why the text could not be read; empty when it was.
var error: String = ""


static func load_file(path: String) -> MapOverview:
	if not FileAccess.file_exists(path):
		var missing := MapOverview.new()
		missing.error = "no overview at %s (scripts/extract_assets.sh radar)" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


## Reads the text: one block, named for the map, of quoted keys and values,
## with // comments.
static func parse(text: String) -> MapOverview:
	var overview := MapOverview.new()
	var tokens := RegEx.create_from_string('"([^"]*)"|([{}])').search_all(_without_comments(text))
	var depth := 0
	var key := ""
	for token in tokens:
		var brace := token.get_string(2)
		if brace == "{":
			depth += 1
			key = ""
		elif brace == "}":
			depth -= 1
		elif depth == 1:
			if key.is_empty():
				key = token.get_string(1)
			else:
				overview.keys[key] = token.get_string(1)
				key = ""
	if not (overview.keys.has("pos_x") and overview.keys.has("pos_y") and overview.keys.has("scale")):
		overview.error = "the overview gives no pos_x, pos_y and scale"
		return overview
	overview.top_left = Vector2(float(overview.keys["pos_x"]), float(overview.keys["pos_y"]))
	overview.scale = float(overview.keys["scale"])
	overview.zoom = float(overview.keys.get("zoom", "1"))
	for name: String in overview.keys:
		if name.ends_with("_x") and overview.keys.has(name.trim_suffix("_x") + "_y") and not name.begins_with("pos"):
			var marker := name.trim_suffix("_x")
			overview.markers[marker] = Vector2(float(overview.keys[name]), float(overview.keys[marker + "_y"]))
	return overview


## Where a point in game space falls on the image, 0 to 1 across and down
## (beyond that off its edges).
func to_image(point: Vector3) -> Vector2:
	# Game (x, y, z) is Source (y, z, x).
	return Vector2(point.z - top_left.x, top_left.y - point.x) / (scale * IMAGE_SIZE)


## The point in game space at a place on the image, at a height.
func to_game(on_image: Vector2, height: float) -> Vector3:
	var source := Vector2(top_left.x + on_image.x * scale * IMAGE_SIZE, top_left.y - on_image.y * scale * IMAGE_SIZE)
	return SourceEntities.to_game(Vector3(source.x, source.y, height))


static func _without_comments(text: String) -> String:
	var lines := PackedStringArray()
	for line in text.split("\n"):
		var cut := line.find("//")
		lines.append(line.substr(0, cut) if cut >= 0 else line)
	return "\n".join(lines)
