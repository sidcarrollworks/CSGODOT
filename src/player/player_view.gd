class_name PlayerView
extends Node

## What you see and hear of your own player: the first-person camera, the
## arms and weapon, your body when you look down and its shadow, your
## weapon's sounds and your footsteps, and the marks your rounds leave.
##
## It only reads the simulation (PlayerSim's state) and answers its signals;
## it never changes it. Everything here runs at the rate frames are drawn,
## between the simulation's ticks, which is why the camera is placed from the
## position interpolated between the last two ticks and from the look angles
## as the mouse has them now rather than as the last command had them.
##
## The camera is deliberately NOT a plain child of the body. The body moves on
## the 128 Hz simulation tick; the camera has to be smooth at whatever the
## monitor runs at, and mouse look has to be sampled at render rate. So the
## camera is top_level and its transform is rebuilt every frame from the
## interpolated body position plus the render-rate look angles.

## What the camera must not see of the body: the head it sits inside, and
## the arms the view model stands in for. Folding the upper arms folds the
## hands with them.
const FOLDED_BONES: Array[String] = ["head_0", "neck_0", "arm_upper_L", "arm_upper_R"]
## What the shadow does without: the arms, which would fall across the view
## model's own from a pose that is not its.
const SHADOW_FOLDED_BONES: Array[String] = ["arm_upper_L", "arm_upper_R"]

## How far behind the eyes the body stands, in units. The eyes are at the
## front of the head, over the chest; at zero the collar fills the bottom of
## the view looking straight ahead. This puts the chest below the view until
## you look down for it.
const BODY_SETBACK := 8.0

var player: PlayerController
var camera: Camera3D

## The weapon model, if there is one. It rides the recoil.
##
## Only rotated and moved from here: whatever the model does for itself
## (animations) is left alone. Cosmetic in full; it changes nothing about aim
## or bullets.
var viewmodel: Node3D

## The bob of walking and the lag of turning, on the weapon model.
var viewmodel_motion := ViewModelMotion.new()

## The arms and weapon, drawn under the camera with a projection of their
## own (ViewModelProjection), when the models are there.
var view_model: ViewModel

## What you hear of your own weapon and your hits, and of your own feet.
var weapon_sounds: WeaponSounds
var footsteps: Footsteps

## Your own body, seen when you look down: the third-person model without
## its head and arms, walking the same clips as a bot's. It stands in the
## world and casts no shadow; that is body_shadow's job.
var body_model: PlayerModel
## Your shadow: the same model walking the same clips in the same place,
## drawn only into the shadow maps, with its head. The body the camera sees
## has none, and a shadow without one is a strange thing to see.
var body_shadow: PlayerModel

## The weapon model's rest pose, captured on the first frame so the recoil,
## bob and sway can be applied relative to however it was posed in the scene.
var _viewmodel_rest := Transform3D.IDENTITY
var _viewmodel_rest_captured := false


func _init(p_player: PlayerController) -> void:
	player = p_player
	name = "View"


func _ready() -> void:
	camera = player.camera
	if camera != null:
		camera.top_level = true
		# Source-unit scale: the near plane has to be a fraction of an inch or
		# the view model, drawn squeezed towards the camera, clips.
		camera.near = ViewModelProjection.NEAR
		camera.far = 16384.0
		# CS2's 90, which is horizontal at 4:3; Godot's number is vertical.
		camera.fov = ViewModelProjection.vertical_fov(ViewModelProjection.WORLD_FOV)
	_show_body()
	weapon_sounds = WeaponSounds.new()
	weapon_sounds.name = "WeaponSounds"
	player.add_child(weapon_sounds)
	footsteps = Footsteps.new()
	footsteps.name = "Footsteps"
	player.add_child(footsteps)

	player.equipped.connect(_on_equipped)
	player.reload_started.connect(_on_reload_started)
	player.shot_traced.connect(_on_shot_traced)
	player.killed.connect(_on_killed)
	player.respawned.connect(_on_respawned)


func _on_equipped(data: WeaponData) -> void:
	_show_view_model(data)
	weapon_sounds.equip(data)


func _on_reload_started() -> void:
	if view_model != null:
		view_model.play(&"reload")
	weapon_sounds.reload()


func _on_shot_traced(_shot: Weapon.Shot, result: Hitscan.Result) -> void:
	if view_model != null:
		view_model.shoot()
	weapon_sounds.shot()
	if result.hitbox != null and result.hitbox.target != null:
		weapon_sounds.hit(result.zone, result.hitbox.target, not result.hitbox.target.alive)
	BulletImpacts.mark_in(get_tree(), result)


