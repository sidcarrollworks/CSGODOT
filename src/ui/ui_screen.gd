class_name UiScreen
extends CanvasLayer

## Full-screen menu shell. A PackedScene supplies its panel tree. Signals
## supply actions; it never writes simulation state. Popups use MODAL_LAYER.
## Each nested shell gets a higher layer, including during a scene handoff.
var input_scope: UiInputScope
## A menu stops the local player's commands; the match keeps running.
## Cursor-only surfaces such as the buy menu keep their existing policy.
var block_gameplay: bool = true
var _closing := false
static var _screens: Array[WeakRef] = []


func _ready() -> void:
	var next_layer := UiStyle.MENU_LAYER
	for existing in _screens:
		var screen := existing.get_ref() as UiScreen
		if is_instance_valid(screen):
			next_layer = maxi(next_layer, screen.layer + 1)
	layer = maxi(layer, next_layer)
	_screens.append(weakref(self))
	input_scope = UiInputScope.acquire(self, block_gameplay)


func mount(scene: PackedScene) -> Control:
	var view := scene.instantiate() as Control
	view.theme = UiStyle.menu()
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.mouse_force_pass_scroll_events = false
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.modulate.a = 0.0
	view.create_tween().tween_property(view, "modulate:a", 1.0, UiStyle.FADE_SECONDS)
	return view


## Release before emitting a result that may open the next screen.
func close_screen() -> void:
	_closing = true
	set_process_input(false)
	if input_scope != null:
		input_scope.release()
		input_scope = null
	hide()


func _exit_tree() -> void:
	if input_scope != null:
		input_scope.release()
	for i in range(_screens.size() - 1, -1, -1):
		if _screens[i].get_ref() == self or not is_instance_valid(_screens[i].get_ref()):
			_screens.remove_at(i)


func _input(event: InputEvent) -> void:
	if _closing or input_scope == null or not input_scope.is_top():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		get_viewport().gui_release_focus()
	# Explicit shortcuts first; otherwise native focused fields get the key.
	# Mouse activation also belongs to Control._gui_input, never this phase.
	if handle_key(event):
		get_viewport().set_input_as_handled()


func _unhandled_key_input(_event: InputEvent) -> void:
	_block_unused_input()


func _shortcut_input(_event: InputEvent) -> void:
	_block_unused_input()


func _unhandled_input(_event: InputEvent) -> void:
	_block_unused_input()


func _block_unused_input() -> void:
	if not _closing and input_scope != null and input_scope.is_top():
		get_viewport().set_input_as_handled()


func handle_key(_event: InputEvent) -> bool:
	return false
