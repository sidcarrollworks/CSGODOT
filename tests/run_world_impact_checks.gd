extends "res://tests/check_suite.gd"

## Surface inheritance, weighted/grazing choices, placement/fade and queued
## view delivery; real authored textures are checked when extracted.

class Particles extends Node:
	var contacts: Array[Dictionary] = []
	var sparks: Array[Dictionary] = []

	func queue_world(surface: String, position: Vector3, normal: Vector3, direction: Vector3, at_usec: int) -> void:
		contacts.append({"surface": surface, "position": position, "normal": normal, "direction": direction, "at_usec": at_usec})

	func queue_spark(position: Vector3, normal: Vector3, direction: Vector3, at_usec: int) -> void:
		sparks.append({"position": position, "normal": normal, "direction": direction, "at_usec": at_usec})


class FixtureImpacts extends BulletImpacts:
	var sounds: Array[Dictionary] = []

	func _ready() -> void:
		add_to_group(&"bullet_impacts")
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var texture := ImageTexture.create_from_image(image)
		_groups["Impact.Concrete"] = [{"weight": 1.0, "material": "fixture", "authored": true, "width": 5.8, "height": 5.8, "depth": 12.0, "offset": -4.0, "variance": 0.0, "fade_start": 30.0, "fade_duration": 3.0, "albedo_texture": texture, "normal_texture": null}]

	func _sound(surface: String, at: Vector3) -> void:
		sounds.append({"surface": surface, "position": at})


func _initialize() -> void:
	await process_frame
	_test_selection()
	_test_materials()
	_test_size_and_fade()
	_test_delivery()
	_test_extracted()
	if DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		await _test_projection_pixels()
	_finish("world-impacts")


func _test_selection() -> void:
	_check_equal(BulletImpacts.impact_for("physics_group_metal").get("decal"), "Impact.Metal", "metal inherits solidmetal's authored decal")
	_check_equal(BulletImpacts.impact_for("physics_group_wood_plank").get("effect"), "impact_wood", "a wood plank inherits its authored particles")
	_check_equal(BulletImpacts.impact_for("physics_group_sand").get("decal"), "Impact.Dirt", "sand takes dirt's authored decal instead of plaster")
	_check_equal(BulletImpacts.impact_for("physics_group_brick").get("decal"), "Impact.Rock", "brick inherits rock's decal rather than concrete's")
	_check_equal(BulletImpacts.impact_for("physics_group_wet").get("decal"), "", "an explicit empty decal stops inheritance")
	_check_equal(BulletImpacts.impact_for("physics_group_no_decal").get("decal"), "", "a no_decal surface stays unmarked")
	_check_equal(BulletImpacts.impact_for("unknown_fixture").get("decal"), "Impact.Concrete", "unknown surface names retain the concrete fallback")
	var grazing := BulletImpacts.is_grazing(Vector3(1.0, 0.0, -0.2), Vector3.BACK)
	_check(grazing and not BulletImpacts.is_grazing(Vector3.FORWARD, Vector3.BACK), "only a shallow incidence selects a grazing group")
	var metal := BulletImpacts.impact_for("physics_group_metal")
	_check_equal(BulletImpacts.decal_group(metal, grazing), "Impact.Metal_Grazing", "a metal graze selects its dedicated scratch materials")
	_check_equal(BulletImpacts.decal_group(metal, false), "Impact.Metal", "a straight metal hit uses the round-hole group")
	_check(not BulletImpacts.is_grazing(Vector3.ZERO, Vector3.BACK), "a missing direction cannot masquerade as a grazing hit")
	_check_equal(BulletImpacts.pick_material("Impact.Tile", 0.0), "materials/decals/tile/tile1.vmat", "the tile group's first weighted choice is preserved")
	_check_equal(BulletImpacts.pick_material("Impact.Tile", 0.27), "materials/decals/tile/tile1.vmat", "tile1 retains its authored double probability")
	_check_equal(BulletImpacts.pick_material("Impact.Tile", 0.30), "materials/decals/tile/tile2.vmat", "the weighted boundary advances to tile2")
	_check_equal(BulletImpacts.pick_material("Impact.Tile", 1.0), "materials/decals/tile/tile5.vmat", "the final boundary safely picks the last authored option")


