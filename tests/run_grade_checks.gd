extends "res://tests/check_suite.gd"

## CS2's colour grade (ColourGrade) and the map's post-processing file it is
## read from (MapPostProcessing): the Hable curve against hand values; the
## table Godot is handed, sampled here the way Godot 4.7.2's tonemap.glsl
## samples it, against CS2's chain worked through directly; the reader, on
## small made-up files in both of Source 2 Viewer's forms (no Valve data is
## committed); and the Environment MapLighting builds in each mode, the
## default unchanged. Whether the grade looks like CS2 needs dust2's own file
## and a GPU: that is Sid's (reference/playtest-2026-09-25.md, issue 10).

const SCRATCH := "user://grade_checks"

## Colours in CS2's exposed scene (after the exposure and the bias): long
## doors' sunlit ground and shade as the playtest measured them, a saturated
## sky, a lamp's warm glow, and past the white point.
const COLOURS: Array[Vector3] = [
	Vector3(0.52, 0.41, 0.33), Vector3(0.05, 0.08, 0.11), Vector3(0.3, 0.6, 1.4),
	Vector3(2.5, 1.2, 0.3), Vector3(0.002, 0.004, 0.001), Vector3(6.0, 5.0, 4.5),
]


func _initialize() -> void:
	_check_curve()
	_check_table(MapPostProcessing.load_file(""), "the defaults")
	_check_table(_warm(), "a warm table and a curve of the file's own")
	_check_reader()
	_check_environment()
	_check_mode()
	_finish("grade")


func _check_curve() -> void:
	var tonemap := MapPostProcessing.DEFAULT_TONEMAP
	_check_near(ColourGrade.hable(0.0, tonemap), 0.0, "the curve starts at 0")
	# (1 (0.15 + 0.1 x 0.5) + 0.2 x 0.02) / (1 (0.15 + 0.5) + 0.2 x 0.3) - 0.02 / 0.3
	_check(absf(ColourGrade.hable(1.0, tonemap) - (0.204 / 0.71 - 0.02 / 0.3)) < 1e-6, "the curve at 1, worked by hand")
	var white := 4.0 * ColourGrade.PRE_CURVE_SCALE
	var at_white := (white * (0.15 * white + 0.05) + 0.004) / (white * (0.15 * white + 0.5) + 0.06) - 0.02 / 0.3
	_check(absf(ColourGrade.hable(white, tonemap) - at_white) < 1e-6, "and at the white point, 2.8 W")
	_check(absf(ColourGrade.display(1.0, tonemap) - ColourGrade.hable(2.8, tonemap) / at_white) < 1e-6,
		"a scene value is scaled by 2.8 before the curve, and the curve divided by its white")
	_check_near(ColourGrade.display(4.0, tonemap), 1.0, "the white point displays as 1")
	_check_near(ColourGrade.display(40.0, tonemap), 1.0, "and anything past it")
	var grey := ColourGrade.scene_for(ColourGrade.MIDDLE_GREY, tonemap)
	_check(absf(ColourGrade.display(grey, tonemap) - ColourGrade.MIDDLE_GREY) < 1e-5, "the scene value middle grey comes from is found")
	var previous := -1.0
	var rising := true
	for i in 101:
		var shown := ColourGrade.display(float(i) * 0.04, tonemap)
		rising = rising and shown > previous
		previous = shown
	_check(rising, "the curve rises all the way to its white")


## A table and a curve unlike the defaults, as a map's file might have them:
## 32 cubed, the reds lifted, the blues cut and lifted off black.
func _warm() -> MapPostProcessing:
	var post := MapPostProcessing.new()
	post.tonemap = MapPostProcessing.DEFAULT_TONEMAP.duplicate()
	post.tonemap["m_flShoulderStrength"] = 0.22
	post.tonemap["m_flWhitePoint"] = 3.0
	post.tonemap["m_flExposureBias"] = 0.4
	post.lut_size = 32
	post.lut.resize(32 * 32 * 32 * 3)
	for k in 32:
		for j in 32:
			for i in 32:
				var at := ((k * 32 + j) * 32 + i) * 3
				post.lut[at] = roundi(pow(i / 31.0, 0.85) * 255.0)
				post.lut[at + 1] = roundi(j / 31.0 * 255.0)
				post.lut[at + 2] = roundi((0.05 + 0.8 * k / 31.0) * 255.0)
	return post


