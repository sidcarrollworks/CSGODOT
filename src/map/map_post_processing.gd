class_name MapPostProcessing
extends RefCounted

## A map's post-processing file (a .vpost, which the map's
## post_processing_volume names), as CS2 grades the frame with it: the
## filmic curve's numbers, the bloom's, and the colour-correction table that
## every other layer is baked into. ColourGrade turns it into Godot's
## Environment.
##
## Read from Source 2 Viewer's text, in either of the two forms it writes:
## what `-d` decompiles a vpost_c to (CPostProcessData, its layers, and the
## table in a .raw file beside it, 8-bit RGB), or what `-b DATA` prints (the
## compiled resource's data block, the table inline as RGBA bytes).
## scripts/extract_assets.sh postprocessing takes the first. Where there is
## no file, the numbers are Source 2 Viewer's defaults (ScenePostProcessVolume.cs,
## TonemapSettings) with no bloom and no table, which is what its renderer
## draws a map without one with (reference/research/cs2-post-processing.md).
##
## Read once when the map loads, never during a tick.

## The filmic curve's numbers, by their names in the file, at Source 2
## Viewer's defaults. m_flExposureBias is in stops.
const DEFAULT_TONEMAP := {
	"m_flExposureBias": 0.0,
	"m_flShoulderStrength": 0.15,
	"m_flLinearStrength": 0.5,
	"m_flLinearAngle": 0.1,
	"m_flToeStrength": 0.2,
	"m_flToeNum": 0.02,
	"m_flToeDenom": 0.3,
	"m_flWhitePoint": 4.0,
}

## The bloom's numbers, at Source 2 Viewer's defaults (BloomSettings).
## m_flBlurWeight is one weight for each of five blurs, a half to a 32nd of
## the screen.
const DEFAULT_BLOOM := {
	"m_blendMode": "BLOOM_BLEND_ADD",
	"m_flBloomStrength": 1.0,
	"m_flScreenBloomStrength": 0.0,
	"m_flBlurBloomStrength": 0.0,
	"m_flBloomThreshold": 1.05,
	"m_flBloomThresholdWidth": 1.661,
	"m_flSkyboxBloomStrength": 1.0,
	"m_flBloomStartValue": 1.0,
	"m_flBlurWeight": [0.2, 0.2, 0.2, 0.2, 0.2],
}

## The file read, or "" for the defaults.
var source := ""
## Why the defaults are in use, or "".
var error := ""
## Whether the file has a curve of its own (otherwise the defaults are).
var has_tonemap := false
var tonemap := DEFAULT_TONEMAP.duplicate()
## Whether the file blooms at all; bloom holds its numbers either way.
var has_bloom := false
var bloom := DEFAULT_BLOOM.duplicate(true)
## The colour-correction table: lut_size cubed texels of 8-bit RGB, red
## changing fastest, then green, then blue; empty for none (the identity).
var lut := PackedByteArray()
var lut_size := 0
## Layers the file has that ColourGrade does not draw (a vignette, local
## contrast), by name.
var unused := PackedStringArray()


## Reads a map's post-processing from the file at path (Source 2 Viewer's
## text), or the defaults where there is none or it will not read.
static func load_file(path: String) -> MapPostProcessing:
	var post := MapPostProcessing.new()
	if path.is_empty() or not FileAccess.file_exists(path):
		post.error = "no post-processing file" if path.is_empty() else "%s is not there" % path
		return post
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = parse_text(text)
	if not parsed is Dictionary:
		post.error = "%s is not KV3 text" % path
		return post
	post.source = path
	post._read(parsed, path.get_base_dir())
	return post


## Source 2 Viewer's KV3 text, its header comment left out.
static func parse_text(text: String) -> Variant:
	var header := text.find("-->")
	if text.strip_edges().begins_with("<!--") and header >= 0:
		text = text.substr(header + 3)
	return NmGraph.parse_kv3(text)


## Takes the numbers from a parsed file; dir is where a .raw table it names
## is looked for.
func _read(data: Dictionary, dir: String) -> void:
	if data.has("m_layers"):
		_read_layers(data["m_layers"], dir)
	else:
		_read_data_block(data)
	if not lut.is_empty() and lut.size() != lut_size * lut_size * lut_size * 3:
		error = "the colour table has %d bytes, not %d cubed RGB" % [lut.size(), lut_size]
		lut = PackedByteArray()
		lut_size = 0


