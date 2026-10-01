class_name UsePrompt
extends HudElement

## What E would do, under the crosshair while it applies: CS2's
## "[E] Take Bomb" (Panorama_HUD_botid_request_bomb in csgo_english.txt,
## its own yellow #e5da25) while you look at a bot teammate carrying the
## bomb within E's reach (C4.take_from_bot), or "Press [E] to pick up ..."
## for a dropped bomb, gun or grenade. ItemDrops supplies the ground item
## E would take, including sight, owner delays and inventory limits.
##
## Where and how big: centred under the crosshair, the baseline 106 px under
## it at 1080p and the text 30 px, estimated from Sid's CS2 screenshot of
## the pickup prompt (playtest-2026-09-25.md issue 18); set beside CS2.

const TAKE_BOMB := "[E] Take Bomb"
const PICK_UP_BOMB := "Press [E] to pick up bomb"
const TAKE_BOMB_COLOUR := Color("e5da25")
const BASELINE_UNDER_CROSSHAIR := 106.0
const SIZE := 30
const WIDTH := 600.0

var text: String = ""
var colour: Color = Color.WHITE


func _ready() -> void:
	place(Vector2(0.5, 0.5), Rect2(-WIDTH * 0.5, BASELINE_UNDER_CROSSHAIR - SIZE, WIDTH, SIZE * 1.5))


## Shows a line (none hides it) in a colour; redraws only on a change.
func say(line: String, line_colour: Color = Color.WHITE) -> void:
	text = line
	colour = line_colour
	show_state([line, line_colour])


func _draw() -> void:
	if text.is_empty():
		return
	HudStyle.draw_text(self, Vector2(size.x * 0.5, float(SIZE)), text, SIZE, colour,
		HORIZONTAL_ALIGNMENT_CENTER, &"bold", Color(0, 0, 0, 0.8), 2)


## What E would take now. The bomb has priority over a ground item; its
## reach is pure geometry, while item_class was selected on a physics frame.
static func line_for(you: PlayerSim, bomb: C4, carrier: PlayerSim,
	item_class: String = "", now_usec: int = -1) -> String:
	if you == null or not you.alive:
		return ""
	var actor := C4.Actor.of_player(you, you.userid)
	var carried_by := C4.Actor.of_player(carrier, carrier.userid) if carrier != null else null
	if bomb != null and bomb.claims_use(actor, carried_by):
		if bomb.state == C4.State.CARRIED:
			return TAKE_BOMB
		if bomb.state == C4.State.DROPPED:
			var at := SimClock.now_usec() if now_usec < 0 else now_usec
			if actor.id != bomb.dropped_by or at >= bomb.redrop_usec:
				return PICK_UP_BOMB
		return ""
	return "Press [E] to pick up %s" % ItemRegistry.item(item_class).name if ItemRegistry.has(item_class) else ""
