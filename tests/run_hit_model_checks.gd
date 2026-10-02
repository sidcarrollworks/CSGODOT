extends "res://tests/check_suite.gd"

## Bone-following projections, final fitted poses and actual mesh buffers.
## Forward+ also checks projected pixels and color/alpha on a real fleck.
const FLECK := {"kind": "model", "blend": "alpha", "model": "models/particle/flecks3.vmdl"}
const PUFF := {"kind": "model", "blend": "alpha", "model": "models/particle/impacts/impact_puff.vmdl"}

class ShiftModifier extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void:
		get_skeleton().set_bone_pose_position(0, Vector3(3.0, 0.0, 0.0))


func _initialize() -> void:
	await process_frame
	_test_wound_attachment()
	await _test_final_pose()
	_test_mesh_buffers()
	if DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		await _test_wound_pixels()
		await _test_fleck_pixels()
		await _test_plain_character_pixels()
	_finish("hit-models")


func _fixture_model(receiver: bool = true) -> PlayerModel:
	var model := PlayerModel.new()
	var skeleton := Skeleton3D.new()
	model.add_child(skeleton)
	model.character_rig = skeleton
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.add_bone("hit")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	skeleton.reset_bone_poses()
	if receiver:
		var mesh := MeshInstance3D.new()
		mesh.mesh = QuadMesh.new()
		mesh.layers = RigModel.LAYER
		model.add_child(mesh)
	model.set_process(false)
	return model


func _fixture_wounds(parent: Node) -> BodyWounds:
	var wounds := BodyWounds.new()
	parent.add_child(wounds)
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	wounds._texture = ImageTexture.create_from_image(image)
	wounds._normal = null
	return wounds


func _test_wound_attachment() -> void:
	var model := _fixture_model()
	root.add_child(model)
	model.position = Vector3(2.0, 4.0, 6.0)
	model.scale = Vector3.ONE * 2.0
	var second := _fixture_model()
	root.add_child(second)
	second.position = Vector3(-20.0, 0.0, 0.0)
	var wounds := _fixture_wounds(root)
	var source_pose := model.character_rig.global_transform * model.character_rig.get_bone_global_pose(0)
	var local_at := Vector3(1.0, 2.0, 0.0)
	var at := source_pose * local_at
	wounds.mark(4, [model, second], &"hit", at, Vector3.BACK)
	_check_equal(wounds.marks.size(), 2, "each drawn rig receives the shared bone-local hit")
	_check_equal(wounds._following.size(), 2, "each struck skeleton has one final-pose subscription")
	var first: Decal = wounds.marks[0].node
	var other: Decal = wounds.marks[1].node
	_check(first.global_position.is_equal_approx(at + Vector3.BACK * 0.05), "a scaled rig preserves the original world hit")
	_check(other.global_position.is_equal_approx(second.global_position + local_at + Vector3.BACK * 0.05), "a duplicate rig receives the same local point")
	_check(first.global_basis.y.dot(Vector3.BACK) > 0.99, "the body projector points inward, with positive Y along the outward normal")
	_check_equal(first.cull_mask, RigModel.LAYER, "body wounds only project onto the character layer")
	model.character_rig.set_bone_pose_position(0, Vector3(2.0, 0.0, 0.0))
	model.character_rig.set_bone_pose_rotation(0, Quaternion(Vector3.UP, PI * 0.5))
	wounds.update_marks()
	var pose := model.character_rig.global_transform * model.character_rig.get_bone_global_pose(0)
	var normal := (pose.basis * Vector3.BACK).normalized()
	_check(first.global_position.is_equal_approx(pose * local_at + normal * 0.05), "a moving/rotating bone carries its saved local point")
	_check(first.global_basis.y.dot(normal) > 0.99, "the wound normal turns with its struck bone")
	wounds.mark(5, [model], &"missing", at, Vector3.BACK)
	_check_equal(wounds.marks.size(), 2, "a missing bone cannot make a guessed body mark")
	var shadow := _fixture_model(false)
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.add_child(mesh)
	root.add_child(shadow)
	wounds.mark(4, [shadow], &"hit", Vector3.ZERO, Vector3.BACK)
	_check_equal(wounds.marks.size(), 2, "a shadow-only duplicate cannot double-stamp the visible body")
	var hidden := _fixture_model()
	root.add_child(hidden)
	(hidden.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).layers = PlayerSim.UNSEEN_LAYER
	wounds.mark(4, [hidden], &"hit", Vector3.ZERO, Vector3.BACK)
	_check_equal(wounds.marks.size(), 2, "an authority rig on the unseen layer cannot double-stamp the visible body")
	for i in BodyWounds.LIMIT + 5:
		wounds.mark(8, [model], &"hit", at, Vector3.BACK)
	_check_equal(wounds.marks.size(), BodyWounds.LIMIT, "sustained wounds retain a bounded mark pool")
	_check_equal(wounds._following.size(), 1, "evicting a rig's final mark removes its subscription")
	wounds.clear_player(4)
	_check_equal(wounds.marks.size(), BodyWounds.LIMIT, "clearing another user leaves these marks")
	wounds.clear_player(8)
	_check(wounds.marks.is_empty() and wounds._following.is_empty(), "respawn clears marks and final-pose subscriptions")
	wounds.mark(9, [second], &"hit", second.global_position, Vector3.BACK)
	second.free()
	wounds.update_marks()
	_check(wounds.marks.is_empty() and wounds._following.is_empty(), "a removed skeleton safely discards its marks and callback")
	wounds.free()
	model.free()
	shadow.free()
	hidden.free()


