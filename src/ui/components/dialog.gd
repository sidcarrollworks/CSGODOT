class_name UiDialog
extends UiScreen

## Reusable confirmation popup. Callers connect result signals; this view
## never performs the requested action itself. Enter accepts, Escape cancels.
signal confirmed
signal cancelled
var title := "Confirm"
var message := ""
var confirm_text := "Confirm"
const VIEW := preload("res://src/ui/components/dialog_view.tscn")


func _ready() -> void:
	layer = UiStyle.MODAL_LAYER
	super._ready()
	var view := mount(VIEW)
	view.get_node("%Title").text = title
	view.get_node("%Message").text = message
	var accept := view.get_node("%Confirm") as Button
	accept.text = confirm_text
	accept.pressed.connect(resolve.bind(true))
	view.get_node("%Cancel").pressed.connect(resolve.bind(false))


func resolve(accept: bool) -> void:
	if _closing:
		return
	close_screen()
	if accept:
		confirmed.emit()
	else:
		cancelled.emit()
	queue_free()


func handle_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		resolve(true)
	elif key.keycode == KEY_ESCAPE:
		resolve(false)
	else:
		return false
	return true
