extends "res://tests/check_suite.gd"

## CPU interpolation/batch contracts always run. Real pixel checks exercise
## current/next atlas rectangles, colour lookup, coverage and motion on a GPU.

const TEXTURE := "materials/test/hit_quad.vtex"
const MOTION := "materials/test/hit_quad_mv.vtex"
const SIZE := 128
var _quads: HitQuads
var _viewport: SubViewport


func _initialize() -> void:
	_test_frames()
	call_deferred(&"_run")


func _test_frames() -> void:
	var sheet := SpriteSheet.new()
	sheet.read({"sequences": [
		{"clamp": true, "frames": [[0,0,0.25,1], [0.25,0,0.5,1], [0.5,0,0.75,1]], "times": [1,3,0]},
		{"clamp": false, "frames": [[0,0,0.5,0.5], [0.5,0.5,1,1]]},
	]})
	_check(sheet.interpolation_data(0, 0.125).is_equal_approx(Vector3(0,1,0.5)), "the first frame interpolates by its own display time")
	_check(sheet.interpolation_data(0, 0.625).is_equal_approx(Vector3(1,2,0.5)), "a longer second frame uses its own time and blends into a zero-duration final frame")
	_check_equal(sheet.interpolation_data(0, 1.0), Vector3(2,2,0), "the clamped endpoint holds the zero-duration final frame")
	_check_equal(sheet.interpolation_data(0, -1.0), Vector3(0,1,0), "negative time on a clamped sheet holds its first frame")
	_check(sheet.interpolation_data(1, 0.75).is_equal_approx(Vector3(4,3,0.5)), "flat frame indices include prior sequences and loop back to the first")
	_check(sheet.interpolation_data(1, -0.25).is_equal_approx(Vector3(4,3,0.5)), "looping animation also wraps negative fractions")
	_check_equal(sheet.interpolation_data(3, 0.75), sheet.interpolation_data(1, 0.75), "sequence IDs wrap as the existing frame method does")
	_check_equal(sheet.frame(0, 0.625), Rect2(0.25,0,0.25,1), "the existing frame method keeps its discrete rectangle contract")
	var metadata := sheet.frame_metadata()
	_check(metadata == sheet.frame_metadata() and metadata.get_width() == 5 and metadata.get_height() == 1, "frame metadata is one cached floating-point texel per atlas rectangle")
	var data := metadata.get_image()
	_check(data.get_format() == Image.FORMAT_RGBAF
		and data.get_pixel(4,0).is_equal_approx(Color(0.5,0.5,1,1)), "metadata stores exact UV corners without sRGB conversion")
	sheet.read({"sequences": [{"clamp": true, "frames": [[0.1,0.2,0.8,0.9]]}]})
	_check(sheet.frame_metadata() != metadata and sheet.frame_metadata().get_width() == 1, "reading new metadata invalidates the old lookup texture")
	var plain := SpriteSheet.new()
	_check_equal(plain.interpolation_data(99, 0.9), Vector3.ZERO, "a plain texture uses its single frame")
	_check(plain.frame_metadata().get_image().get_pixel(0,0).is_equal_approx(Color(0,0,1,1)), "a plain texture's lookup spans its whole image")
	var zero := SpriteSheet.new()
	zero.read({"sequences":[{"frames":[[0,0,0.5,1],[0.5,0,1,1]], "times":[0,0]}]})
	_check_equal(zero.interpolation_data(0, 0.5), Vector3(1,1,0), "an all-zero timeline holds its final frame without division by zero")
	var static_sheet := SpriteSheet.new()
	var static_sequences := []
	for sequence in 5:
		static_sequences.append({"frames":[[sequence * 0.1,0,sequence * 0.1 + 0.05,1]]})
	static_sheet.read({"sequences":static_sequences})
	var flow_sheet := SpriteSheet.new()
	var flow_sequences := []
	for sequence in 3:
		flow_sequences.append({"frames":[[0,sequence * 0.25,0.5,sequence * 0.25 + 0.2],[0.5,sequence * 0.25,1,sequence * 0.25 + 0.2]]})
	flow_sheet.read({"sequences":flow_sequences})
	var paired := HitQuads._static_overlay(static_sheet, flow_sheet)
	_check_equal(paired[0].sequences.size(), 15, "five static-smoke choices and three flow choices retain independent sequence wrapping")
	_check(paired[0].frame(8, 0.25).is_equal_approx(static_sheet.frame(8,0.25))
		and paired[1].frame(8,0.25).is_equal_approx(flow_sheet.frame(8,0.25)), "the common timeline looks up each texture's authored sequence")
	_check(paired[0].interpolation_data(8,0.25).is_equal_approx(Vector3(16,17,0.5)), "a static colour frame still carries the animated motion frame's interpolation")


