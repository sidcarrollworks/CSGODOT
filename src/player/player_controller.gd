class_name PlayerController
extends PlayerBody

## Drives the player body from local input, and owns the first-person camera.
##
## The camera is deliberately NOT a plain child of the body. The body moves on
## the 128 Hz simulation tick; the camera has to be smooth at whatever the
## monitor runs at, and mouse look has to be sampled at render rate. So the
## camera is top_level and its transform is rebuilt every frame from the
## interpolated body position plus the render-rate look angles.

@export var camera: Camera3D

## The weapon model, if there is one. Assign it and it rides the recoil.
##
## Optional and read-only from here: this rotates the node and touches nothing
## else, so whatever the model does for itself (bob, sway, animations) is left
## alone. Cosmetic in full; it changes nothing about aim or bullets.
@export var viewmodel: Node3D

## The weapon model's rest orientation, captured on the first frame so the
## recoil can be applied relative to however it was posed in the scene.
var _viewmodel_rest := Basis.IDENTITY
var _viewmodel_rest_captured := false

var input := PlayerInput.new()

## The weapon currently held. Swapped with the number keys.
var weapon: Weapon

## Which side's arms are on screen. Set by the map from the spawn.
@export_enum("T", "CT") var team: String = "T"

## The arms and weapon, drawn over the world by a camera of their own, when
## the models are there.
var view_model: ViewModel
var view_model_overlay: ViewModelOverlay

signal shot_traced(shot: Weapon.Shot, result: Hitscan.Result)

var _tick_start_usec: int = 0
var _tick_length_usec: int = 0


func _ready() -> void:
	super._ready()
	_tick_length_usec = int(1_000_000.0 / float(Engine.physics_ticks_per_second))
	if camera == null:
		camera = _find_camera()
	if camera != null:
		camera.top_level = true
		# Source-unit scale: the near plane has to be no more than an inch or
		# geometry clips through the view model later on.
		camera.near = 1.0
		camera.far = 16384.0
		# CS2's 90, which is horizontal at 4:3; Godot's number is vertical.
		camera.fov = ViewModelOverlay.vertical_fov(90.0)
		# The view model is drawn by the overlay's camera, not this one.
		camera.cull_mask &= ~(1 << (ViewModelOverlay.LAYER - 1))
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	equip(WeaponLibrary.ak47())


## Swaps to a weapon, which also changes how fast you can run.
func equip(data: WeaponData) -> void:
	weapon = Weapon.new(data)
	config.max_speed = data.max_player_speed
	_show_view_model(data)


func _show_view_model(data: WeaponData) -> void:
	if camera == null:
		return
	if view_model == null:
		view_model_overlay = ViewModelOverlay.new()
		add_child(view_model_overlay)
		view_model = ViewModel.new()
		view_model.name = "ViewModel"
		view_model_overlay.camera.add_child(view_model)
		# And it rides the recoil.
		viewmodel = view_model
	if view_model.setup(team, data.model_path, data.clip_set):
		ViewModelOverlay.claim(view_model)


func _find_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
		return
	if event.is_action_pressed(&"slot1"):
		equip(WeaponLibrary.ak47())
		return
	if event.is_action_pressed(&"slot2"):
		equip(WeaponLibrary.m4a1s())
		return
	if event.is_action_pressed(&"reload"):
		if weapon.start_reload(Time.get_ticks_usec()) and view_model != null:
			view_model.play(&"reload")
		return
	if event.is_action_pressed(&"noclip"):
		noclip = not noclip
		velocity = Vector3.ZERO
		return
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		input.handle_event(event)


func _physics_process(delta: float) -> void:
	_tick_start_usec = Time.get_ticks_usec()

	# Button transitions that happened during the frames since the last tick.
	# A tap shorter than one tick still has to register, so a press event in
	# the buffer counts even if the key is already back up by now. Each one
	# carries the instant it happened, which is what lets the jump and the
	# shot below land inside the tick rather than at its boundary.
	var jump_tapped := false
	var jump_press_usec := 0
	var fire_events: Array[PlayerInput.ButtonEvent] = []
	for event in input.take_events():
		if event.action == &"jump" and event.pressed:
			# The earliest press in the buffer is the one that jumps, so a
			# double tap inside one tick does not push the jump later.
			if not jump_tapped:
				jump_press_usec = event.timestamp_usec
			jump_tapped = true
		elif event.action == &"attack" and event.pressed:
			fire_events.append(event)

	wants_jump = Input.is_action_pressed(&"jump") or jump_tapped
	wants_duck = Input.is_action_pressed(&"duck")

	# Where inside this tick the press happened, so the body can split the tick
	# there instead of rounding the jump to the boundary. A jump from a held
	# key has no transition to time, so it stays at the boundary.
	jump_fraction = -1.0
	if jump_tapped:
		jump_fraction = PlayerInput.tick_fraction(
			jump_press_usec, _tick_start_usec, _tick_length_usec
		)

	if noclip:
		wish_dir = _noclip_direction()
		wish_speed = 0.0
		simulate(delta)
		return

	wish_dir = input.wish_direction()
	wish_speed = _current_max_speed()
	if wish_dir.length_squared() == 0.0:
		wish_speed = 0.0

	simulate(delta)
	_update_weapon(delta, fire_events)


