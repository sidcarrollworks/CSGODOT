class_name ModePicker
extends CanvasLayer

## The game mode, chosen as a map starts, until there are menus (roadmap
## item 26): Competitive or Practice, by mouse, or by 1 and 2 while it is
## open (an open menu takes keys first, reference/binds.md), or Enter for
## the highlighted one. The last choice is remembered in user:// and is
## highlighted the next time; it is read here, before play, never in a tick.
##
## PlayScene shows it before the map loads, so choosing waits on nothing,
## and builds the mode once it says which (chosen). The mouse shows while it
## is open; the player captures it again as it is placed.

## The mode chosen: one of MODES.
signal chosen(mode_name: String)

## The choices, in order: key 1 is the first.
const MODES: Array[String] = ["Competitive", "Practice"]
const DESCRIPTIONS := {
	"Competitive": "5 v 5 with bots. Warmup, then a match of rounds.",
	"Practice": "No bots. Warmup, with its money and buying, until F5 starts the rounds.",
}

## Where the last choice is kept. The checks point it elsewhere.
var settings_file := "user://mode_picker.cfg"
## The choice Enter takes, and the one drawn lit.
var highlighted: int = 0

var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _screen: _Screen


func _ready() -> void:
	layer = 10
	highlighted = maxi(0, MODES.find(last_choice()))
	_mouse_before = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_screen = _Screen.new()
	_screen.picker = self
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)


## The mode chosen last time, or "" if none was.
func last_choice() -> String:
	var config := ConfigFile.new()
	if config.load(settings_file) != OK:
		return ""
	return String(config.get_value("mode_picker", "mode", ""))


## Takes a mode: remembers it, gives the mouse back, says which, and goes.
func choose(index: int) -> void:
	if index < 0 or index >= MODES.size() or is_queued_for_deletion():
		return
	var config := ConfigFile.new()
	config.set_value("mode_picker", "mode", MODES[index])
	config.save(settings_file)
	Input.set_mouse_mode(_mouse_before)
	chosen.emit(MODES[index])
	queue_free()


func _input(event: InputEvent) -> void:
	if handle_key(event):
		get_viewport().set_input_as_handled()


## 1 and 2 choose; up and down (or W and S) move the highlight; Enter or
## Space takes it. True where the key was the picker's.
func handle_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	match key.keycode:
		KEY_1, KEY_KP_1:
			choose(0)
		KEY_2, KEY_KP_2:
			choose(1)
		KEY_UP, KEY_W, KEY_LEFT:
			highlighted = posmod(highlighted - 1, MODES.size())
			_screen.queue_redraw()
		KEY_DOWN, KEY_S, KEY_RIGHT:
			highlighted = posmod(highlighted + 1, MODES.size())
			_screen.queue_redraw()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			choose(highlighted)
		_:
			return false
	return true


## The picker drawn in CS2's HUD style over a dark screen, laid out on the
## 1920x1080 base size the canvas stretch scales.
class _Screen:
	extends Control

	const CARD_SIZE := Vector2(840.0, 120.0)
	const CARD_GAP := 24.0
	const TITLE_SIZE := 44
	const NAME_SIZE := 36
	const TEXT_SIZE := 22

	var picker: ModePicker

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	## Where the choice at index is drawn.
	func card(index: int) -> Rect2:
		var count := ModePicker.MODES.size()
		var height := count * CARD_SIZE.y + (count - 1) * CARD_GAP
		var top := size.y * 0.5 - height * 0.5 + 40.0
		return Rect2(Vector2(size.x * 0.5 - CARD_SIZE.x * 0.5, top + index * (CARD_SIZE.y + CARD_GAP)), CARD_SIZE)

	func _card_at(point: Vector2) -> int:
		for i in ModePicker.MODES.size():
			if card(i).has_point(point):
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		var motion := event as InputEventMouseMotion
		if motion != null:
			var over := _card_at(motion.position)
			if over >= 0 and over != picker.highlighted:
				picker.highlighted = over
				queue_redraw()
			return
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var at := _card_at(button.position)
			if at >= 0:
				accept_event()
				picker.choose(at)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.92))
		var gold := HudStyle.T_COLOUR
		var first := card(0)
		HudStyle.draw_text(self, Vector2(size.x * 0.5, first.position.y - 48.0), "Choose a game mode",
			TITLE_SIZE, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		for i in ModePicker.MODES.size():
			var box := card(i)
			var lit := i == picker.highlighted
			draw_rect(box, Color(1, 1, 1, 0.12) if lit else Color(1, 1, 1, 0.04))
			draw_rect(box, gold if lit else Color(1, 1, 1, 0.25), false, 2.0)
			var mode_name: String = ModePicker.MODES[i]
			HudStyle.draw_text(self, box.position + Vector2(28.0, 50.0), "%d  %s" % [i + 1, mode_name],
				NAME_SIZE, gold if lit else Color.WHITE)
			HudStyle.draw_text(self, box.position + Vector2(28.0, 92.0), ModePicker.DESCRIPTIONS[mode_name],
				TEXT_SIZE, Color(1, 1, 1, 0.75))
		HudStyle.draw_text(self, Vector2(size.x * 0.5, card(ModePicker.MODES.size() - 1).end.y + 48.0),
			"1 or 2, or click. --mode competitive or --mode practice skips this.",
			TEXT_SIZE, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