## Dead: the arms and body gone until the respawn.
func _on_killed(_zone: StringName) -> void:
	_show_player(false)


func _on_respawned() -> void:
	_show_player(true)


func _show_player(shown: bool) -> void:
	if view_model != null:
		view_model.visible = shown
	for body in [body_model, body_shadow]:
		if body != null:
			body.visible = shown


func _show_view_model(data: WeaponData) -> void:
	if camera == null:
		return
	if view_model == null:
		view_model = ViewModel.new()
		view_model.name = "ViewModel"
		camera.add_child(view_model)
		# And it rides the recoil.
		viewmodel = view_model
	if view_model.setup(player.team, data.model_path, data.clip_set):
		ViewModelProjection.claim(view_model)


## The body and its shadow, when the models are there. They are top_level
## like the camera and follow the interpolated position, so they do not step
## at the tick rate against a camera that does not.
func _show_body() -> void:
	body_model = _build_body("Body", FOLDED_BONES, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if body_model != null:
		body_shadow = _build_body("BodyShadow", SHADOW_FOLDED_BONES, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)


func _build_body(node_name: String, folded: Array[String], casting: GeometryInstance3D.ShadowCastingSetting) -> PlayerModel:
	var model := PlayerModel.new()
	model.name = node_name
	# A model only the shadow maps see needs no lighting.
	model.probe_lit = casting != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if not model.setup(player.team, ""):
		model.free()
		return null
	model.fold_bones(PackedStringArray(folded))
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = casting
	model.top_level = true
	player.add_child(model)
	return model


## After each tick the player has run (a child ticks after its parent): the
## body walks the clips for how it moved.
func _physics_process(_delta: float) -> void:
	if not player.alive:
		return
	for body in [body_model, body_shadow]:
		if body != null:
			body.update_motion(player.velocity, player.input.yaw_degrees, player.is_ducked, player.on_ground)


func _process(delta: float) -> void:
	if camera == null:
		return

	# Between the last two simulation positions, by how far this frame falls
	# between their ticks, so the view is smooth at any framerate rather than
	# stepping at 128 Hz.
	var alpha := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var interpolated := player.previous_position.lerp(player.global_position, alpha)

	camera.global_position = interpolated + Vector3.UP * player.eye_height()
	var yaw := deg_to_rad(player.input.yaw_degrees)
	for body in [body_model, body_shadow]:
		if body != null:
			body.global_position = interpolated + Vector3(sin(yaw), 0.0, cos(yaw)) * BODY_SETBACK
	# The recoil punch is added here rather than to the player's own look
	# angles, so the view kicks while the angles the player is actually
	# holding stay untouched. It is also deliberately smaller than the spray:
	# the crosshair suggests the recoil, it does not report it.
	var punch := player.weapon.aim_punch if player.weapon != null else Vector2.ZERO
	# And where a hit has thrown the aim, all of it: that one is where the
	# rounds go, so the crosshair tells the truth about it.
	punch += player.hit_punch.value
	camera.global_rotation = Vector3(
		deg_to_rad(player.input.pitch_degrees + punch.y),
		deg_to_rad(player.input.yaw_degrees - punch.x),
		0.0
	)

	_update_viewmodel(delta)
	# The arms from where the eyes are, the body from its middle.
	if view_model != null:
		view_model.light_from(camera.global_position)
	if body_model != null:
		body_model.light_from(interpolated + Vector3.UP * 40.0)


## Rides the weapon model on the same punch, scaled by viewmodel_recoil.
##
## The model is a child of the camera, so it already follows the view kick.
## This is the extra movement on top: the gun climbing in the hands relative
## to the screen, which is most of what reads as recoil.
func _update_viewmodel(delta: float) -> void:
	if viewmodel == null or player.weapon == null:
		return
	if not _viewmodel_rest_captured:
		_viewmodel_rest = viewmodel.transform
		_viewmodel_rest_captured = true

	# The bob and sway move the model in the camera's frame, the kick in the
	# model's own.
	var motion := viewmodel_motion.update(
		delta, player.velocity, player.on_ground,
		Vector2(player.input.yaw_degrees, player.input.pitch_degrees)
	)
	var kick := player.weapon.viewmodel_punch()
	viewmodel.transform = Transform3D(
		motion.basis * _viewmodel_rest.basis
			* Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0)),
		_viewmodel_rest.origin + motion.origin
	)