func _test_final_pose() -> void:
	var model := _fixture_model()
	model.character_rig.add_child(ShiftModifier.new())
	root.add_child(model)
	var wounds := _fixture_wounds(root)
	wounds.mark(3, [model], &"hit", Vector3.ZERO, Vector3.BACK)
	var decal: Decal = wounds.marks[0].node
	model.character_rig.advance(0.02)
	await process_frame
	await process_frame
	_check_near(decal.global_position.x, 3.0, "the final fitted pose updates the wound after skeleton modifiers, in the same render update")
	_check_near(model.character_rig.get_bone_global_pose(0).origin.x, 0.0, "outside the update, the bone getter still returns the unfitted pose")
	wounds.free()
	model.free()


func _test_mesh_buffers() -> void:
	if not ResourceLoader.exists("res://assets/effects/impacts/models/particle/flecks3.glb"):
		print("Fleck/puff extraction absent; skipping actual mesh-buffer checks.")
		return
	var models := HitModels.new()
	root.add_child(models)
	models.prepare(FLECK)
	models.prepare(PUFF)
	_check_equal((models._groups[FLECK.model] as Array).size(), 64, "all 64 actual fleck mesh groups are available")
	_check_equal((models._groups[PUFF.model] as Array).size(), 4, "all four actual impact puff meshes are available")
	var batch: Dictionary = models._groups[FLECK.model][0]
	_check((batch.mm.mesh as ArrayMesh).surface_get_array_len(0) > 0, "the mesh batch uses real extracted vertices")
	_check_equal((batch.node.material_override as StandardMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "the fleck material can draw authored alpha fades")
	models.begin()
	var xform := Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(2.0, 3.0, 4.0)), Vector3(5.0, 6.0, 7.0))
	var color := Color(0.2, 0.3, 0.4, 0.5)
	models.card(FLECK, xform, 0, color)
	models.finish()
	_check(batch.data[3] == 5.0 and batch.data[7] == 6.0 and batch.data[11] == 7.0, "submitted model data retains its full translation")
	_check_near(batch.data[15], color.a, "submitted model data retains the authored particle alpha")
	if DisplayServer.get_name() != "headless":
		_check((batch.mm.get_instance_transform(0) as Transform3D).is_equal_approx(xform), "the renderer reads the nontrivial bulk basis and translation correctly")
		_check((batch.mm.get_instance_color(0) as Color).is_equal_approx(color), "the renderer reads linear RGB and authored alpha correctly")
	_check_equal(batch.mm.visible_instance_count, 1, "only submitted model instances draw")
	for i in HitModels.CAPACITY + 20:
		models.card(FLECK, xform, 0, color)
	models.finish()
	_check_equal(batch.mm.visible_instance_count, HitModels.CAPACITY, "a flooded variant cannot overrun its fixed buffer")
	_check_equal(batch.mm.buffer.size(), HitModels.CAPACITY * 16, "bulk uploads remain a fixed transform/color stride")
	models.begin()
	models.finish()
	_check(not batch.node.visible, "a frame with no instances hides a formerly active mesh group")
	models.free()