## Fires any shots that happened during the frames since the last tick, at the
## instant and the aim angles they actually happened at.
##
## A held trigger fires on the tick as well, since an automatic weapon keeps
## going without further input events.
func _update_weapon(
	delta: float, fire_events: Array[PlayerInput.ButtonEvent]
) -> void:
	if weapon == null:
		return

	var now := Time.get_ticks_usec()
	weapon.finish_reload_if_due(now)
	# The weapon is told about the trigger rather than left to infer it from
	# the gap since the last round, so the crosshair starts coming home on the
	# frame the button comes up instead of a round and a quarter later. A press
	# that happened and ended between ticks still counts as held for this one.
	weapon.trigger_held = (
		Input.is_action_pressed(&"attack") or not fire_events.is_empty()
	)
	weapon.update(delta, now)

	var state := Weapon.ShooterState.new(
		Vector2(velocity.x, velocity.z).length(), on_ground, is_ducked
	)

	for event in fire_events:
		_try_shoot(
			event.timestamp_usec,
			PlayerInput.tick_fraction(
				event.timestamp_usec, _tick_start_usec, _tick_length_usec
			),
			event.yaw_degrees,
			event.pitch_degrees,
			state
		)

	if Input.is_action_pressed(&"attack"):
		_try_shoot(now, 1.0, input.yaw_degrees, input.pitch_degrees, state)


func _try_shoot(
	timestamp_usec: int,
	tick_fraction: float,
	yaw: float,
	pitch: float,
	state: Weapon.ShooterState
) -> void:
	# The shot came from where the player was at the instant of the click, not
	# from where the tick left them. CS2 sends this as an explicit
	# shoot_position. At 250 u/s, skipping it puts the muzzle up to ~1.6 units
	# from where it belongs, which is exactly the strafe-and-tap case that hit
	# registration arguments are made of.
	var at := previous_position.lerp(global_position, clampf(tick_fraction, 0.0, 1.0))
	var origin := at + Vector3.UP * eye_height()
	var shot := weapon.fire(
		timestamp_usec, tick_fraction, origin, yaw, pitch, state
	)
	if shot == null:
		return
	if view_model != null:
		view_model.shoot()

	var space := get_world_3d().direct_space_state
	var result := Hitscan.fire_at(space, shot, weapon.data, [get_rid()])
	shot_traced.emit(shot, result)


## Noclip flies where you are looking, pitch included, with jump and duck for
## straight up and down.
func _noclip_direction() -> Vector3:
	var pitch := deg_to_rad(input.pitch_degrees)
	var yaw := deg_to_rad(input.yaw_degrees)
	var forward := Vector3(
		-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)
	)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))

	var direction := (
		forward * Input.get_axis(&"move_back", &"move_forward")
		+ right * Input.get_axis(&"move_left", &"move_right")
	)
	if Input.is_action_pressed(&"jump"):
		direction += Vector3.UP
	if Input.is_action_pressed(&"duck"):
		direction += Vector3.DOWN

	if direction.length_squared() == 0.0:
		return Vector3.ZERO
	return direction.normalized()


func _current_max_speed() -> float:
	var speed := config.max_speed
	if is_ducked:
		speed *= config.duck_modifier
	elif Input.is_action_pressed(&"walk"):
		speed *= config.walk_modifier
	return speed


func _process(_delta: float) -> void:
	if camera == null:
		return

	# Interpolate between the last two simulation positions so the view is
	# smooth at any framerate rather than stepping at 128 Hz.
	var alpha := clampf(
		float(Time.get_ticks_usec() - _tick_start_usec) / float(_tick_length_usec),
		0.0, 1.0
	)
	var interpolated := previous_position.lerp(global_position, alpha)

	camera.global_position = interpolated + Vector3.UP * eye_height()
	# The recoil punch is added here rather than to the player's own look
	# angles, so the view kicks while the angles the player is actually
	# holding stay untouched. It is also deliberately smaller than the spray:
	# the crosshair suggests the recoil, it does not report it.
	var punch := weapon.aim_punch if weapon != null else Vector2.ZERO
	camera.global_rotation = Vector3(
		deg_to_rad(input.pitch_degrees + punch.y),
		deg_to_rad(input.yaw_degrees - punch.x),
		0.0
	)

	if view_model_overlay != null:
		view_model_overlay.follow(camera)
	_update_viewmodel()


## Rides the weapon model on the same punch, scaled by viewmodel_recoil.
##
## The model is a child of the camera, so it already follows the view kick.
## This is the extra movement on top: the gun climbing in the hands relative
## to the screen, which is most of what reads as recoil.
func _update_viewmodel() -> void:
	if viewmodel == null or weapon == null:
		return
	if not _viewmodel_rest_captured:
		_viewmodel_rest = viewmodel.transform.basis
		_viewmodel_rest_captured = true

	var kick := weapon.viewmodel_punch()
	viewmodel.transform.basis = (
		_viewmodel_rest
		* Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0))
	)