## The table built for post, sampled as Godot samples it, against CS2's
## chain, with 2D in linear light (the project's hdr_2d, the texture read
## through an sRGB view) and without.
func _check_table(post: MapPostProcessing, what: String) -> void:
	var started := Time.get_ticks_msec()
	# The images themselves: headless, a texture keeps no copy to read back.
	var slices := ColourGrade.build_table(post)
	print("  the %d-cubed table for %s built in %d ms" % [ColourGrade.TABLE_SIZE, what, Time.get_ticks_msec() - started])
	var texture := ImageTexture3D.new()
	texture.create(Image.FORMAT_RGBA8, slices.size(), slices.size(), slices.size(), false, slices)
	var values := ColourGrade.settings(post, 1.0, texture)
	_check_equal(slices.size(), ColourGrade.TABLE_SIZE, "%s: the table is %d cubed" % [what, ColourGrade.TABLE_SIZE])
	_check_equal(texture.get_width(), ColourGrade.TABLE_SIZE, "%s: and so is its texture" % what)
	var white := float(post.tonemap["m_flWhitePoint"])
	var bias := pow(2.0, float(post.tonemap["m_flExposureBias"]))
	var scenes: Array[Vector3] = []
	for i in 241:
		var grey := float(i) / 200.0 * white
		scenes.append(Vector3(grey, grey, grey))
	scenes.append_array(COLOURS)
	for linear_light in [true, false]:
		var worst := 0.0
		var worst_at := Vector3.ZERO
		for scene in scenes:
			# Godot's exposure takes the scene to CS2's exposed one over W; a
			# scene of 1 in CS2 is then this before the grade.
			var godot := scene / bias * float(values["tonemap_exposure"])
			var shown := _godot_shows(godot, slices, float(values["adjustment_contrast"]), linear_light)
			var wanted := ColourGrade.cs2_shows(scene, post)
			var off := maxf(absf(shown.x - wanted.x), maxf(absf(shown.y - wanted.y), absf(shown.z - wanted.z))) * 255.0
			if off > worst:
				worst = off
				worst_at = scene
		print("  %s, %s: worst %.2f/255 at %s" % [what, "hdr_2d" if linear_light else "sRGB 2D", worst, worst_at])
		_check(worst <= 2.0, "%s: Godot's grade is within 2/255 of CS2's %s (worst %.2f)" % [
			what, "in linear light" if linear_light else "in sRGB", worst])


## What Godot 4.7.2 puts on screen for a colour after its exposure, on the
## LINEAR tone mapper with the table (tonemap.glsl): brightness 1, to sRGB,
## the contrast about 0.5, saturation 1, clamped, then the table sampled at
## that colour with no texel-centre offset, trilinear, clamped at its edges.
## With linear_light each texel is read through an sRGB view (hdr_2d), so it
## is blended in linear light and the result encoded again for the screen.
func _godot_shows(colour: Vector3, slices: Array[Image], contrast: float, linear_light: bool) -> Vector3:
	var size := slices.size()
	var u := Vector3.ZERO
	for axis in 3:
		var value := ColourGrade.to_srgb(colour[axis])
		u[axis] = clampf(0.5 + (value - 0.5) * contrast, 0.0, 1.0)
	var at := (u * float(size) - Vector3.ONE * 0.5).clamp(Vector3.ZERO, Vector3.ONE * float(size - 1))
	var low := Vector3i(mini(int(at.x), size - 2), mini(int(at.y), size - 2), mini(int(at.z), size - 2))
	var t := at - Vector3(low)
	var out := Vector3.ZERO
	for corner in 8:
		var dx := corner & 1
		var dy := (corner >> 1) & 1
		var dz := (corner >> 2) & 1
		var weight := (t.x if dx else 1.0 - t.x) * (t.y if dy else 1.0 - t.y) * (t.z if dz else 1.0 - t.z)
		var texel := slices[low.z + dz].get_pixel(low.x + dx, low.y + dy)
		var value := Vector3(texel.r, texel.g, texel.b)
		if linear_light:
			value = Vector3(ColourGrade.to_linear(value.x), ColourGrade.to_linear(value.y), ColourGrade.to_linear(value.z))
		out += value * weight
	if linear_light:
		out = Vector3(ColourGrade.to_srgb(out.x), ColourGrade.to_srgb(out.y), ColourGrade.to_srgb(out.z))
	return out