func _run() -> void:
	var image := Image.create_empty(64,32,false,Image.FORMAT_RGBA8)
	image.fill(Color.BLUE)
	image.fill_rect(Rect2i(0,0,32,32), Color.RED)
	var sheet := SpriteSheet.new()
	sheet.texture = ImageTexture.create_from_image(image)
	sheet.read({"sequences":[{"clamp":true,"frames":[[0,0,0.5,1],[0.5,0,1,1]]}]})
	SpriteSheet._loaded[TEXTURE] = sheet
	var renderer := {"tex":TEXTURE,"blend":"alpha"}
	_quads = HitQuads.new()
	root.add_child(_quads)
	_quads.prepare(renderer)
	_quads.prepare(renderer.duplicate(true))
	_check_equal(_quads.get_child_count(), 1, "equivalent prepared renderers share one MultiMesh batch")
	_quads.begin()
	var xform := Transform3D(Basis(Vector3(2,0,0),Vector3(0,3,0),Vector3.BACK),Vector3(5,6,-10))
	_quads.card(renderer, xform, 0, 0.25, Color(0.1,0.2,0.3,0.4), 0.6)
	_quads.finish()
	_check_equal(_quads.cards(), 1, "a card is counted once in its prepared batch")
	var batch: HitQuads.Batch = _quads._batches.values()[0]
	_check(batch.data.size() == HitQuads.FIRST_CAPACITY * HitQuads.FLOATS and batch.mesh.visible_instance_count == 1,
		"the batch uploads a complete buffer and draws only populated cards")
	_check(batch.data.slice(16,20) == PackedFloat32Array([0,1,0.5,0.6]), "instance custom data carries current/next frames, their blend and per-particle coverage")
	_check(batch.data.slice(0,12) == PackedFloat32Array([2,0,0,5,0,3,0,6,0,0,1,-10]), "card transforms use the documented row-major MultiMesh buffer layout")
	_quads.begin()
	_quads.finish()
	_check(_quads.cards() == 0 and not batch.node.visible and batch.mesh.visible_instance_count == 0, "an empty next frame hides the batch and leaves no stale cards")
	_quads.card({"tex":"not_prepared.vtex"}, Transform3D.IDENTITY, 0, 0, Color.WHITE)
	_check_equal(_quads.cards(), 0, "a shot cannot read an unprepared renderer from disk")
	_quads.free()
	if DisplayServer.get_name() != "headless":
		await _test_pixels(sheet, renderer)
	else:
		print("hit_quads: GPU pixel checks skip headless")
	SpriteSheet._loaded.erase(TEXTURE)
	SpriteSheet._loaded.erase(MOTION)
	_finish("hit_quads")