func _test_materials() -> void:
	var hole := BulletImpacts.material_description("materials/decals/concrete/concrete1.vmat")
	_check_near(hole["width"], 5.8, "the current concrete material's width is 5.8 units")
	_check_near(hole["depth"], 12.0, "the material retains its authored projection depth")
	_check_near(hole["offset"], -4.0, "the material retains its authored projection offset")
	_check_equal(hole["color"], "materials/decals/concrete/bullethole_concrete_1_color_psd_5d8baebd.vtex", "the current compiled colour texture is selected")
	_check(String(hole["normal"]).ends_with("19befad2.vtex") and String(hole["occlusion"]).ends_with("8a3975ae.vtex"), "the current normal and AO texture slots are preserved")
	_check_near(hole["variance"], 0.5, "the material's own size variance is retained")
	var blood := BulletImpacts.material_description("materials/decals/blood/blood_decals_10_01.vmat")
	_check_near(blood["fade_start"], 180.0, "an authored lifetime overrides the generic fade convar")
	_check_near(blood["fade_duration"], 5.0, "an authored fade duration overrides the generic default")
	_check(BulletImpacts.material_description("no such material").is_empty(), "missing material metadata has no guessed texture")
	var tall := Image.create(32, 1024, false, Image.FORMAT_RGBA8)
	_check_equal(BulletImpacts._plain(tall).get_size(), Vector2i(8, 256), "a tall scratch texture has the same bounded longest edge as a square hole")


func _test_size_and_fade() -> void:
	_check_near(BulletImpacts.distance_scale(100.0), 1.0, "near decals retain their authored size")
	_check_near(BulletImpacts.distance_scale(256.0), 1.0, "the boost starts at 256 units")
	_check_near(BulletImpacts.distance_scale(896.0), 1.175, "the documented linear approximation reaches its midpoint")
	_check_near(BulletImpacts.distance_scale(1536.0), 1.35, "far decals reach the current 35-percent size boost")
	_check_near(BulletImpacts.distance_scale(3000.0), 1.35, "distance scaling stops growing beyond its end")
	var material := BulletImpacts.material_description("materials/decals/concrete/concrete1.vmat")
	var size := BulletImpacts.placement_size(material, Vector3.ZERO, 1536.0)
	_check(size.is_equal_approx(Vector3(5.8 * 1.35, 12.0, 5.8 * 1.35)), "distance boosts the visible width/height while leaving projection depth alone")
	_check_near(BulletImpacts.fade_at(29.0), 1.0, "persistent world holes remain opaque before the default fade")
	_check_near(BulletImpacts.fade_at(31.5), 0.5, "the default hole fades over three seconds")
	_check_near(BulletImpacts.fade_at(33.0), 0.0, "the default hole ends at 33 seconds")
	_check_near(BulletImpacts.fade_at(181.0, 180.0, 5.0), 0.8, "a material-specific longer lifetime uses its own fade")


