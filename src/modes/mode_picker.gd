class_name ModePicker
extends UiScreen

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
	"Practice": "No bots, unlimited money and grenade buys. F5 starts the rounds.",
}

## Where the last choice is kept. The checks point it elsewhere.
var settings_file := "user://mode_picker.cfg"
## The choice Enter takes, and the one drawn lit.
var highlighted: int = 0

var _screen: Control
var _cards: Array[UiChoiceCard] = []
const VIEW := preload("res://src/modes/mode_picker_view.tscn")
const CARD := preload("res://src/ui/components/choice_card.tscn")


func _ready() -> void:
	super._ready()
	highlighted = maxi(0, MODES.find(last_choice()))
	_screen = mount(VIEW)
	_screen.get_node("Backdrop").color = UiStyle.BACKDROP
	var choices := _screen.get_node("%Choices") as VBoxContainer
	for i in MODES.size():
		var card := CARD.instantiate() as UiChoiceCard
		choices.add_child(card)
		card.activated.connect(choose.bind(i))
		card.pointed.connect(_pointed.bind(i))
		_cards.append(card)
	_refresh_cards()


func _pointed(index: int) -> void:
	highlighted = index
	_refresh_cards()


func _refresh_cards() -> void:
	for i in _cards.size():
		_cards[i].bind("%d  %s" % [i + 1, MODES[i]], DESCRIPTIONS[MODES[i]], i == highlighted)


## The mode chosen last time, or "" if none was.
func last_choice() -> String:
	var config := ConfigFile.new()
	if config.load(settings_file) != OK:
		return ""
	return String(config.get_value("mode_picker", "mode", ""))


## Takes a mode: remembers it, gives the mouse back, says which, and goes.
func choose(index: int) -> void:
	if index < 0 or index >= MODES.size() or _closing or is_queued_for_deletion():
		return
	var config := ConfigFile.new()
	config.set_value("mode_picker", "mode", MODES[index])
	config.save(settings_file)
	close_screen()
	chosen.emit(MODES[index])
	queue_free()


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
			_refresh_cards()
		KEY_DOWN, KEY_S, KEY_RIGHT:
			highlighted = posmod(highlighted + 1, MODES.size())
			_refresh_cards()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			choose(highlighted)
		_:
			return false
	return true
