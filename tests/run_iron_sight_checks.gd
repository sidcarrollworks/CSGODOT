extends "res://tests/check_suite.gd"

## Checks the AUG's and SG 553's scopes, which raise the gun to the eye
## rather than putting it away (reference/research/scopes.md): the game's
## iron-sight numbers on both and on no other gun; the gun coming up at the
## pull-up speed as the scope goes in and down at the put-down speed as it
## comes out; the arms drawn at the iron-sight field of view while up, and
## the effects placed on them the same way; the crosshair put away while
## up; the first-person clips going to the pose at the eye and firing from
## it; the lens black at the hip and clear at the eye; and the outside
## focus effect drawing only while scoped, below the HUD.
##
##   godot --headless --path . --script tests/run_iron_sight_checks.gd
##
## Needs nothing extracted: the clips are made up here.

const SECOND := 1_000_000
const T0 := 100 * SECOND


func _initialize() -> void:
	_test_the_games_numbers()
	_test_the_gun_comes_up_and_goes_down()
	_test_the_arms_field_of_view()
	_test_the_view_uses_the_scoped_framing()
	_test_the_crosshair_is_put_away()
	_test_focus_only_while_scoped()
	_test_the_clips_at_the_eye()
	_test_the_glass_is_clear()
	_test_the_stand_in()
	_finish("iron_sight")


func _test_the_games_numbers() -> void:
	for gun in ["weapon_aug", "weapon_sg556"]:
		var data := WeaponLibrary.build(gun)
		_check(data.has_iron_sight(), "%s raises the gun to the eye as it scopes" % gun)
		_check_near(data.iron_sight_fov, 45.0, "%s's iron-sight vdata FOV is 45" % gun)
		_check_near(data.iron_sight_pull_up_speed, 10.0, "%s comes up at 10 a second" % gun)
		_check_near(data.iron_sight_put_down_speed, 8.0, "%s goes down at 8 a second" % gun)
	for gun in ["weapon_awp", "weapon_ssg08", "weapon_g3sg1", "weapon_scar20", "weapon_ak47"]:
		_check(not WeaponLibrary.build(gun).has_iron_sight(), "%s has no iron sight" % gun)


func _test_the_gun_comes_up_and_goes_down() -> void:
	var sg := _ready_weapon("weapon_sg556")
	_check_near(sg.iron_sight_amount(T0), 0.0, "the SG 553 starts at the hip")
	sg.press_zoom(T0)
	_check_near(sg.iron_sight_amount(T0), 0.0, "scoping, it starts from the hip")
	_check_near(sg.iron_sight_amount(T0 + SECOND / 20), 0.5, "half way up 0.05 s later")
	_check_near(sg.iron_sight_amount(T0 + SECOND / 10), 1.0, "up at 0.1 s")
	_check_near(sg.iron_sight_amount(T0 + SECOND), 1.0, "and stays up")
	var out := T0 + 2 * SECOND
	sg.press_zoom(out)
	_check_near(sg.iron_sight_amount(out + SECOND / 16), 0.5, "out of the scope, half way down at 1/16 s")
	_check_near(sg.iron_sight_amount(out + SECOND / 8), 0.0, "and down at 0.125 s")

	var awp := _ready_weapon("weapon_awp")
	awp.press_zoom(T0)
	_check_near(awp.iron_sight_amount(T0 + SECOND), 0.0, "the AWP's scope raises nothing")


func _test_the_arms_field_of_view() -> void:
	_check_near(ViewModelProjection.fov_narrowing(45.0, 45.0), 1.0,
		"the arms at the eye are drawn as the world is, at the scope's fov")
	var camera := Camera3D.new()
	camera.fov = ViewModelProjection.vertical_fov(45.0)
	var hip := ViewModelProjection.narrowing_under(camera)
	_check_near(hip, ViewModelProjection.fov_narrowing(45.0), "without the view's word the effects take the arms' 68")
	camera.set_meta(ViewModelProjection.ARMS_FOV_META, 45.0)
	_check_near(ViewModelProjection.narrowing_under(camera), 1.0, "and with it the arms' 45, as the gun is drawn")
	camera.free()