const HEADER := "<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:generic:version{7412167c-06e9-4698-aff2-e63eb59037e7} -->\n"

## What Source 2 Viewer's -d writes for a vpost, cut down: a curve, a
## screen bloom, a table two texels a side (red, green, blue, then white
## for the rest), in the file itself or in a .raw beside it.
func _decompiled(lut_inline: bool) -> String:
	var lut := "[ 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 ]" if lut_inline else "[  ]"
	return HEADER + """{
	_class = "CPostProcessData"
	m_layers =
	[
		{
			_class = "CToneMappingLayer"
			m_name = "Tone Mapping"
			m_nOpacityPercent = 100
			m_bVisible = true
			m_pLayerMask = null
			m_params =
			{
				m_flExposureBias = 0.4192
				m_flShoulderStrength = 0.1476
				m_flLinearStrength = 0.5
				m_flLinearAngle = 0.1
				m_flToeStrength = 0.2
				m_flToeNum = 0.02
				m_flToeDenom = 0.3
				m_flWhitePoint = 3.9996
			}
		},
		{
			_class = "CBloomLayer"
			m_name = "Bloom"
			m_nOpacityPercent = 100
			m_bVisible = true
			m_pLayerMask = null
			m_params =
			{
				m_blendMode = "BLOOM_BLEND_SCREEN"
				m_flBloomStrength = 0.0
				m_flScreenBloomStrength = 0.5
				m_flBlurBloomStrength = 0.0
				m_flBloomThreshold = 1.021
				m_flBloomThresholdWidth = 4.543
				m_flSkyboxBloomStrength = 1.0
				m_flBloomStartValue = 1.0
				m_flBlurWeight = [ 0.303444, 0.097861, 0.084843, 0.233257, 0.280595 ]
				m_vBlurTint = [ [ 1.0, 1.0, 1.0 ], [ 1.0, 1.0, 1.0 ], [ 1.0, 1.0, 1.0 ], [ 1.0, 1.0, 1.0 ], [ 1.0, 1.0, 1.0 ] ]
			}
		},
		{
			_class = "CColorLookupColorCorrectionLayer"
			m_name = "VRF Extracted Lookup Table"
			m_nOpacityPercent = 100
			m_bVisible = true
			m_pLayerMask = null
			m_fileName = "lighting/postprocessing/test/%s"
			m_lut = %s
			m_nDim = 2
		},
	]
}
""" % ["never_written.raw" if lut_inline else "test.raw", lut]


## What -b DATA prints for the same, the table inline as RGBA bytes.
const DATA_BLOCK := HEADER + """{
	m_bHasTonemapParams = true
	m_toneMapParams =
	{
		m_flExposureBias = 0.4192
		m_flShoulderStrength = 0.1476
		m_flLinearStrength = 0.5
		m_flLinearAngle = 0.1
		m_flToeStrength = 0.2
		m_flToeNum = 0.02
		m_flToeDenom = 0.3
		m_flWhitePoint = 3.9996
	}
	m_bHasBloomParams = false
	m_bHasVignetteParams = true
	m_nColorCorrectionVolumeDim = 2
	m_colorCorrectionVolumeData =
	#[
		FF 00 00 FF 00 FF 00 FF 00 00 FF FF FF FF FF FF FF FF FF FF FF FF FF FF
		FF FF FF FF FF FF FF FF
	]
}
"""

const TABLE := [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]