func _viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.position = Vector3(0.0, 0.0, 20.0)
	camera.current = true
	viewport.add_child(camera)
	return viewport


func _drawn(viewport: SubViewport) -> Image:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _test_wound_pixels() -> void:
	var viewport := _viewport()
	var model := _fixture_model(false)
	viewport.add_child(model)
	var receiver := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(20.0, 20.0)
	receiver.mesh = quad
	receiver.layers = RigModel.LAYER
	var material := ShaderMaterial.new()
	material.shader = load("res://src/player/character.gdshader")
	material.set_shader_parameter(&"albedo_color", Color(0.12, 0.2, 0.65))
	var white := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	material.set_shader_parameter(&"albedo_texture", ImageTexture.create_from_image(white))
	var orm := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	orm.fill(Color(1.0, 1.0, 0.0))
	material.set_shader_parameter(&"orm_texture", ImageTexture.create_from_image(orm))
	material.set_shader_parameter(&"has_normal_map", false)
	material.set_shader_parameter(&"probe_energy", 1.0)
	receiver.material_override = material
	model.add_child(receiver)
	var wounds := _fixture_wounds(viewport)
	var before := await _drawn(viewport)
	var baseline := before.get_pixel(128, 128)
	wounds.mark(4, [model], &"hit", Vector3.ZERO, Vector3.BACK)
	var image := await _drawn(viewport)
	image.save_png("res://.godot/pr172-body-wound-projection.png")
	var marked := image.get_pixel(128, 128)
	_check(marked.r > baseline.r + 0.2 and marked.g > baseline.g + 0.2, "the inward wound projection reaches the actual character shader")
	model.character_rig.set_bone_pose_position(0, Vector3(7.0, 0.0, 0.0))
	model.character_rig.advance(0.01)
	image = await _drawn(viewport)
	var moved_centre := image.get_pixel(128, 128)
	var moved_mark := image.get_pixel(217, 128)
	_check(absf(moved_centre.r - baseline.r) < 0.04 and moved_mark.r > baseline.r + 0.2, "rendered coverage follows the changed bone instead of staying at the old hit")
	receiver.layers = 1
	image = await _drawn(viewport)
	_check(absf(image.get_pixel(217, 128).r - baseline.r) < 0.04, "the same wound projector cannot color world-layer geometry")
	# Direct light must receive the projected color too. A custom light()
	# can accidentally divide out Godot's decal mix after fragment().
	receiver.layers = RigModel.LAYER
	wounds.clear_player(4)
	model.character_rig.set_bone_pose_position(0, Vector3.ZERO)
	material.set_shader_parameter(&"probe_energy", 0.0)
	var sunlight := DirectionalLight3D.new()
	viewport.add_child(sunlight)
	var sun_before := (await _drawn(viewport)).get_pixel(128, 128)
	wounds.mark(4, [model], &"hit", Vector3.ZERO, Vector3.BACK)
	var sun_marked := (await _drawn(viewport)).get_pixel(128, 128)
	_check(sun_marked.r > sun_before.r + 0.12, "character direct sunlight receives the wound color (%s -> %s)" % [sun_before, sun_marked])
	viewport.free()