## Exercise the view's actual projection and its return to the hip. The
## world zoom stays at 45; framing the housing changes only the arms and
## the projection the muzzle effects read from the camera.
func _test_the_view_uses_the_scoped_framing() -> void:
	for gun in ["weapon_sg556", "weapon_aug"]:
		var player := PlayerController.new()
		player.input = PlayerInput.new()
		player.weapon = _ready_weapon(gun)
		player.weapon.call("_zoom_to", 1, DrawClock.usec() - SECOND)
		var view := PlayerView.new(player)
		view.camera = Camera3D.new()
		view.view_model = ViewModel.new()
		var expected_fov := 9.0 if gun == "weapon_sg556" else 10.0
		var look := WeaponLibrary.look(gun)
		if ResourceLoader.exists(look.model_path) and not RigModel.list_clips(ViewModel.clips_dir(look.clip_set)).is_empty():
			_check(view.view_model.setup("T", look.model_path, look.clip_set), "%s builds from its extracted sight clips" % gun)
			_check_near(view.view_model.iron_sight_arms_fov, expected_fov, "%s uses the framing calibrated with the extracted model" % gun)
		else:
			view.view_model.iron_sight_arms_fov = expected_fov
		view.call("_follow_scope")
		_check_near(view.camera.fov, ViewModelProjection.vertical_fov(45.0), "%s keeps the world's zoom at 45" % gun)
		_check(ViewModelProjection.narrowing_under(view.camera) > 4.0, "%s fills the scoped view, including its muzzle effects" % gun)
		player.weapon.call("_unscope")
		view.call("_follow_scope")
		_check_near(view.camera.fov, ViewModelProjection.vertical_fov(90.0), "%s restores the world at the hip" % gun)
		_check(not view.camera.has_meta(ViewModelProjection.ARMS_FOV_META), "%s restores the normal arms projection" % gun)
		view.view_model.free()
		view.camera.free()
		view.free()
		player.free()


func _test_the_crosshair_is_put_away() -> void:
	var player := PlayerSim.new()
	player.weapon = _ready_weapon("weapon_aug")
	_check(GameHud.shows_crosshair(player), "the AUG has its crosshair at the hip")
	# Scoped a second ago on the view's clock, which starts near 0, before
	# a new gun's draw would let a press through.
	player.weapon.call("_zoom_to", 1, DrawClock.usec() - SECOND)
	_check(not GameHud.shows_crosshair(player), "and none up at the eye, where its dot is the aim")
	_check(IronSightOverlay.amount_for(player) >= IronSightOverlay.DOT_FROM, "which the overlay draws")
	player.weapon = _ready_weapon("weapon_ak47")
	_check(GameHud.shows_crosshair(player), "the AK-47 keeps its crosshair")
	player.free()


## A first-person model with made-up clips: the hip's idle and shot, the
## pose at the eye and the shot from it.
func _test_the_clips_at_the_eye() -> void:
	var model := ViewModel.new()
	var player := AnimationPlayer.new()
	model.add_child(player)
	var library := AnimationLibrary.new()
	for clip in ["idle", "shoot1", "ironsight_fidget", "ironsight_shoot"]:
		var animation := Animation.new()
		animation.length = 0.5
		if not clip.contains("shoot"):
			animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip, animation)
	player.add_animation_library(&"", library)
	model.animation_player = player
	model.one_shots = PackedStringArray(["shoot", "ironsight_shoot"])
	model.idle = &"idle"
	model.shoot_clips = PackedStringArray(["shoot1"])
	model.set("_hip_idle", &"idle")
	root.add_child(model)
	model.play(&"idle")

	var sg := WeaponLibrary.build("weapon_sg556")
	model.raise_to_eye(0.2, sg)
	_check_equal(player.current_animation, "ironsight_fidget", "scoping, the gun goes to its pose at the eye")
	_check_equal(model.idle, &"ironsight_fidget", "and holds it there")
	model.raise_to_eye(1.0, sg)
	model.shoot()
	_check_equal(player.current_animation, "ironsight_shoot", "a round fired up there plays the shot at the eye")
	model.raise_to_eye(0.6, sg)
	_check_equal(model.idle, &"idle", "coming out, the idle is the hip's again")
	_check_equal(player.current_animation, "ironsight_shoot", "and the shot is left to finish first")
	model.raise_to_eye(0.0, sg)
	model.shoot()
	_check_equal(player.current_animation, "shoot1", "at the hip a round plays the hip's shot")

	var ak := WeaponLibrary.ak47()
	model.play(&"idle")
	model.raise_to_eye(1.0, ak)
	_check_equal(player.current_animation, "idle", "a gun without an iron sight stays at the hip")
	model.free()


