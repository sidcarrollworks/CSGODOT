class_name TeamPicker
extends UiScreen

## The side you play, chosen as a match starts, as CS2's team select asks
## it: Terrorists on the left, Counter-Terrorists on the right, each with how
## many players and bots it has, a countdown at the top, and Auto Select in
## the bottom right, which is also what the countdown picks when it runs
## out. Laid out from Sid's screenshot of CS2's screen (2026-09-30).
##
## By mouse (either half, or Auto Select), or by 1 (T), 2 (CT) and 3 (Auto
## Select) while it is open; an open menu takes keys first
## (reference/binds.md). CS2's screen also offers Spectate, which waits for a
## mode that plays with no body of your own (free spectating, a thread of
## its own).
##
## PlayScene shows it after the mode is chosen and before the map loads, so
## the countdown is not held up by the load. It runs on the frame, before
## any simulation: what it decides is only which side the mode places you on.

## The side chosen: "T" or "CT". Auto Select says which side it chose.
signal chosen(side: String)

## How long the screen waits before it picks for you, in seconds: CS2's
## mp_force_pick_time, 15 by its default (from CS:GO's, not read from CS2's
## files here; inferred). Sid's screenshot shows the ring at 11 s.
const PICK_SECONDS := 15.0

## Bots on each side before you join, the "N Players - N Bots" lines.
var bots_per_side: int = 5
## Seconds left before Auto Select picks.
var seconds_left: float = PICK_SECONDS
## The half under the mouse: "T", "CT", "Auto", or "".
var hovered: String = ""

var _screen: _Screen


func _ready() -> void:
	super._ready()
	_screen = _Screen.new()
	_screen.picker = self
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)


func _process(delta: float) -> void:
	tick_down(delta)


## Counts the countdown down; at 0, Auto Select picks.
func tick_down(seconds: float) -> void:
	if is_queued_for_deletion():
		return
	var shown := ceili(seconds_left)
	seconds_left = maxf(0.0, seconds_left - seconds)
	if seconds_left <= 0.0:
		choose("Auto")
	elif ceili(seconds_left) != shown and _screen != null:
		_screen.queue_redraw()


## Takes a side ("T", "CT", or "Auto" for either): gives the mouse back,
## says which, and goes.
func choose(choice: String) -> void:
	if _closing or is_queued_for_deletion() or not choice in ["T", "CT", "Auto"]:
		return
	var side := auto_side() if choice == "Auto" else choice
	close_screen()
	chosen.emit(side)
	queue_free()


## The side Auto Select joins: the one with fewer humans, which before you
## join is neither, so either at random, as CS2 does with even teams.
static func auto_side() -> String:
	return MatchState.SIDES[randi_range(0, 1)]


## What a side's line under its name says: "0 Players - 5 Bots".
static func side_line(players: int, bots: int) -> String:
	return "%d %s - %d %s" % [players, "Player" if players == 1 else "Players", bots, "Bot" if bots == 1 else "Bots"]


## 1 T, 2 CT, 3 Auto Select. True where the key was the picker's.
func handle_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	match key.keycode:
		KEY_1, KEY_KP_1:
			choose("T")
		KEY_2, KEY_KP_2:
			choose("CT")
		KEY_3, KEY_KP_3:
			choose("Auto")
		_:
			return false
	return true