func _test_fleck_pixels() -> void:
	if not ResourceLoader.exists("res://assets/effects/impacts/models/particle/flecks3.glb"):
		return
	var viewport := _viewport()
	var models := HitModels.new()
	viewport.add_child(models)
	models.prepare(FLECK)
	var xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 150.0), Vector3.ZERO)
	models.begin()
	models.card(FLECK, xform, 0, Color(1.0, 0.1, 0.1, 1.0))
	models.finish()
	var opaque := await _drawn(viewport)
	var bright := 0.0
	var location := Vector2i.ZERO
	for y in opaque.get_height():
		for x in opaque.get_width():
			var pixel := opaque.get_pixel(x, y)
			if pixel.r > bright:
				bright = pixel.r
				location = Vector2i(x, y)
	_check(bright > 0.2, "an actual fleck mesh is visible through its submitted bulk transform")
	var color := opaque.get_pixelv(location)
	_check(color.r > color.g * 2.0, "the extracted mesh receives its per-particle RGB tint")
	models.begin()
	models.card(FLECK, xform, 0, Color(1.0, 0.1, 0.1, 0.25))
	models.finish()
	var faded := await _drawn(viewport)
	var fade := faded.get_pixelv(location).r
	_check(fade > 0.02 and fade < bright * 0.8, "authored particle alpha really fades the fleck's rendered pixels")
	viewport.free()


## Compare ordinary material pixels to the former direct-light formula,
## including colored cloth sheen. This checks the rendered result rather
## than only asserting that the shader contains a particular expression.
func _test_plain_character_pixels() -> void:
	var viewport := _viewport()
	var receiver := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(20.0, 20.0)
	receiver.mesh = quad
	viewport.add_child(receiver)
	var current := ShaderMaterial.new()
	current.shader = CharacterMaterials.SHADER
	var white := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	current.set_shader_parameter(&"albedo_texture", ImageTexture.create_from_image(white))
	var orm := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	orm.fill(Color(1.0, 0.7, 0.0))
	current.set_shader_parameter(&"orm_texture", ImageTexture.create_from_image(orm))
	current.set_shader_parameter(&"has_normal_map", false)
	var cloth_mask := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	cloth_mask.fill(Color(0.0, 0.0, 1.0))
	current.set_shader_parameter(&"cloth_mask", ImageTexture.create_from_image(cloth_mask))
	current.set_shader_parameter(&"sheen_tint", Vector3(0.7, 0.4, 0.2))
	var legacy_shader := Shader.new()
	legacy_shader.code = CharacterMaterials.SHADER.code.replace(
		"* character_diffuse_share;", "* (character_albedo / max(ALBEDO, vec3(1e-4)));")
	var legacy := current.duplicate() as ShaderMaterial
	legacy.shader = legacy_shader
	var sunlight := DirectionalLight3D.new()
	viewport.add_child(sunlight)
	for probes in [false, true]:
		sunlight.visible = not probes
		for cloth in [false, true]:
			for tint in [Color(0.12, 0.2, 0.65), Color(0.65, 0.3, 0.1)]:
				for material in [current, legacy]:
					material.set_shader_parameter(&"albedo_color", tint)
					material.set_shader_parameter(&"cloth_shading", cloth)
					material.set_shader_parameter(&"probe_energy", 1.0 if probes else 0.0)
				receiver.material_override = legacy
				var before := (await _drawn(viewport)).get_pixel(128, 128)
				receiver.material_override = current
				var after := (await _drawn(viewport)).get_pixel(128, 128)
				_check(absf(after.r - before.r) < 0.008 and absf(after.g - before.g) < 0.008 and absf(after.b - before.b) < 0.008,
					"ordinary character RGB is preserved: probes=%s cloth=%s tint=%s (%s -> %s)" % [probes, cloth, tint, before, after])
	viewport.free()
