class_name GameMenu
extends UiScreen

## Local menu commands belong to the host. Opening settings or confirming
## quit leaves this screen alive underneath the nested screen.
signal resumed
signal settings_requested
signal quit_requested

var context_text := ""
var _view: Control
const VIEW := preload("res://src/ui/menus/game_menu_view.tscn")


func _ready() -> void:
	super._ready()
	var view := mount(VIEW)
	_view = view
	var context := view.get_node("%Context") as Label
	context.text = context_text
	context.visible = not context_text.is_empty()
	view.get_node("%Resume").pressed.connect(resume)
	view.get_node("%Settings").pressed.connect(_request_settings)
	view.get_node("%Quit").pressed.connect(_request_quit)


## Settings draw their own blurred world surface, as Panorama's content
## page hides the pause navbar. Keep this shell/input owner for returning.
func show_content(show_view: bool = true) -> void:
	if is_instance_valid(_view):
		_view.visible = show_view


func resume() -> void:
	if _closing or is_queued_for_deletion():
		return
	close_screen()
	resumed.emit()
	queue_free()


func _request_settings() -> void:
	if not _closing:
		settings_requested.emit()


func _request_quit() -> void:
	if not _closing:
		quit_requested.emit()


func handle_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return false
	resume()
	return true