## The screen, on the 1920x1080 base size the canvas stretch scales: each
## side's half washed in its colour, its emblem, name and counts at the top,
## the countdown ring between them, Auto Select in the bottom right.
class _Screen:
	extends Control

	const TITLE_SIZE := 64
	const LINE_SIZE := 24
	const BUTTON_SIZE := 28
	const EMBLEM := 84.0
	const RING := 30.0

	var picker: TeamPicker

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_force_pass_scroll_events = false

	## Where Auto Select sits, bottom right.
	func auto_button() -> Rect2:
		return Rect2(size.x - 300.0, size.y - 92.0, 260.0, 56.0)

	func half(side: String) -> Rect2:
		var left := side == "T"
		return Rect2(0.0 if left else size.x * 0.5, 0.0, size.x * 0.5, size.y)

	func _choice_at(point: Vector2) -> String:
		if auto_button().has_point(point):
			return "Auto"
		return "T" if point.x < size.x * 0.5 else "CT"

	func _gui_input(event: InputEvent) -> void:
		var motion := event as InputEventMouseMotion
		if motion != null:
			var over := _choice_at(motion.position)
			if over != picker.hovered:
				picker.hovered = over
				queue_redraw()
			return
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picker.choose(_choice_at(button.position))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 1.0))
		for side: String in MatchState.SIDES:
			_draw_side(side)
		# The countdown: a ring that empties, the seconds inside.
		var centre := Vector2(size.x * 0.5, 72.0)
		draw_circle(centre, RING, Color(0, 0, 0, 0.5))
		draw_arc(centre, RING, 0.0, TAU, 64, Color(1, 1, 1, 0.2), 3.0, true)
		var share := picker.seconds_left / TeamPicker.PICK_SECONDS
		draw_arc(centre, RING, -PI * 0.5, -PI * 0.5 + TAU * share, 64, Color.WHITE, 3.0, true)
		HudStyle.draw_text(self, Vector2(centre.x, HudStyle.baseline_centred(centre.y, LINE_SIZE)),
			"%ds" % ceili(picker.seconds_left), LINE_SIZE, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		# Auto Select, bottom right.
		var auto := auto_button()
		var lit := picker.hovered == "Auto"
		if lit:
			draw_rect(auto, Color(1, 1, 1, 0.12))
		var arrow := auto.position + Vector2(30.0, auto.size.y * 0.5)
		draw_arc(arrow, 12.0, -PI * 0.3, PI * 1.5, 24, Color.WHITE, 3.0, true)
		HudStyle.draw_text(self, Vector2(auto.position.x + 56.0, HudStyle.baseline_centred(arrow.y, BUTTON_SIZE)),
			"3  AUTO SELECT", BUTTON_SIZE, Color.WHITE if lit else Color(1, 1, 1, 0.8))

	func _draw_side(side: String) -> void:
		var box := half(side)
		var colour := HudStyle.team_colour(side)
		var lit := picker.hovered == side
		# The side's wash, brighter under the mouse, as CS2 lights the agent
		# you point at.
		draw_rect(box, Color(colour, 0.22 if lit else 0.1))
		var middle := box.position.x + box.size.x * 0.5
		var emblem_centre := Vector2(middle, 84.0)
		draw_circle(emblem_centre, EMBLEM * 0.5, Color(colour, 0.9 if side == "T" else 0.25))
		draw_arc(emblem_centre, EMBLEM * 0.5, 0.0, TAU, 64, colour, 3.0, true)
		var emblem := HudStyle.icon("icons/ui/ct_logo_1c" if side == "CT" else "icons/ui/t_logo_1c")
		var inner := Rect2(emblem_centre - Vector2.ONE * EMBLEM * 0.3, Vector2.ONE * EMBLEM * 0.6)
		if emblem != null:
			HudStyle.draw_fitted(self, emblem, inner, Color.BLACK if side == "T" else colour)
		else:
			HudStyle.draw_text(self, Vector2(middle, HudStyle.baseline_centred(emblem_centre.y, 32)),
				side, 32, Color.BLACK if side == "T" else colour, HORIZONTAL_ALIGNMENT_CENTER)
		var title := "TERRORISTS" if side == "T" else "COUNTER-TERRORISTS"
		HudStyle.draw_text(self, Vector2(middle, 210.0), title, TITLE_SIZE,
			colour if lit else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, &"bold_tf", Color(0, 0, 0, 0.6))
		HudStyle.draw_text(self, Vector2(middle, 252.0), TeamPicker.side_line(0, picker.bots_per_side),
			LINE_SIZE, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
		HudStyle.draw_text(self, Vector2(middle, size.y * 0.6), "%d" % (1 if side == "T" else 2),
			96, Color(colour, 0.6 if lit else 0.25), HORIZONTAL_ALIGNMENT_CENTER)
