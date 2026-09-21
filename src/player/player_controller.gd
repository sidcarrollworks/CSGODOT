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

var input := PlayerInput.new()

var _tick_start_usec: int = 0
var _tick_length_usec: int = 0


func _ready() -> void:
	super._ready()
	_tick_length_usec = int(1_000_000.0 / float(Engine.physics_ticks_per_second))
	if camera == null:
		camera = _find_camera()
	if camera != null:
		camera.top_level = true
		# Source-unit scale: the near plane has to be well inside an inch or
		# geometry clips through the view model later on.
		camera.near = 1.0
		camera.far = 16384.0
		camera.fov = 90.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		input.handle_event(event)


func _physics_process(delta: float) -> void:
	_tick_start_usec = Time.get_ticks_usec()

	# Button transitions that happened during the frames since the last tick.
	# A tap shorter than one tick still has to register, so a press event in
	# the buffer counts even if the key is already back up by now. Only jump
	# and duck use this today; the timestamps are carried regardless so
	# shooting can use them unchanged once weapons exist.
	var jump_tapped := false
	for event in input.take_events():
		if event.action == &"jump" and event.pressed:
			jump_tapped = true

	wants_jump = Input.is_action_pressed(&"jump") or jump_tapped
	wants_duck = Input.is_action_pressed(&"duck")

	wish_dir = input.wish_direction()
	wish_speed = _current_max_speed()
	if wish_dir.length_squared() == 0.0:
		wish_speed = 0.0

	simulate(delta)


func _current_max_speed() -> float:
	var speed := config.max_speed
	if wants_duck:
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
	var eye_height: float = (
		config.duck_eye_height if wants_duck else config.stand_eye_height
	)
	var interpolated := previous_position.lerp(global_position, alpha)

	camera.global_position = interpolated + Vector3.UP * eye_height
	camera.global_rotation = Vector3(
		deg_to_rad(input.pitch_degrees),
		deg_to_rad(input.yaw_degrees),
		0.0
	)