func _test_delivery() -> void:
	var particles := Particles.new()
	root.add_child(particles)
	particles.add_to_group(&"hit_effects")
	var impacts := FixtureImpacts.new()
	impacts.max_holes = 2
	root.add_child(impacts)
	impacts.set_process(false)
	var result := Hitscan.Result.new()
	result.hit = true
	result.surface = "physics_group_concrete"
	result.position = Vector3(0.0, 0.0, -10.0)
	result.normal = Vector3.BACK
	var wall := Hitscan.Wall.new()
	wall.surface = "physics_group_concrete"
	wall.exit_surface = wall.surface
	wall.entry = Vector3(0.0, 0.0, -3.0)
	wall.exit = Vector3(0.0, 0.0, -5.0)
	wall.entry_normal = Vector3.BACK
	wall.exit_normal = Vector3.FORWARD
	result.walls.append(wall)
	impacts.mark(result, Vector3.FORWARD, 123_456)
	_check(impacts.holes == 0 and impacts.sounds.is_empty() and particles.contacts.is_empty(), "reporting a trace cannot render or start a sound inside the tick")
	result.position = Vector3(1000.0, 0.0, 0.0)
	wall.entry = Vector3(1000.0, 0.0, 0.0)
	impacts._process(0.0)
	_check_equal(impacts.holes, 3, "entry, exit and the stopped bullet create their three frame-delivered marks")
	var newest := impacts._hole_nodes[0] if impacts._hole_nodes[0].sorting_offset > impacts._hole_nodes[1].sorting_offset else impacts._hole_nodes[1]
	var older := impacts._hole_nodes[1] if newest == impacts._hole_nodes[0] else impacts._hole_nodes[0]
	_check(newest.sorting_offset - older.sorting_offset >= BulletImpacts.DECAL_ORDER_STEP and newest.sorting_offset >= BulletImpacts.DECAL_ORDER_STEP * 3,
		"each new mark sorts above every one before it by more than the largest box, so overlapping holes keep their order as the camera moves")
	_check(particles.sparks.is_empty(), "a round that went through nothing on the ground makes no sparks")
	var through := Hitscan.Result.new()
	through.items.append({"at": Vector3(2.0, 1.0, -8.0), "normal": Vector3.UP})
	impacts.mark(through, Vector3.FORWARD, 654_321)
	_check(particles.sparks.is_empty() and impacts.holes == 3, "a round through a dropped gun reports no hole, and sparks only on a frame")
	impacts._process(0.0)
	_check(particles.sparks.size() == 1 and particles.sparks[0]["position"] == Vector3(2.0, 1.0, -8.0)
		and particles.sparks[0]["normal"] == Vector3.UP and particles.sparks[0]["at_usec"] == 654_321 and impacts.holes == 3,
		"where it went through a dropped gun, sparks at that spot with the shot's time, and no hole")
	_check_equal(impacts._hole_nodes.size(), 2, "three marks reuse a bounded two-decal pool")
	_check_equal(impacts.sounds.size(), 2, "penetration keeps the existing entry/stop sounds without adding an exit sound")
	_check_equal(particles.contacts.size(), 3, "each world contact queues its authored particle request")
	_check_equal(particles.contacts[0]["position"], Vector3(0.0, 0.0, -3.0), "queued contact data is independent of later result changes")
	_check_equal(particles.contacts[0]["surface"], "concrete", "particles receive the actual cleaned surface name")
	_check_equal(particles.contacts[0]["at_usec"], 123_456, "particles retain the authoritative shot timestamp")
	var decal := impacts._hole_nodes[1]
	_check(decal.global_basis.y.dot(Vector3.FORWARD) > 0.99, "the penetration exit projects into the exit face")
	_check((decal.cull_mask & RigModel.LAYER) == 0, "world marks cannot stamp onto player models")
	_check((decal.cull_mask & DroppedItemView.LAYER) == 0, "nor onto a gun, the bomb or a grenade lying on the world")
	impacts._process(31.5)
	_check_near(decal.modulate.a, 0.5, "a reused decal receives the persistent fade")
	impacts._process(1.5)
	_check(impacts._hole_nodes.all(func(h: Decal) -> bool: return not h.visible), "expired holes are hidden and available for recycling")
	impacts.mark(result)
	impacts._process(0.0)
	_check_equal(impacts._hole_nodes.size(), 2, "expired slots are reused without growing the pool")
	_check(impacts._hole_nodes.all(func(h: Decal) -> bool: return h.modulate.a == 1.0), "recycling resets a faded decal's alpha")
	var sky := Hitscan.Result.new()
	sky.hit = true
	sky.surface = "physics_group_sky"
	impacts.mark(sky)
	_check(impacts._pending.is_empty(), "sky hits queue no sound, decal or particle")
	for i in BulletImpacts.MAX_PENDING + 20:
		impacts.mark(result)
	_check_equal(impacts._pending.size(), BulletImpacts.MAX_PENDING, "a frame backlog cannot grow without bound")
	impacts.free()
	particles.free()


