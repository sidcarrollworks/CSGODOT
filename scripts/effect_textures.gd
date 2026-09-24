extends SceneTree

## Puts the effects' sprite sheets back together.
##
##   godot --headless --path . --script scripts/effect_textures.gd
##
## (scripts/extract_assets.sh effects runs this for you.)
##
## Source 2 Viewer writes a sprite sheet (the flames, the steam, the smoke) as
## one image a frame, each trimmed to what it draws, and the flames are
## sheets of 4096 by 2048 with 34 frames a sequence. Drawn one texture a
## frame they could not be batched, so each frame goes back where it was on
## its sheet: the texture's data block (Source 2 Viewer's -b DATA, in
## assets/effects/raw/textures_data.txt) gives every frame's rectangle, as
## CS2 draws it (uncropped) and as the trimmed image covers it (cropped).
## Out come assets/effects/<the texture's path>.png, the sheet whole, and
## beside it <name>.sheet.json with each sequence's frames, the rectangles
## a sprite is drawn with, and how long each shows (a frame can show for
## none: the steam's last), for SpriteSheet. A texture that is no sheet is
## copied across as it is.

const RAW_DIR := "res://assets/effects/raw"
const OUT_DIR := "res://assets/effects"


func _init() -> void:
	var data := FileAccess.get_file_as_string(RAW_DIR.path_join("textures_data.txt"))
	if data.is_empty():
		print("effect textures: no %s; run scripts/extract_assets.sh effects" % RAW_DIR.path_join("textures_data.txt"))
		quit(1)
		return
	var written := 0
	var failed := PackedStringArray()
	for texture: Dictionary in parse_data(data):
		var error := _write(texture)
		if error.is_empty():
			written += 1
		else:
			failed.append("%s: %s" % [texture["path"], error])
	print("effect textures: %d written" % written)
	for line in failed:
		print("  " + line)
	quit(0 if failed.is_empty() else 1)


## Every texture in a -b DATA dump: its path (materials/... .vtex), size, and
## its sheet's sequences, each {"clamp", "frames": [{"cropped", "uncropped",
## "time"}]} with the rectangles in UV as Rect2s (the first image of a frame;
## the smoke sheets' second is the same rectangle) and the frame's display
## time.
static func parse_data(text: String) -> Array[Dictionary]:
	var textures: Array[Dictionary] = []
	var texture := {}
	var sequence := {}
	var frame: Variant = null
	var header := RegEx.create_from_string("^\\[\\d+/\\d+\\] (\\S+)_c$")
	var rect := RegEx.create_from_string(
		"\\[\\d+\\.\\d+\\.0\\] (uvCropped|uvUncropped)\\s*=\\s*\\{ \\( ([-\\d.]+), ([-\\d.]+) \\), \\( ([-\\d.]+), ([-\\d.]+) \\) \\}"
	)
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		var found := header.search(line)
		if found != null:
			texture = {"path": found.get_string(1), "width": 0, "height": 0, "sequences": []}
			textures.append(texture)
			continue
		if texture.is_empty():
			continue
		if line.begins_with("Width "):
			texture["width"] = int(line.get_slice("=", 1))
		elif line.begins_with("Height "):
			texture["height"] = int(line.get_slice("=", 1))
		elif line.begins_with("[Sequence ") and not line.contains("Frame"):
			sequence = {"clamp": true, "frames": []}
			(texture["sequences"] as Array).append(sequence)
		elif line.begins_with("m_bClamp") and not sequence.is_empty():
			sequence["clamp"] = line.get_slice("=", 1).strip_edges() == "True"
		elif line.begins_with("[Sequence ") and line.contains("Frame"):
			frame = {"time": 1.0}
			(sequence["frames"] as Array).append(frame)
		elif line.begins_with("m_flDisplayTime") and frame != null:
			frame["time"] = line.get_slice("=", 1).strip_edges().to_float()
		else:
			found = rect.search(line)
			if found != null and frame != null:
				var from := Vector2(found.get_string(2).to_float(), found.get_string(3).to_float())
				var to := Vector2(found.get_string(4).to_float(), found.get_string(5).to_float())
				frame["cropped" if found.get_string(1) == "uvCropped" else "uncropped"] = Rect2(from, to - from)
	return textures


## Writes one texture: the sheet put back together, or the image copied.
## Returns what went wrong, or "".
static func _write(texture: Dictionary) -> String:
	var path: String = texture["path"]
	var base := RAW_DIR.path_join(path.get_basename())
	var out := OUT_DIR.path_join(path.get_basename())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var sequences: Array = texture["sequences"]
	if sequences.is_empty():
		var image := Image.load_from_file(ProjectSettings.globalize_path(base + ".png"))
		if image == null:
			return "no %s.png" % base
		return "" if image.save_png(ProjectSettings.globalize_path(out + ".png")) == OK else "could not write it"

	var size := Vector2(texture["width"], texture["height"])
	var sheet := Image.create_empty(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	var described := []
	for s in sequences.size():
		var frames: Array = sequences[s]["frames"]
		var rects := []
		var times := []
		for f in frames.size():
			var frame: Dictionary = frames[f]
			var cropped: Rect2 = frame.get("cropped", Rect2())
			var uncropped: Rect2 = frame.get("uncropped", Rect2())
			rects.append([uncropped.position.x, uncropped.position.y, uncropped.end.x, uncropped.end.y])
			times.append(frame.get("time", 1.0))
			# A frame with nothing in it (the flames' last, burnt out) is
			# written as no image at all.
			if not cropped.has_area():
				continue
			var file := "%s_seq%d_%d.png" % [base, s, f]
			if frames.size() == 1 and not FileAccess.file_exists(file):
				file = "%s_seq%d.png" % [base, s]
			var image := Image.load_from_file(ProjectSettings.globalize_path(file))
			if image == null:
				return "no %s" % file
			image.convert(Image.FORMAT_RGBA8)
			# Trimmed to its cropped rectangle, or (a sheet of one-frame
			# sequences) the whole uncropped one: whichever it is the size of.
			var at := cropped
			if absf(image.get_width() - uncropped.size.x * size.x) < absf(image.get_width() - cropped.size.x * size.x):
				at = uncropped
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i((at.position * size).round()))
		described.append({"clamp": sequences[s]["clamp"], "frames": rects, "times": times})
	if sheet.save_png(ProjectSettings.globalize_path(out + ".png")) != OK:
		return "could not write it"
	var json := FileAccess.open(out + ".sheet.json", FileAccess.WRITE)
	if json == null:
		return "could not write its sheet"
	json.store_string(JSON.stringify({"width": size.x, "height": size.y, "sequences": described}))
	return ""