func _write(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _check_reader() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var defaults := MapPostProcessing.load_file("")
	_check(not defaults.error.is_empty() and defaults.source.is_empty(), "no file: the defaults, and the report says why")
	_check_equal(defaults.tonemap, MapPostProcessing.DEFAULT_TONEMAP, "no file: Source 2 Viewer's curve")
	_check(not defaults.has_bloom and defaults.lut.is_empty(), "no file: no bloom and no table")
	_check(not MapPostProcessing.load_file(SCRATCH.path_join("missing.vpost")).error.is_empty(), "a file that is not there is said so")

	var inline := MapPostProcessing.load_file(_write(SCRATCH.path_join("inline.vpost"), _decompiled(true)))
	_check(inline.error.is_empty() and inline.has_tonemap, "the decompiled form reads")
	_check_near(inline.tonemap["m_flShoulderStrength"], 0.1476, "its shoulder")
	_check_near(inline.tonemap["m_flWhitePoint"], 3.9996, "its white point")
	_check_near(inline.tonemap["m_flExposureBias"], 0.4192, "its bias")
	_check(inline.has_bloom and inline.bloom["m_blendMode"] == "BLOOM_BLEND_SCREEN", "its bloom, screened")
	_check_near(inline.bloom["m_flScreenBloomStrength"], 0.5, "its bloom's strength")
	_check_near((inline.bloom["m_flBlurWeight"] as Array)[3], 0.233257, "its blurs' weights")
	_check_equal(inline.lut_size, 2, "its table's size")
	_check_equal(Array(inline.lut), TABLE, "its table, from the file's own numbers")

	var raw := FileAccess.open(SCRATCH.path_join("test.raw"), FileAccess.WRITE)
	raw.store_buffer(PackedByteArray(TABLE))
	raw.close()
	var beside := MapPostProcessing.load_file(_write(SCRATCH.path_join("beside.vpost"), _decompiled(false)))
	_check(beside.error.is_empty(), "the decompiled form with its table in a .raw beside it reads")
	_check_equal(Array(beside.lut), TABLE, "the table from the .raw")

	var data := MapPostProcessing.load_file(_write(SCRATCH.path_join("data.txt"), DATA_BLOCK))
	_check(data.error.is_empty() and data.has_tonemap and not data.has_bloom, "the data block's form reads, its bloom off")
	_check_near(data.tonemap["m_flShoulderStrength"], 0.1476, "its shoulder")
	_check_equal(Array(data.lut), TABLE, "its table, alpha left out")
	_check(data.unused.has("vignette"), "a vignette it does not draw is said so")
	_check(data.summary().contains("not drawn: vignette"), "in the report too")

	var wrong := MapPostProcessing.load_file(_write(SCRATCH.path_join("wrong.vpost"), _decompiled(true).replace("m_nDim = 2", "m_nDim = 3")))
	_check(not wrong.error.is_empty() and wrong.lut.is_empty(), "a table the wrong size is left out, and said so")
	_check(not MapPostProcessing.load_file(_write(SCRATCH.path_join("junk.vpost"), "not kv3")).error.is_empty(), "text that is not KV3 is said so")

	var entities: Array[Dictionary] = [
		{"classname": "post_processing_volume", "postprocessing": "lighting/postprocessing/local.vpost"},
		{"classname": "post_processing_volume", "master": "1", "postprocessing": "lighting/postprocessing/de_dust2_prefab/de_dust2_prefab.vpost"},
	]
	_check_equal(MapLighting.post_processing_file(entities, "res://assets/maps/de_dust2"),
		"res://assets/maps/de_dust2/lighting/postprocessing/de_dust2_prefab/de_dust2_prefab.vpost",
		"the map's file is the master volume's, under the map's directory")
	_check_equal(MapLighting.post_processing_file([] as Array[Dictionary], "res://x"), "", "no volume, no file")
	_check_near(MapLighting.cs2_exposure({}), 1.0, "no volume: CS2's exposure is 1")
	_check_near(MapLighting.cs2_exposure({"minexposure": "0.925", "maxexposure": "1.1"}), 1.0125, "the middle of the window")
	_check_near(MapLighting.cs2_exposure({"minexposure": "0.925", "maxexposure": "1.1", "enableexposure": "0"}), 1.0,
		"1 where the volume's exposure control is off")
	_check_near(MapLighting.cs2_exposure({"minexposure": "1", "maxexposure": "1", "exposurecompensation": "1"}), 2.0,
		"times 2 to the power of the compensation")


## MapLighting's Environment in each mode: the default unchanged, CS2's on
## the linear tone mapper with the table, and each put back by the other.
func _check_environment() -> void:
	var entities: Array[Dictionary] = [
		{"classname": "light_environment", "brightness": "2.5"},
		{"classname": "post_processing_volume", "minexposure": "0.925", "maxexposure": "1.1"},
	]
	var post := MapPostProcessing.load_file(_write(SCRATCH.path_join("map.vpost"), _decompiled(true)))
	var aces_holder := Node3D.new()
	var cs2_holder := Node3D.new()
	root.add_child(aces_holder)
	root.add_child(cs2_holder)
	var aces_used := MapLighting.build(aces_holder, {}, entities, "", null, false, post, "aces")
	var cs2_used := MapLighting.build(cs2_holder, {}, entities, "", null, false, post, "cs2")
	var aces := (aces_holder.get_node("Atmosphere") as WorldEnvironment).environment
	var cs2 := (cs2_holder.get_node("Atmosphere") as WorldEnvironment).environment
	var exposure := (0.925 + 1.1) * 0.5

	_check_equal(aces_used["grade"], "aces", "the report names the grade")
	_check(
		aces.tonemap_mode == Environment.TONE_MAPPER_ACES and is_equal_approx(aces.tonemap_exposure, exposure)
			and is_equal_approx(aces.adjustment_saturation, 1.15) and aces.adjustment_color_correction == null
			and aces.glow_enabled and is_equal_approx(aces.glow_intensity, 0.4),
		"ACES as it was: the window's middle, saturation 1.15, glow 0.4, no table"
	)
	_check_equal(cs2_used["grade"], "cs2", "CS2's grade when asked for")
	_check(cs2.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "CS2's: the linear tone mapper, the curve being in the table")
	_check_near(cs2.tonemap_exposure * 1000.0, exposure * pow(2.0, 0.4192) / 3.9996 * 1000.0,
		"its exposure: the window's middle, the file's bias, over the white point")
	_check(cs2.adjustment_color_correction is ImageTexture3D, "its table is the colour correction")
	_check(is_equal_approx(cs2.adjustment_saturation, 1.0) and is_equal_approx(cs2.adjustment_brightness, 1.0),
		"no saturation or brightness of Godot's own")
	_check_near(cs2.adjustment_contrast, float(ColourGrade.TABLE_SIZE - 1) / ColourGrade.TABLE_SIZE,
		"the contrast that puts 0 and 1 on the table's first and last texels")
	_check(cs2.glow_enabled and cs2.glow_blend_mode == Environment.GLOW_BLEND_MODE_SCREEN
		and is_equal_approx(cs2.glow_intensity, 0.5) and not cs2.glow_normalized,
		"the file's bloom: screened at its strength")
	_check_near(cs2.glow_hdr_threshold * 1000.0, 1.021 * pow(2.0, 0.4192) / 3.9996 * 1000.0, "at its threshold, in Godot's exposed scene")
	_check_near(cs2.get("glow_levels/4"), 0.233257, "each blur weighed as the file weighs it")
	_check_near(cs2.get("glow_levels/6"), 0.0, "and none past CS2's fifth")
	_check_equal(cs2.fog_enabled, aces.fog_enabled, "the fog is the same in both")
	_check(cs2_used["post_processing"].contains("map.vpost"), "the report names the file")

	ColourGrade.use(cs2, "aces")
	_check_equal(ColourGrade.current(cs2), ColourGrade.current(aces), "CS2's grade swapped for ACES is ACES as built")
	ColourGrade.use(aces, "cs2")
	_check_equal(aces.tonemap_mode, Environment.TONE_MAPPER_LINEAR, "and the other way")
	aces_holder.free()
	cs2_holder.free()


func _check_mode() -> void:
	_check_equal(ProjectSettings.get_setting(ColourGrade.SETTING), "aces", "the switch is off in project.godot")
	_check_equal(ColourGrade.mode(PackedStringArray()), "aces", "so ACES is the grade unless asked")
	_check_equal(ColourGrade.mode(PackedStringArray(["--grade", "cs2"])), "cs2", "--grade cs2 asks for CS2's")
	_check_equal(ColourGrade.mode(PackedStringArray(["--map", "de_dust2", "--grade=cs2"])), "cs2", "--grade=cs2 too")
	_check_equal(ColourGrade.mode(PackedStringArray(["--grade", "sepia"])), "aces", "a grade there is not is passed over")
