class_name ColourGrade
extends RefCounted

## CS2's colour grade on Godot's Environment: its filmic curve and its
## colour-correction table, from the map's post-processing file
## (MapPostProcessing), in place of the ACES and saturation MapLighting
## picked by eye. Behind a switch (mode) until Sid has judged it against the
## game (reference/playtest-2026-09-25.md, issue 10).
##
## Source 2 grades a frame in this order (Source 2 Viewer's reimplementation,
## post_processing.frag.slang; reference/research/cs2-post-processing.md):
## the scene times the exposure and 2 to the power of the file's bias; bloom;
## times 2.8 and clamped at 2.8 W; the Hable curve, divided by its value at
## 2.8 W; sRGB; the file's 32-cube table, sampled on its texel centres.
##
## Godot has no Hable curve, so the curve and the table go into one 3D
## texture that Godot's colour correction reads (adjustment_color_correction),
## on its LINEAR tone mapper, with the exposure scaled so the curve's white
## lands on 1. Godot 4.7.2's tonemap.glsl then takes the scene times the
## exposure, bloom, to sRGB, the contrast, clamps to 0 to 1 and samples the
## table there, with no texel-centre offset. The contrast, (N - 1) / N about
## the middle, puts 0 and 1 on the first and last texels' centres, so texel
## i holds the grade at i / (N - 1) exactly as CS2's own table is sampled.
## Every step after the clamp is the table's, and every step before it is
## Godot's own, so nothing here runs per frame.

## The mode MapLighting grades with unless told otherwise.
const DEFAULT_MODE := "aces"
const MODES: PackedStringArray = ["aces", "cs2"]
## The project setting that picks the mode; the command line's --grade
## overrides it.
const SETTING := "csgodot/rendering/colour_grade"

## Source 2's scale on the exposed scene before the curve
## (TonemapSettings.PreTonemapScale).
const PRE_CURVE_SCALE := 2.8
## The table's size. At 64, what Godot draws from it is within 1.2/255 of
## CS2's chain, with 2D in linear light (hdr_2d, as the project draws) or
## not (tests/run_grade_checks.gd); at 32, the default curve alone is 3/255
## off near black without hdr_2d. 64 cubed is a megabyte of video memory.
const TABLE_SIZE := 64

## Source 2 Viewer's middle grey, what auto exposure aims for.
const MIDDLE_GREY := 0.18


## The mode to grade with: --grade <mode> or --grade=<mode> among the
## command line's arguments, then the project setting, then DEFAULT_MODE.
static func mode(args: PackedStringArray = OS.get_cmdline_user_args()) -> String:
	for i in args.size():
		var wanted := ""
		if args[i] == "--grade" and i + 1 < args.size():
			wanted = args[i + 1]
		elif args[i].begins_with("--grade="):
			wanted = args[i].trim_prefix("--grade=")
		if wanted in MODES:
			return wanted
	var setting := String(ProjectSettings.get_setting(SETTING, DEFAULT_MODE))
	return setting if setting in MODES else DEFAULT_MODE


## The Hable curve (Uncharted 2's) at x, with the file's numbers.
static func hable(x: float, tonemap: Dictionary) -> float:
	var a := float(tonemap["m_flShoulderStrength"])
	var b := float(tonemap["m_flLinearStrength"])
	var c := float(tonemap["m_flLinearAngle"])
	var d := float(tonemap["m_flToeStrength"])
	var e := float(tonemap["m_flToeNum"])
	var f := float(tonemap["m_flToeDenom"])
	return (x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f) - e / f


## What Source 2 displays for an exposed scene value, in linear light from
## 0 to 1, before the sRGB step: the curve after the 2.8 scale, clamped at
## and divided by its white.
static func display(scene: float, tonemap: Dictionary) -> float:
	var white := float(tonemap["m_flWhitePoint"]) * PRE_CURVE_SCALE
	return hable(minf(maxf(scene, 0.0) * PRE_CURVE_SCALE, white), tonemap) / hable(white, tonemap)


## The exposed scene value Source 2 displays as middle grey (0.18 displayed),
## which its auto exposure aims the frame's average at
## (PostProcessRenderer.AutoAdjustExposure); NAN where the curve has none.
static func scene_for(displayed: float, tonemap: Dictionary) -> float:
	# Bisection: the curve rises from 0 to 1 over 0 to W.
	var low := 0.0
	var high := float(tonemap["m_flWhitePoint"])
	if displayed <= 0.0 or displayed >= 1.0:
		return NAN
	for i in 60:
		var middle := (low + high) * 0.5
		if display(middle, tonemap) < displayed:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## CS2's table sampled as its shader samples it, at a colour in sRGB from 0