func _test_pixels(sheet: SpriteSheet, renderer: Dictionary) -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE,SIZE)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.current = true
	_viewport.add_child(camera)
	_quads = HitQuads.new()
	_viewport.add_child(_quads)
	_quads.prepare(renderer)
	var midpoint: Color = await _draw(renderer, 0.25)
	_check(midpoint.r > 0.3 and midpoint.b > 0.3 and absf(midpoint.r - midpoint.b) < 0.03 and midpoint.g < 0.02,
		"GPU interpolates two differently placed atlas frames without sampling their border")
	var held: Color = await _draw(renderer, 2.0)
	_check(held.b > 0.95 and held.r < 0.02, "GPU holds a clamped sheet's final frame")
	var alpha_image := Image.create_empty(64,32,false,Image.FORMAT_RGBA8)
	alpha_image.fill(Color(1,1,1,0.4))
	(sheet.texture as ImageTexture).update(alpha_image)
	var clear: Color = await _draw(renderer, 0.0, 0.5)
	_check(clear.r < 0.02 and clear.g < 0.02 and clear.b < 0.02, "GPU coverage removes texels below a per-particle threshold")
	var covered: Color = await _draw(renderer, 0.0, 0.2)
	_check(covered.r > 0.2 and covered.r < 0.65, "GPU coverage remaps surviving alpha continuously")
	var gradient_renderer := {"tex":TEXTURE,"blend":"alpha","gradient":[[0.0,[0,255,0]],[1.0,[0,255,0]]], "gradient_blend":"SPRITECARD_TEXTURE_BLEND_REPLACE"}
	_quads.prepare(gradient_renderer)
	alpha_image.fill(Color.WHITE)
	(sheet.texture as ImageTexture).update(alpha_image)
	var green: Color = await _draw(gradient_renderer, 0.0)
	_check(green.g > 0.95 and green.r < 0.02 and green.b < 0.02, "GPU applies the authored gradient ramp to sprite intensity")
	alpha_image.fill(Color(0.5,0.5,0.5,0.5))
	(sheet.texture as ImageTexture).update(alpha_image)
	var multiply_gradient := gradient_renderer.duplicate(true)
	multiply_gradient.gradient_blend = "SPRITECARD_TEXTURE_BLEND_MULTIPLY"
	_quads.prepare(multiply_gradient)
	var replaced: Color = await _draw(gradient_renderer, 0.0)
	var tinted: Color = await _draw(multiply_gradient, 0.0)
	_check(replaced.g > tinted.g * 2.0 and tinted.g > 0.05, "GPU gradient REPLACE retains ramp colour while MULTIPLY tints input RGB and its alpha")
	var lookup := {"tex":TEXTURE, "gradient":[[0.0,[0,0,0]],[1.0,[255,255,255]]], "gradient_blend":"SPRITECARD_TEXTURE_BLEND_REPLACE", "gradient_channels":"SPRITECARD_TEXTURE_CHANNEL_MIX_RGB"}
	_quads.prepare(lookup)
	var rgb_lookup: Color = await _draw(lookup, 0.0)
	var premul_lookup := lookup.duplicate(true)
	premul_lookup.gradient_channels = "SPRITECARD_TEXTURE_CHANNEL_MIX_RGBA"
	_quads.prepare(premul_lookup)
	var rgba_lookup: Color = await _draw(premul_lookup, 0.0)
	_check(rgb_lookup.r > rgba_lookup.r * 1.05, "GPU MIX_RGBA ramp uses premultiplied source intensity while MIX_RGB reads plain source RGB")
	var motion_sheet := SpriteSheet.new()
	var flow := Image.create_empty(64,32,false,Image.FORMAT_RGBA8)
	flow.fill(Color(0.5,1.0,0.0,0.5))
	motion_sheet.texture = ImageTexture.create_from_image(flow)
	motion_sheet.read({"sequences":[{"clamp":true,"frames":[[0,0,0.5,1],[0.5,0,1,1]]}]})
	SpriteSheet._loaded[MOTION] = motion_sheet
	for x in 64:
		for y in 32:
			alpha_image.set_pixel(x,y,Color(float(x)/31.0 if x < 32 else 0.0,0,0,1))
	(sheet.texture as ImageTexture).update(alpha_image)
	var stationary: Color = await _draw(renderer, 0.25)
	var motion_renderer := {"tex":TEXTURE,"tex_mv":MOTION,"blend":"alpha","motion_u":8.0,"motion_v":0.0}
	_quads.prepare(motion_renderer)
	# A ramp in the first frame and a black next frame makes flow visible;
	# identical linear ramps would cancel their opposite warps.
	stationary = await _draw(renderer, 0.125)
	var warped: Color = await _draw(motion_renderer, 0.125)
	_check(absf(warped.r - stationary.r) > 0.015, "GPU uses actual green/alpha motion channels to warp interpolated frames")
	var additive := {"tex":TEXTURE,"blend":"add"}
	_quads.prepare(additive)
	var added: Color = await _draw(additive, 0.0)
	_check(added.r > 0.1 and added.g < 0.02, "GPU compiles and draws the additive hit shader")
	var premul := {"tex":TEXTURE,"blend":"premul"}
	_quads.prepare(premul)
	var multiplied: Color = await _draw(premul, 0.0)
	_check(multiplied.r > 0.1 and multiplied.g < 0.02, "GPU compiles and draws the premultiplied hit shader")
	_viewport.free()


func _draw(renderer: Dictionary, frame: float, threshold: float = 0.0) -> Color:
	_quads.begin()
	_quads.card(renderer, Transform3D(Basis.IDENTITY.scaled(Vector3(3,3,1)),Vector3(0,0,-5)), 0,frame,Color.WHITE,threshold)
	_quads.finish()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image().get_pixel(SIZE / 2, SIZE / 2)
