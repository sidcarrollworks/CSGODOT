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

## The arms and what is in hand, drawn under the camera with a projection of
## their own (ViewModelProjection), when the models are there.
var view_model: ViewModel

## A view model for everything carried, by class, built as it comes into
## the inventory and kept while it is carried: taking something in hand
## shows its model and hides the others, where building the gun, its clips
## and the arms anew hitched every switch. The hidden ones are not
## processed, so their animations cost nothing.
var _view_models := {}
## What the tick changed that the view has yet to draw (catch_up): the
## inventory, and what is in hand. Built on the tick it happened, a view
## model read the disk and built its nodes there: a first buy or pickup of
## a gun took 136 ms of the tick.
var _view_models_due := false
var _in_hand_due := false
var _in_hand_entry: Inventory.Entry
## The side whose first-person clips are being read ahead (_read_ahead).
var _read_for_team := ""
## Planting, as last shown: the bomb's plant clip is playing.
var _planting := false
## The field of view last drawn, in CS2's degrees, and the view model it
## was drawn for: a scope narrows it (_follow_scope).
var _fov := ViewModelProjection.WORLD_FOV
var _fov_model: ViewModel

## What you hear of your own weapon and your hits, and of your own feet.
var weapon_sounds: WeaponSounds
var footsteps: Footsteps

## Your own body, seen when you look down: the third-person model without
## its head and arms, walking the same clips as a bot's. It stands in the
## world and casts no shadow; that is body_shadow's job.
var body_model: PlayerModel
## Your shadow: the same model walking the same clips in the same place,
## drawn only into the shadow maps, whole: head, arms and what is in hand,
## held, fired and reloaded as everyone else sees you hold it, as CS2's
## shadow is your third-person body. The body the camera sees has no head
## or arms, and a shadow without them is a strange thing to see.
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
	# Frames held just under the screen's refresh, as NVIDIA Reflex holds
	# CS2's with G-Sync and V-Sync on: inside a variable refresh screen's
	# range, V-Sync never has to hold one back (the Godot docs' advice for
	# G-Sync and FreeSync). A Max FPS set in Project Settings wins, as
	# CS2's fps_max would; headless, nothing is drawn to hold.
	if Engine.max_fps == 0 and DisplayServer.get_name() != "headless":
		Engine.max_fps = frame_cap(DisplayServer.screen_get_refresh_rate())
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
	weapon_sounds.watch(player)
	footsteps = Footsteps.new()
	footsteps.name = "Footsteps"
	player.add_child(footsteps)

	player.equipped.connect(_on_equipped)
	player.inventory.changed.connect(func() -> void: _view_models_due = true)
	player.pin_pulled.connect(_on_pin_pulled)
	player.grenade_released.connect(_on_grenade_released)
	player.reload_started.connect(_on_reload_started)
	player.shot_traced.connect(_on_shot_traced)
	player.killed.connect(_on_killed)
	player.respawned.connect(_on_respawned)
	player.team_changed.connect(_on_team_changed)


## Something else in hand: its model shown, drawing, and a gun's sounds,
## from the next frame (catch_up).
func _on_equipped(entry: Inventory.Entry) -> void:
	_in_hand_due = true
	_in_hand_entry = entry


## What the tick changed, drawn now: a view model for what came into the
## inventory, what is in hand shown, and your side's clips read ahead once
## it is known or has changed. Once a frame, before the view is placed; a
## check that changes the inventory calls it to see the result.
func catch_up() -> void:
	if _read_for_team != player.team:
		_read_for_team = player.team
		_read_ahead()
	if _view_models_due:
		_view_models_due = false
		_build_view_models()
	if _in_hand_due:
		_in_hand_due = false
		_show_in_hand(_in_hand_entry)
		if _in_hand_entry != null and _in_hand_entry.weapon != null:
			weapon_sounds.equip(_in_hand_entry.weapon.data)
		_in_hand_entry = null


## Every first-person clip of what your side might take in hand, read on
## worker threads while the game plays, so a first buy or pickup reads
## nothing from the disk (RigModel.read_ahead). Headless nothing is drawn,
## and nothing is read ahead.
func _read_ahead() -> void:
	if DisplayServer.get_name() != "headless":
		RigModel.read_ahead(first_person_clips(player.team))


## The first-person clips of every item a side's player can hold, as paths.
static func first_person_clips(team: String) -> PackedStringArray:
	var out := PackedStringArray()
	for def in ItemRegistry.all():
		var clip_set := String(WeaponLibrary.look(def.item_class, team).get("clip_set", ""))
		if not clip_set.is_empty():
			out.append_array(RigModel.list_clips(ViewModel.clips_dir(clip_set)))
	return out