## What `-d` writes: CPostProcessData's layers.
func _read_layers(layers: Variant, dir: String) -> void:
	if not layers is Array:
		return
	for layer: Variant in layers:
		if not layer is Dictionary:
			continue
		var params: Dictionary = layer.get("m_params", {}) if layer.get("m_params") is Dictionary else {}
		match String(layer.get("_class", "")):
			"CToneMappingLayer":
				has_tonemap = true
				_take(tonemap, params)
			"CBloomLayer":
				has_bloom = true
				_take(bloom, params)
			"CColorLookupColorCorrectionLayer":
				lut_size = int(layer.get("m_nDim", 0))
				# The .raw beside the file first: the same bytes, without
				# reading them back from a hundred thousand numbers.
				var raw := dir.path_join(String(layer.get("m_fileName", "")).get_file())
				var values: Variant = layer.get("m_lut", [])
				if not raw.get_file().is_empty() and FileAccess.file_exists(raw):
					lut = FileAccess.get_file_as_bytes(raw)
				elif values is Array and not (values as Array).is_empty():
					lut = PackedByteArray()
					lut.resize((values as Array).size())
					for i in (values as Array).size():
						lut[i] = clampi(roundi(float(values[i]) * 255.0), 0, 255)
				else:
					error = "the colour table %s is not there" % raw
			var other:
				unused.append(other)


## What `-b DATA` prints: the compiled resource's own fields.
func _read_data_block(data: Dictionary) -> void:
	if bool(data.get("m_bHasTonemapParams", false)) and data.get("m_toneMapParams") is Dictionary:
		has_tonemap = true
		_take(tonemap, data["m_toneMapParams"])
	if bool(data.get("m_bHasBloomParams", false)) and data.get("m_bloomParams") is Dictionary:
		has_bloom = true
		_take(bloom, data["m_bloomParams"])
	if bool(data.get("m_bHasVignetteParams", false)):
		unused.append("vignette")
	if bool(data.get("m_bHasLocalContrastParams", false)):
		unused.append("local contrast")
	if bool(data.get("m_bHasLocalExposureParams", false)):
		unused.append("local exposure")
	if bool(data.get("m_bHasFogScatteringParams", false)):
		unused.append("fog scattering")
	# Files from before Aperture Desk Job have no flag, and always a table
	# (Source 2 Viewer's PostProcessing.HasColorCorrection).
	if bool(data.get("m_bHasColorCorrection", true)) and data.has("m_colorCorrectionVolumeData"):
		lut_size = int(data.get("m_nColorCorrectionVolumeDim", 0))
		var rgba := hex_bytes(String(data["m_colorCorrectionVolumeData"]))
		@warning_ignore("integer_division")
		var texels := rgba.size() / 4
		lut = PackedByteArray()
		lut.resize(texels * 3)
		for i in texels:
			lut[i * 3] = rgba[i * 4]
			lut[i * 3 + 1] = rgba[i * 4 + 1]
			lut[i * 3 + 2] = rgba[i * 4 + 2]


## The bytes of a KV3 binary blob, #[ 00 01 FF ... ].
static func hex_bytes(blob: String) -> PackedByteArray:
	var hex := blob.trim_prefix("#[").trim_suffix("]").replace(" ", "").replace("\n", "").replace("\r", "").replace("\t", "")
	return hex.hex_decode()


## Copies the numbers params has over the defaults in into, keeping the
## defaults' types.
static func _take(into: Dictionary, params: Dictionary) -> void:
	for key: String in into:
		if not params.has(key):
			continue
		var value: Variant = params[key]
		if into[key] is float:
			into[key] = float(value)
		elif into[key] is Array:
			if value is Array:
				into[key] = (value as Array).map(func(each: Variant) -> float: return float(each))
		else:
			into[key] = String(value)


## One line on what was read, for the load report.
func summary() -> String:
	var parts := PackedStringArray()
	parts.append(source.get_file() if not source.is_empty() else "Source 2 Viewer's defaults (%s)" % error)
	parts.append("curve W %.2f, bias %.2f stops" % [float(tonemap["m_flWhitePoint"]), float(tonemap["m_flExposureBias"])])
	parts.append("bloom %s" % (String(bloom["m_blendMode"]).trim_prefix("BLOOM_BLEND_").to_lower() if has_bloom else "none"))
	parts.append("table %d cubed" % lut_size if not lut.is_empty() else "no table")
	if not unused.is_empty():
		parts.append("not drawn: %s" % ", ".join(unused))
	return "; ".join(parts)
