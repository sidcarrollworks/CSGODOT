class_name PlayerController
extends PlayerSim

## You: a player in the simulation (PlayerSim), driven by your keys and
## mouse, and drawn for you in first person (PlayerView).
##
## Every tick the world asks for your command, your input since the last
## one (PlayerInput.build_command), and runs it, exactly as it runs a bot's,
## and as a server will run the commands a client sends. Nothing here decides
## anything about the game; it only turns keys into commands and hands the
## drawing to the view.

@export var camera: Camera3D

## Your keys and mouse, sampled as they happen; the look angles move at the
## rate frames are drawn, not the tick rate.
var input := PlayerInput.new()

## The camera, arms, body, shadow, sounds and bullet marks.
var view: PlayerView

## One local preference resource, shared with the round's music presenter.
var preferences: ClientPreferences
var preferences_file := ClientPreferences.FILE_PATH
var game_menu: GameMenu
var menu_context := ""
var _ui_generation := 0

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
	if UiInputScope.available_to(self):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	PlayerInput.ensure_actions()
	if preferences == null:
		preferences = ClientPreferences.current() if preferences_file == ClientPreferences.FILE_PATH else ClientPreferences.read_file(preferences_file)
	input.sensitivity = preferences.sensitivity
	_sync_menu_input()
	view = PlayerView.new(self)
	add_child(view)
	killed.connect(func(_zone: StringName) -> void: died.emit())
	control_changed.connect(_on_control_changed)
	# CS2's knife and your side's pistol, the pistol in hand; anything else
	# is bought (B), or given by whoever set starting_gun.
	_loadout()


func _find_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child
	return null


func _unhandled_input(event: InputEvent) -> void:
	_sync_menu_input()
	if event.is_action_pressed(&"ui_cancel"):
		open_game_menu()
		get_viewport().set_input_as_handled()
		return
	if not input.gameplay_blocked and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		input.handle_event(event)


## Where the map put you, to come back to, looking the way it faced you.
func place(spawn_position: Vector3, yaw: float) -> void:
	super.place(spawn_position, yaw)
	if view != null:
		view.camera_motion.reset()
	input.yaw_degrees = yaw
	input.pitch_degrees = 0.0


func command_for(tick: int, _dt: float) -> UserCmd:
	_sync_menu_input()
	# What the keys asked the game to do (G's drop), sent with the tick: the
	# game runs it after everyone's commands.
	# Driving a bot, they are the bot's: its gun dropped, its money spent.
	for line in input.take_commands():
		if is_instance_valid(world):
			world.game.command(pawn().userid, line)
	return input.build_command(tick)


## Reconcile before queued console commands as well as held button polling.
## The generation catches a menu opened and closed between two ticks.
func _sync_menu_input() -> void:
	var generation := UiInputScope.gameplay_generation
	input.set_gameplay_blocked(UiInputScope.blocks_gameplay(), generation != _ui_generation)
	_ui_generation = generation


func open_game_menu() -> void:
	if is_instance_valid(game_menu) or not UiInputScope.available_to(self):
		return
	game_menu = GameMenu.new()
	game_menu.context_text = menu_context
	game_menu.resumed.connect(_menu_resumed)
	game_menu.settings_requested.connect(_open_settings)
	game_menu.quit_requested.connect(_confirm_quit)
	add_child(game_menu)
	_sync_menu_input()


func _menu_resumed() -> void:
	game_menu = null
	_sync_menu_input()


func _open_settings() -> void:
	if not is_instance_valid(game_menu) or not game_menu.input_scope.is_top():
		return
	var screen := ClientSettingsScreen.new()
	screen.preferences = preferences
	screen.applied.connect(_apply_preferences)
	game_menu.show_content(false)
	screen.tree_exited.connect(game_menu.show_content)
	game_menu.add_child(screen)


func _apply_preferences(value: ClientPreferences) -> void:
	preferences.apply_from(value)
	input.sensitivity = preferences.sensitivity
	if preferences.save_file(preferences_file) != OK:
		var notice := UiDialog.new()
		notice.title = "Settings could not be saved"
		notice.message = "Changes apply for this session, but could not be saved to your user data folder."
		notice.confirm_text = "OK"
		game_menu.add_child(notice)


func _confirm_quit() -> void:
	if not is_instance_valid(game_menu) or not game_menu.input_scope.is_top():
		return
	var dialog := UiDialog.new()
	dialog.title = "Quit game?"
	dialog.message = "Leave this match and close CSGODOT?"
	dialog.confirm_text = "Quit"
	dialog.confirmed.connect(quit_to_desktop)
	game_menu.add_child(dialog)


func quit_to_desktop() -> void:
	get_tree().quit()


## A bot taken over: the mouse takes up where it was looking, so the view
## does not turn on the takeover.
func _on_control_changed() -> void:
	var driven := pawn()
	input.yaw_degrees = driven.yaw_degrees
	input.pitch_degrees = driven.pitch_degrees