func _on_pin_pulled() -> void:
	if view_model != null:
		view_model.play(&"pullpin")


func _on_grenade_released(underhand: bool) -> void:
	if view_model != null:
		view_model.play(&"throw_underhand" if underhand else &"throw_overhand")


func _on_reload_started() -> void:
	if view_model != null:
		view_model.play(&"reload")
	if body_shadow != null:
		body_shadow.play(&"reload", 0.1)
	weapon_sounds.reload()


func _on_shot_traced(shot: Weapon.Shot, result: Hitscan.Result) -> void:
	if shot.pellet == 0:
		if view_model != null:
			view_model.shoot()
		if body_shadow != null:
			body_shadow.fire()
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


## On the other side: that side's body to look down at, and its arms round
## everything carried.
func _on_team_changed(_team: String) -> void:
	for body in [body_model, body_shadow]:
		if body != null:
			body.queue_free()
	body_model = null
	body_shadow = null
	_show_body()
	for model: ViewModel in _view_models.values():
		_let_go(model)
	_view_models.clear()
	view_model = null
	viewmodel = null
	_view_models_due = true
	_in_hand_due = true
	_in_hand_entry = player.inventory.in_hand()
	_show_player(player.alive)


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


## The frames a second to hold to on a screen of this refresh rate: just
## under it, by the Godot docs' rule for variable refresh with V-Sync on
## (224 at 240 Hz, 138 at 144). 0, no cap, when the rate is not known.
static func frame_cap(refresh_hz: float) -> int:
	if refresh_hz <= 0.0:
		return 0
	return roundi(refresh_hz - refresh_hz * refresh_hz / 3600.0)


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
	var alpha := DrawClock.fraction()
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


## Shows the model of what is in hand, drawing it from the start, and puts
## the rest away; lets go of the models of what is no longer carried.
func _show_in_hand(entry: Inventory.Entry) -> void:
	_build_view_models()
	var shown: ViewModel = _view_models.get(entry.item.item_class) if entry != null else null
	for item_class: String in _view_models.keys():
		var model: ViewModel = _view_models[item_class]
		if model == shown:
			continue
		if not player.inventory.has(item_class):
			_let_go(model)
			_view_models.erase(item_class)
			continue
		model.put_away()
	view_model = shown
	# And it rides the recoil.
	viewmodel = shown
	_planting = false
	if shown == null:
		return
	shown.deploy(player.alive)


## A model for everything carried that has none, hidden until it is taken
## in hand: bought, picked up or handed out, it is built then, not at the
## switch.
func _build_view_models() -> void:
	if camera == null:
		return
	for entry in player.inventory.entries():
		if not _view_models.has(entry.item.item_class):
			_build_view_model(entry)


func _build_view_model(entry: Inventory.Entry) -> void:
	var look := {}
	if entry.weapon != null:
		look = {"model_path": entry.weapon.data.model_path, "clip_set": entry.weapon.data.clip_set}
	else:
		look = WeaponLibrary.look(entry.item.item_class, player.team)
	if String(look.get("clip_set", "")).is_empty():
		return
	var model := ViewModel.new()
	model.name = "ViewModel_%s" % entry.item.item_class
	model.visible = false
	model.process_mode = Node.PROCESS_MODE_DISABLED
	camera.add_child(model)
	if not model.setup(player.team, look["model_path"], look["clip_set"]):
		model.free()
		return
	ViewModelProjection.claim(model)
	_view_models[entry.item.item_class] = model


## Out of the view now, its name free for the next of its class, and freed
## at the frame's end.
static func _let_go(model: ViewModel) -> void:
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	model.queue_free()


## The bomb's plant clip while planting with it in hand, and back to the
## idle when a plant stops short.
func _follow_plant() -> void:
	var planting := player.alive and player.held_still and player.in_hand_class() == "weapon_c4"
	if planting == _planting:
		return
	_planting = planting
	if view_model != null:
		view_model.play(&"plant" if planting else view_model.idle)