func _test_extracted() -> void:
	if not DirAccess.dir_exists_absolute(SpriteSheet.DIR):
		print("Impact effect extraction absent; skipping real decal textures.")
		return
	var impacts := BulletImpacts.new()
	root.add_child(impacts)
	impacts.set_process(false)
	var missing := PackedStringArray()
	for group in ["Impact.Concrete", "Impact.Dirt", "Impact.Metal", "Impact.Metal_Grazing", "Impact.Wood", "Impact.Wood_Grazing", "Impact.Tile"]:
		if impacts._group_variants(group).is_empty():
			missing.append(group)
	_check(missing.is_empty(), "authored common and grazing materials are playable: %s" % ", ".join(missing))
	var hole := impacts._material_for("materials/decals/concrete/concrete1.vmat")
	_check(not hole.is_empty() and hole["albedo_texture"] != null and hole["normal_texture"] != null, "a current concrete mark has actual colour/AO and normal textures")
	if not hole.is_empty():
		_check((hole["albedo_texture"] as Texture2D).get_width() <= BulletImpacts.MAX_TEXELS, "persistent holes keep a bounded texture footprint")
	var loaded := impacts._materials.size()
	impacts._hole("physics_group_solidmetal", Vector3.ZERO, Vector3.BACK, Vector3(1.0, 0.0, -0.1))
	_check(String(impacts._hole_nodes[0].get_meta(&"material", "")).contains("grazing"), "a real shallow metal hit uses its authored grazing texture")
	_check_equal(impacts._materials.size(), loaded, "a hit prepares no new material or texture from disk")
	impacts.free()


## The pool's actual Decal projection and fade, on a lit receiver. This
## requires Forward+/Mobile; headless and Compatibility have no decals.
func _test_projection_pixels() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var receiver := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(20.0, 20.0)
	receiver.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.2, 0.65)
	receiver.material_override = material
	viewport.add_child(receiver)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.position = Vector3(0.0, 0.0, 20.0)
	camera.current = true
	viewport.add_child(camera)
	var impacts := FixtureImpacts.new()
	viewport.add_child(impacts)
	impacts.set_process(false)
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var baseline := viewport.get_texture().get_image().get_pixel(128, 128)
	impacts._hole("concrete", Vector3.ZERO, Vector3.BACK, Vector3.FORWARD)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png("res://.godot/pr172-decal-projection.png")
	var marked := image.get_pixel(128, 128)
	_check(marked.r > baseline.r + 0.3 and marked.g > baseline.g + 0.3, "the projected box really prints the fixture decal on its receiver")
	impacts._process(31.5)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var fading := viewport.get_texture().get_image().get_pixel(128, 128)
	_check(fading.r < marked.r - 0.1 and fading.r > baseline.r + 0.1, "the persistent alpha fade really fades rendered pixels")
	impacts._process(1.5)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var gone := viewport.get_texture().get_image().get_pixel(128, 128)
	_check(absf(gone.r - baseline.r) < 0.04 and absf(gone.g - baseline.g) < 0.04, "an expired decal restores the receiver pixels")
	impacts._hole("concrete", Vector3.ZERO, Vector3.BACK, Vector3.FORWARD)
	receiver.layers = RigModel.LAYER
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var player_layer := viewport.get_texture().get_image().get_pixel(128, 128)
	_check(absf(player_layer.r - baseline.r) < 0.04, "the same projection cannot print onto a receiver on the player layer")
	viewport.free()
