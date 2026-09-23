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
## the 64 Hz simulation tick; the camera has to be smooth at whatever the
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

## Dead, the camera leaves your eyes for a view of your body from outside:
## this far from its middle, looking down on it at least this steeply, turned
## round it by the mouse, and taking this long to get there. By eye; CS2's
## death camera has convars of its own that are not matched here.
const DEATH_CAM_DISTANCE := 110.0
const DEATH_CAM_DOWN_DEGREES := 20.0
const DEATH_CAM_SECONDS := 0.6
## How far off a wall behind it the camera stays, in units.
const DEATH_CAM_WALL_GAP := 6.0

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

## How long you have been dead, and where the camera was when you died.
var _dead_for := -1.0
var _died_at := Transform3D.IDENTITY

## The teammate whose eyes the camera is in, while dead in a round
## (PlayerSim.observing): their body is kept from the camera, as your own
## is, while it is looked out of.
var _watched: PlayerSim


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
		# Not the body your hitboxes ride: that one is for everyone else.
		camera.cull_mask &= ~PlayerSim.UNSEEN_LAYER
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
	player.team_changed.connect(_on_team_changed)


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


## Dead: the arms and the body you look down at gone until the respawn,
## and the camera out of your head to watch the body the simulation wears
## fall (PlayerSim.ragdoll), drawn for you now.
func _on_killed(_zone: StringName) -> void:
	_show_player(false)
	_show_corpse(true)
	_dead_for = 0.0
	if camera != null:
		_died_at = camera.global_transform


func _on_respawned() -> void:
	_watch(null)
	_show_player(true)
	_show_corpse(false)
	_dead_for = -1.0


## On the other side: that side's body to look down at and its arms.
func _on_team_changed(_team: String) -> void:
	for body in [body_model, body_shadow]:
		if body != null:
			body.queue_free()
	body_model = null
	body_shadow = null
	_show_body()
	_show_player(player.alive)
	if player.weapon != null:
		_show_view_model(player.weapon.data)


## Your body as everyone else sees it, shown to your own camera or put back
## where it cannot see it (UNSEEN_LAYER), lit and casting a shadow while
## shown.
func _show_corpse(shown: bool) -> void:
	var model := player.model
	if model == null:
		return
	if shown:
		model.use_probe_lighting()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = 1 if shown else PlayerSim.UNSEEN_LAYER
		(mesh as MeshInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shown else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)


## Where the death camera sits, from the body's middle: back along where
## the mouse looks, above the body, and in front of any wall behind it.
func death_cam_position(centre: Vector3, yaw_degrees: float, pitch_degrees: float) -> Vector3:
	var pitch := deg_to_rad(minf(pitch_degrees, -DEATH_CAM_DOWN_DEGREES))
	var looking := Basis.from_euler(Vector3(pitch, deg_to_rad(yaw_degrees), 0.0)) * Vector3.FORWARD
	var wanted := centre - looking * DEATH_CAM_DISTANCE
	if player.is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(centre, wanted, Hitscan.WORLD_LAYER)
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var reach := maxf(centre.distance_to(hit["position"]) - DEATH_CAM_WALL_GAP, 0.0)
			wanted = centre - looking * reach
	return wanted


## Dead in a round, watching a teammate: from their eyes, where they look,
## or, in chase, from behind and above them the way the death camera
## watches your own body, turned by the mouse.
func _spectate(watched: PlayerSim) -> void:
	var alpha := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var at := watched.previous_position.lerp(watched.global_position, alpha)
	if player.observing_chase:
		_watch(null)
		var centre := at + Vector3.UP * 48.0
		camera.global_position = death_cam_position(centre, player.input.yaw_degrees, player.input.pitch_degrees)
		if camera.global_position.distance_to(centre) > 1.0:
			camera.look_at(centre, Vector3.UP)
		return
	_watch(watched)
	camera.global_position = at + Vector3.UP * watched.eye_height()
	camera.global_rotation = Vector3(
		deg_to_rad(lerpf(watched.previous_pitch_degrees, watched.pitch_degrees, alpha)),
		lerp_angle(deg_to_rad(watched.previous_yaw_degrees), deg_to_rad(watched.yaw_degrees), alpha),
		0.0
	)


## Keeps a body out of the camera while the camera is in its head, and
## gives the last one back.
func _watch(watched: PlayerSim) -> void:
	if watched == _watched:
		return
	for other: PlayerSim in [_watched, watched]:
		if other == null or not is_instance_valid(other) or other.model == null:
			continue
		for mesh in other.model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).layers = PlayerSim.UNSEEN_LAYER if other == watched else 1
	_watched = watched


func _death_cam(delta: float) -> void:
	_dead_for += delta
	var centre := player.body_centre()
	var at := death_cam_position(centre, player.input.yaw_degrees, player.input.pitch_degrees)
	var there := Transform3D(Basis.IDENTITY, at)
	if at.distance_to(centre) > 1.0:
		there = there.looking_at(centre, Vector3.UP)
	else:
		there.basis = _died_at.basis
	var t := smoothstep(0.0, 1.0, _dead_for / DEATH_CAM_SECONDS)
	camera.global_transform = Transform3D(
		_died_at.basis.get_rotation_quaternion().slerp(there.basis.get_rotation_quaternion(), t),
		_died_at.origin.lerp(there.origin, t)
	)
	if player.model != null:
		player.model.light_from(centre)


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


## After each tick the player has run (the world runs the tick before any
## other node's physics callback): the body walks the clips for how it moved.
func _physics_process(_delta: float) -> void:
	if not player.alive:
		return
	for body in [body_model, body_shadow]:
		if body != null:
			body.update_motion(player.velocity, player.input.yaw_degrees, player.duck_progress, player.on_ground)


func _process(delta: float) -> void:
	if camera == null:
		return
	if _dead_for >= 0.0:
		var watched := player.observing
		if watched != null and is_instance_valid(watched) and watched.alive:
			_spectate(watched)
		else:
			_watch(null)
			_death_cam(delta)
		return

	# Between the last two simulation positions, by how far this frame falls
	# between their ticks, so the view is smooth at any framerate rather than
	# stepping at the 64 Hz tick.
	var alpha := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var interpolated := player.previous_position.lerp(player.global_position, alpha)

	camera.global_position = interpolated + Vector3.UP * player.eye_height()
	var yaw := deg_to_rad(player.input.yaw_degrees)
	for body in [body_model, body_shadow]:
		if body != null:
			body.global_position = interpolated + Vector3(sin(yaw), 0.0, cos(yaw)) * BODY_SETBACK
			# Turned with the view every frame, not with the ticks.
			body.rotation.y = PI + yaw
	# The recoil punch is added here rather than to the player's own look
	# angles, so the view kicks while the angles the player is actually
	# holding stay untouched. It is also deliberately smaller than the spray:
	# the crosshair suggests the recoil, it does not report it. And where a
	# hit has thrown the aim, all of it: that one is where the rounds go, so
	# the crosshair tells the truth about it. Both between the last two
	# ticks, as the position is.
	var punch := player.previous_view_punch.lerp(player.view_punch(), alpha)
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
	var alpha := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var kick := player.previous_viewmodel_punch.lerp(player.weapon.viewmodel_punch(), alpha)
	viewmodel.transform = Transform3D(
		motion.basis * _viewmodel_rest.basis
			* Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0)),
		_viewmodel_rest.origin + motion.origin
	)