func _test_the_glass_is_clear() -> void:
	_check(ViewModel.is_lens("rif_sg556_scope_glass") and ViewModel.is_lens("rif_aug_scope_glass")
		and ViewModel.is_lens("scope_lens_dirt"), "the SG 553's and AUG's glass and the lens dirt are the lens")
	_check(not ViewModel.is_lens("rif_sg556") and not ViewModel.is_lens("scope_sg556"),
		"the gun and the scope's body are not")
	var holder := ViewModel.new()
	var lens := ShaderMaterial.new()
	lens.shader = ViewModel.LENS_SHADER
	lens.set_shader_parameter(&"raised", 0.0)
	holder.set("_lens_material", lens)
	var mesh := MeshInstance3D.new()
	var array := ArrayMesh.new()
	for name in ["rif_sg556", "rif_sg556_scope_glass"]:
		var box := BoxMesh.new()
		array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
		var material := StandardMaterial3D.new()
		material.resource_name = name
		array.surface_set_material(array.get_surface_count() - 1, material)
	mesh.mesh = array
	holder.add_child(mesh)
	_check_equal(ViewModel.clear_lenses(holder, lens), 1, "one surface of the two is glass")
	var glass := mesh.get_active_material(1) as ShaderMaterial
	_check(glass == lens and glass.shader == ViewModel.LENS_SHADER, "and it uses this model's lens material")
	_check_equal(mesh.get_active_material(0).resource_name, "rif_sg556", "the gun's own is left alone")
	_check_near(lens.get_shader_parameter(&"raised"), 0.0, "the lens starts black at the hip")
	var sg := WeaponLibrary.build("weapon_sg556")
	holder.raise_to_eye(1.0, sg)
	_check_near(lens.get_shader_parameter(&"raised"), 1.0, "the lens clears at the eye")
	holder.raise_to_eye(0.5, sg)
	_check_near(lens.get_shader_parameter(&"raised"), 0.5, "the glass fades as the scope lowers")
	holder.call("_lower")
	_check_near(lens.get_shader_parameter(&"raised"), 0.0, "a deploy resets the lens to black")
	holder.raise_to_eye(1.0, WeaponLibrary.ak47())
	_check_near(lens.get_shader_parameter(&"raised"), 0.0, "only an iron sight can clear the lens")
	holder.free()


## The outside blur is below the HUD and stops drawing at the hip, on
## weapon switches, and on death. It also works without extracted models.
func _test_focus_only_while_scoped() -> void:
	var player := PlayerSim.new()
	player.weapon = _ready_weapon("weapon_sg556")
	var overlay := IronSightOverlay.new()
	overlay.player = player
	root.add_child(overlay)
	# The suite runs before the root's ready notification.
	if overlay.get("_focus_layer") == null:
		overlay.call("_ready")
	overlay.call("_process", 0.0)
	var layer := overlay.get("_focus_layer") as CanvasLayer
	var material := overlay.get("_focus_material") as ShaderMaterial
	_check(not layer.visible, "the hip view draws no focus pass")
	_check(layer.layer < 0, "focus draws below the HUD and scope dot")
	_check((layer.get_child(0) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the full-screen focus surface leaves firing input through")
	player.weapon.call("_zoom_to", 1, DrawClock.usec() - SECOND)
	overlay.call("_process", 0.0)
	_check(layer.visible, "scoping softens the outside world, even with no model")
	_check_near(material.get_shader_parameter(&"raised"), 1.0, "focus is fully raised with the scope")
	player.weapon.call("_zoom_to", 0, DrawClock.usec())
	overlay.call("_process", 0.0)
	_check(layer.visible, "focus remains while the gun starts lowering")
	player.weapon.call("_unscope")
	overlay.call("_process", 0.0)
	_check(not layer.visible, "the hip removes the screen-copy and blur pass")
	player.weapon = _ready_weapon("weapon_awp")
	player.weapon.call("_zoom_to", 1, DrawClock.usec() - SECOND)
	overlay.call("_process", 0.0)
	_check(not layer.visible, "a sniper keeps its own scope view")
	player.weapon = _ready_weapon("weapon_aug")
	player.weapon.call("_zoom_to", 1, DrawClock.usec() - SECOND)
	player.alive = false
	overlay.call("_process", 0.0)
	_check(not layer.visible, "death removes the focus effect")
	overlay.free()
	player.free()


func _test_the_stand_in() -> void:
	var sg := WeaponLibrary.build("weapon_sg556")
	_check_equal(IronSightOverlay.stands_in(sg), not ResourceLoader.exists(sg.model_path),
		"the stand-in is drawn exactly when the gun's model is not there")


func _ready_weapon(weapon_class: String) -> Weapon:
	var weapon := Weapon.new(WeaponLibrary.build(weapon_class))
	weapon.trigger_held = false
	return weapon