## to 1: trilinear between texel centres, 0 and 1 on the first and last. An
## empty table is the identity.
static func sample_lut(lut: PackedByteArray, size: int, colour: Vector3) -> Vector3:
	if lut.is_empty() or size < 2:
		return colour.clamp(Vector3.ZERO, Vector3.ONE)
	var at := colour.clamp(Vector3.ZERO, Vector3.ONE) * float(size - 1)
	var low := Vector3i(mini(int(at.x), size - 2), mini(int(at.y), size - 2), mini(int(at.z), size - 2))
	var t := at - Vector3(low)
	var out := Vector3.ZERO
	for corner in 8:
		var dx := corner & 1
		var dy := (corner >> 1) & 1
		var dz := (corner >> 2) & 1
		var weight := (t.x if dx else 1.0 - t.x) * (t.y if dy else 1.0 - t.y) * (t.z if dz else 1.0 - t.z)
		if weight == 0.0:
			continue
		var index := (((low.z + dz) * size + (low.y + dy)) * size + (low.x + dx)) * 3
		out += Vector3(lut[index], lut[index + 1], lut[index + 2]) * weight
	return out / 255.0


## CS2's whole grade for one exposed scene colour (after the exposure and
## the bias): what it puts on screen, in sRGB from 0 to 1.
static func cs2_shows(scene: Vector3, post: MapPostProcessing) -> Vector3:
	var tonemap := post.tonemap
	var shown := Vector3(display(scene.x, tonemap), display(scene.y, tonemap), display(scene.z, tonemap))
	return sample_lut(post.lut, post.lut_size, Vector3(to_srgb(shown.x), to_srgb(shown.y), to_srgb(shown.z)))


## The table Godot samples: size cubed texels of 8-bit RGBA, texel i on each
## axis the grade of the sRGB value i / (size - 1) that Godot hands it (see
## the top of this file), for a scene exposed so the curve's white is 1.
## CS2's table is sampled as sample_lut samples it, one axis at a time
## (trilinear is three linear steps), which is several times quicker in
## GDScript than eight corners a texel: about 0.2 s for 64 cubed.
static func build_table(post: MapPostProcessing, size: int = TABLE_SIZE) -> Array[Image]:
	var white := float(post.tonemap["m_flWhitePoint"])
	var axis := PackedFloat32Array()
	axis.resize(size)
	for i in size:
		axis[i] = to_srgb(display(white * to_linear(float(i) / float(size - 1)), post.tonemap))
	var n := post.lut_size if not post.lut.is_empty() and post.lut_size >= 2 else 0
	# Where each of this table's texels falls in CS2's: the texel below and
	# how far towards the next.
	var below := PackedInt32Array()
	var toward := PackedFloat32Array()
	below.resize(size)
	toward.resize(size)
	for i in size:
		var at := clampf(axis[i], 0.0, 1.0) * float(maxi(n - 1, 1))
		below[i] = mini(int(at), maxi(n - 2, 0))
		toward[i] = at - float(below[i])
	# Along red: CS2's rows at this table's reds (n by n rows of size).
	var reds := PackedFloat32Array()
	if n > 0:
		reds.resize(n * n * size * 3)
		for row in n * n:
			for i in size:
				var from := (row * n + below[i]) * 3
				var t := toward[i]
				var to := (row * size + i) * 3
				for c in 3:
					reds[to + c] = lerpf(post.lut[from + c], post.lut[from + 3 + c], t) / 255.0
	# Along green: n slices of size by size.
	var greens := PackedFloat32Array()
	if n > 0:
		greens.resize(n * size * size * 3)
		for z in n:
			for j in size:
				var low := ((z * n + below[j]) * size) * 3
				var high := low + size * 3
				var t := toward[j]
				var to := ((z * size + j) * size) * 3
				for i3 in size * 3:
					greens[to + i3] = lerpf(reds[low + i3], reds[high + i3], t)
	var slices: Array[Image] = []
	var slice := PackedByteArray()
	slice.resize(size * size * 4)
	for k in size:
		var low := below[k] * size * size * 3
		var high := low + size * size * 3
		var t := toward[k]
		for j in size:
			for i in size:
				var at := (j * size + i) * 4
				if n == 0:
					slice[at] = clampi(roundi(axis[i] * 255.0), 0, 255)
					slice[at + 1] = clampi(roundi(axis[j] * 255.0), 0, 255)
					slice[at + 2] = clampi(roundi(axis[k] * 255.0), 0, 255)
				else:
					var from := (j * size + i) * 3
					for c in 3:
						slice[at + c] = clampi(roundi(lerpf(greens[low + from + c], greens[high + from + c], t) * 255.0), 0, 255)
				slice[at + 3] = 255
		slices.append(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, slice))
	return slices


## The table as the texture Godot's colour correction reads.
static func build_texture(post: MapPostProcessing, size: int = TABLE_SIZE) -> ImageTexture3D:
	var texture := ImageTexture3D.new()
	texture.create(Image.FORMAT_RGBA8, size, size, size, false, build_table(post, size))
	return texture


## The Environment's properties either grade sets, for a variant to put
## back (RenderVariants).
const PROPERTIES: PackedStringArray = [
	"tonemap_mode", "tonemap_exposure", "tonemap_white",
	"adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation",
	"adjustment_color_correction",
	"glow_enabled", "glow_intensity", "glow_strength", "glow_bloom", "glow_blend_mode",
	"glow_hdr_threshold", "glow_hdr_scale", "glow_normalized",
	"glow_levels/1", "glow_levels/2", "glow_levels/3", "glow_levels/4", "glow_levels/5",
	"glow_levels/6", "glow_levels/7",
]