## The body and its shadow, when the models are there. They are top_level
## like the camera and follow the interpolated position, so they do not step
## at the tick rate against a camera that does not.
func _show_body() -> void:
	body_model = _build_body("Body", FOLDED_BONES, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if body_model != null:
		body_shadow = _build_body("BodyShadow", [], GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)


## A body. The shadow's holds what is in hand (PlayerModel.hold), as a
## bot's does; the one you look down at holds nothing, its arms folded.
func _build_body(node_name: String, folded: Array[String], casting: GeometryInstance3D.ShadowCastingSetting) -> PlayerModel:
	var model := PlayerModel.new()
	model.name = node_name
	var shadow := casting == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# A model only the shadow maps see needs no lighting.
	model.probe_lit = not shadow
	if not model.setup(player.team, "", "", shadow):
		model.free()
		return null
	if not folded.is_empty():
		model.fold_bones(PackedStringArray(folded))
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = casting
	model.top_level = true
	player.add_child(model)
	return model


## The shadow holds what the player holds, its model shown and cast only
## into the shadow maps. Per frame, from what the tick left in the hand: the
## body the hitboxes ride took it up on the tick (PlayerSim._body_holds).
func _follow_hand() -> void:
	if body_shadow == null or not player.alive:
		return
	var item_class := player.in_hand_class()
	if body_shadow.holding != item_class:
		body_shadow.hold(item_class, WeaponLibrary.look(item_class, player.team) if not item_class.is_empty() else {})
	var shown := body_shadow.held_weapon
	body_shadow.show_held()
	if body_shadow.held_weapon != null and body_shadow.held_weapon != shown:
		for mesh in body_shadow.held_weapon.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


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
	# The mouse's movement since the frame began, taken in now, just before
	# the view is placed, rather than at the next frame's start. A frame that
	# runs a tick is drawn some 4.5 ms after it began (dust2, ten players),
	# and a turn read only at the start stepped unevenly on every such frame:
	# 1.7 ms off a steady turn, against 0.7 read here too (a real mouse,
	# reference/performance.md, "Frame pacing").
	DisplayServer.process_events()
	Input.flush_buffered_events()
	catch_up()
	_follow_scope()
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
	var alpha := DrawClock.fraction()
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

	_follow_plant()
	_follow_hand()
	_update_viewmodel(delta)
	# The arms from where the eyes are, the body from its middle.
	if view_model != null:
		view_model.light_from(camera.global_position)
	if body_model != null:
		body_model.light_from(interpolated + Vector3.UP * 40.0)


## The scope, as the gun in hand has it at this frame: the camera's field
## of view narrowed to its zoom (eased over the zoom time), the arms and gun
## put away while a sniper is scoped, and the mouse slowed by the zoomed
## field of view over the unzoomed one (CS2's zoom_sensitivity_ratio 1).
## The arms keep their own field of view whatever the world's.
func _follow_scope() -> void:
	var weapon := player.weapon if player.alive and _dead_for < 0.0 else null
	var fov := ViewModelProjection.WORLD_FOV
	var hidden := false
	var sensitivity := 1.0
	if weapon != null and weapon.data.zoom_levels() > 0:
		fov = weapon.zoom_fov_at(DrawClock.usec())
		hidden = weapon.through_scope()
		sensitivity = weapon.data.zoom_fov(weapon.zoom_level) / ViewModelProjection.WORLD_FOV * ZOOM_SENSITIVITY_RATIO
	player.input.zoom_sensitivity = sensitivity
	if view_model != null:
		view_model.visible = player.alive and not hidden
	if is_equal_approx(fov, _fov) and _fov_model == view_model:
		return
	_fov = fov
	_fov_model = view_model
	camera.fov = ViewModelProjection.vertical_fov(fov)
	if view_model != null:
		ViewModelProjection.claim(view_model, fov)


## CS2's zoom_sensitivity_ratio: scoped, the mouse turns the view this much
## on top of the narrowing of the field of view.
const ZOOM_SENSITIVITY_RATIO := 1.0


## Rides the weapon model on the same punch, scaled by viewmodel_recoil.
##
## The model is a child of the camera, so it already follows the view kick.
## This is the extra movement on top: the gun climbing in the hands relative
## to the screen, which is most of what reads as recoil. The knife, a
## grenade and the bomb only bob and sway.
func _update_viewmodel(delta: float) -> void:
	if viewmodel == null:
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
	var alpha := DrawClock.fraction()
	var punch := player.weapon.viewmodel_punch() if player.weapon != null else Vector2.ZERO
	var kick := player.previous_viewmodel_punch.lerp(punch, alpha)
	viewmodel.transform = Transform3D(
		motion.basis * _viewmodel_rest.basis
			* Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0)),
		_viewmodel_rest.origin + motion.origin
	)
