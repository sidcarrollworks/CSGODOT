class_name PlayerController
extends PlayerSim

## You: a player in the simulation (PlayerSim), driven by your keys and
## mouse, and drawn for you in first person (PlayerView).
##
## Every tick your input becomes one UserCmd (PlayerInput.build_command) and
## the simulation runs it, exactly as it runs a bot's, and as a server will
## run the commands a client sends. Nothing here decides anything about the
## game; it only turns keys into commands and hands the drawing to the view.

@export var camera: Camera3D

## Your keys and mouse, sampled as they happen; the look angles move at the
## rate frames are drawn, not the tick rate.
var input := PlayerInput.new()

## The camera, arms, body, shadow, sounds and bullet marks.
var view: PlayerView

signal died

## The view's parts, where the tests and the maps have always found them.
var view_model: ViewModel:
	get:
		return view.view_model if view != null else null
var body_model: PlayerModel:
	get:
		return view.body_model if view != null else null
var body_shadow: PlayerModel:
	get:
		return view.body_shadow if view != null else null
var weapon_sounds: WeaponSounds:
	get:
		return view.weapon_sounds if view != null else null
var footsteps: Footsteps:
	get:
		return view.footsteps if view != null else null


func _ready() -> void:
	super._ready()
	# Which hitboxes the bots' rounds meet, said once, as the range says it
	# for its dummy: the game's capsules on your body, or the stand-in boxes
	# and why.
	print("--- your hitboxes: %s" % hitbox_source())
	if hitboxes_missing():
		push_warning("Your hitboxes: %s" % hitbox_source())
	if camera == null:
		camera = _find_camera()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	view = PlayerView.new(self)
	add_child(view)
	killed.connect(func(_zone: StringName) -> void: died.emit())
	equip(WeaponLibrary.ak47())


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


## Where the map put you, to come back to, looking the way it faced you.
func place(spawn_position: Vector3, yaw: float) -> void:
	super.place(spawn_position, yaw)
	input.yaw_degrees = yaw
	input.pitch_degrees = 0.0


func _physics_process(delta: float) -> void:
	run_command(input.build_command(SimClock.current_tick()), delta)