## The Environment's values for CS2's grade: what apply sets. exposure is the
## scene's, before the file's bias (the middle of the map's exposure window,
## as MapLighting takes it).
static func settings(post: MapPostProcessing, exposure: float, texture: Texture3D) -> Dictionary:
	var white := float(post.tonemap["m_flWhitePoint"])
	var bias := pow(2.0, float(post.tonemap["m_flExposureBias"]))
	var size := texture.get_width() if texture != null else TABLE_SIZE
	var values := {
		"tonemap_mode": Environment.TONE_MAPPER_LINEAR,
		# The curve's white on 1, where Godot clamps before the table.
		"tonemap_exposure": exposure * bias / white,
		"tonemap_white": 1.0,
		"adjustment_enabled": true,
		"adjustment_brightness": 1.0,
		"adjustment_contrast": float(size - 1) / float(size),
		"adjustment_saturation": 1.0,
		"adjustment_color_correction": texture,
		"glow_enabled": post.has_bloom,
	}
	values.merge(bloom_settings(post, exposure), true)
	return values


## CS2's bloom in Godot's glow, as near as it goes (the research page lists
## what differs). CS2 fades a pixel in over the threshold's width of
## luminance times the exposure (no bias), blurs it five times at a half to
## a 32nd of the screen, weighs the five, and adds it, screens it over the
## graded frame, or mixes it in; Godot's glow fades in over the same span,
## times its own exposure, which here has the bias and 1 / W in it, and
## screens before the curve.
static func bloom_settings(post: MapPostProcessing, exposure: float) -> Dictionary:
	var bloom := post.bloom
	var white := float(post.tonemap["m_flWhitePoint"])
	var bias := pow(2.0, float(post.tonemap["m_flExposureBias"]))
	var mode := String(bloom["m_blendMode"])
	var strength := float(bloom["m_flBloomStrength"])
	var blend := Environment.GLOW_BLEND_MODE_ADDITIVE
	if mode == "BLOOM_BLEND_SCREEN":
		strength = float(bloom["m_flScreenBloomStrength"])
		blend = Environment.GLOW_BLEND_MODE_SCREEN
	elif mode == "BLOOM_BLEND_BLUR":
		strength = float(bloom["m_flBlurBloomStrength"])
		blend = Environment.GLOW_BLEND_MODE_MIX
	# Godot's threshold is on its exposed scene, which carries the bias and
	# 1 / W that CS2's threshold does not.
	var scale := bias / white
	var values := {
		"glow_intensity": strength,
		"glow_strength": 1.0,
		"glow_bloom": 0.0,
		"glow_blend_mode": blend,
		"glow_hdr_threshold": float(bloom["m_flBloomThreshold"]) * scale,
		"glow_hdr_scale": float(bloom["m_flBloomThresholdWidth"]) * scale,
		"glow_normalized": false,
	}
	# Godot's level n is drawn at 1 / 2^n of the screen, as CS2's blur n is.
	var weights: Array = bloom["m_flBlurWeight"]
	for level in range(1, 8):
		values["glow_levels/%d" % level] = float(weights[level - 1]) if level <= weights.size() else 0.0
	return values


## Grades an Environment MapLighting built with the named mode, from what
## it keeps on it: the ACES values it set, and the map's post-processing
## and exposure for CS2's, whose table is built the first time and kept.
static func use(environment: Environment, mode: String) -> void:
	apply(environment, values(environment, mode))
	environment.set_meta(&"grade", mode)


## The values the named mode sets on an Environment MapLighting built.
static func values(environment: Environment, mode: String) -> Dictionary:
	if mode != "cs2":
		return environment.get_meta(&"grade_aces", {})
	if not environment.has_meta(&"grade_cs2"):
		var post: MapPostProcessing = environment.get_meta(&"grade_post", null)
		if post == null:
			post = MapPostProcessing.load_file("")
		var exposure := float(environment.get_meta(&"grade_exposure", 1.0))
		environment.set_meta(&"grade_cs2", settings(post, exposure, build_texture(post)))
	return environment.get_meta(&"grade_cs2")


## Sets an Environment's grade from values (settings, or what a variant
## took from it).
static func apply(environment: Environment, values: Dictionary) -> void:
	for property: String in values:
		environment.set(property, values[property])


## An Environment's grade as it stands: its PROPERTIES.
static func current(environment: Environment) -> Dictionary:
	var values := {}
	for property in PROPERTIES:
		values[property] = environment.get(property)
	return values


static func to_srgb(x: float) -> float:
	x = maxf(x, 0.0)
	return 12.92 * x if x <= 0.0031308 else 1.055 * pow(x, 1.0 / 2.4) - 0.055


static func to_linear(x: float) -> float:
	return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)
