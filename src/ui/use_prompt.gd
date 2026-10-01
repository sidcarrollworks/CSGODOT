class_name UsePrompt
extends HudElement

## What E would do, under the crosshair while it applies: CS2's
## "[E] Take Bomb" (Panorama_HUD_botid_request_bomb in csgo_english.txt,
## its own yellow #e5da25) while you look at a bot teammate carrying the
## bomb within E's reach (C4.take_from_bot), or "[E] Pick up ..." / "[E]
## Swap for ..." for ground items. ItemDrops supplies the ground item
## E would take, including sight, owner delays and inventory limits.
##
## CS2's hudreticle.css .targetid: Stratum2 bold 22 px, centred in a
## 1040 x 74 box whose top is 580 at 1080p, additive. Sid's 2026-10-01
## screenshot puts its baseline about 60 px below the crosshair. The
## localization's action prefix is #6a6156, the item's name separate white.

const TAKE_BOMB := "[E] Take Bomb"
const PICK_UP_BOMB := "Press [E] to pick up bomb"
const PICK_UP_PREFIX := "[E] Pick up "
const SWAP_PREFIX := "[E] Swap for "
const BOMB_PREFIX := "Press [E] to pick up "
const PREFIX_COLOUR := Color("6a6156")
const TAKE_BOMB_COLOUR := Color("e5da25")
const BASELINE_UNDER_CROSSHAIR := 60.0
const SIZE := 22
const WIDTH := 1040.0
const HEIGHT := 74.0

var text: String = ""
var colour: Color = Color.WHITE


func _init() -> void:
	additive = true


func _ready() -> void:
	place(Vector2(0.5, 0.5), Rect2(-WIDTH * 0.5, BASELINE_UNDER_CROSSHAIR - SIZE, WIDTH, HEIGHT))


## Shows a line (none hides it) in a colour; redraws only on a change.
func say(line: String, line_colour: Color = Color.WHITE) -> void:
	text = line
	colour = line_colour
	show_state([line, line_colour])


func _draw() -> void:
	if text.is_empty():
		return
	var parts := parts_for(text)
	var font := HudStyle.face(&"bold")
	var prefix_width := font.get_string_size(parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var name_width := font.get_string_size(parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var left := (size.x - prefix_width - name_width) * 0.5
	HudStyle.draw_text(self, Vector2(left, float(SIZE)), parts[0], SIZE, PREFIX_COLOUR,
		HORIZONTAL_ALIGNMENT_LEFT, &"bold")
	HudStyle.draw_text(self, Vector2(left + prefix_width, float(SIZE)), parts[1], SIZE, colour,
		HORIZONTAL_ALIGNMENT_LEFT, &"bold")


## Keep the full line for state comparison, drawing its action and name
## separately as CS2's HTML localization does. Bot take-bomb stays yellow.
static func parts_for(line: String) -> PackedStringArray:
	for prefix: String in [PICK_UP_PREFIX, SWAP_PREFIX, BOMB_PREFIX]:
		if line.begins_with(prefix):
			return PackedStringArray([prefix, line.trim_prefix(prefix)])
	return PackedStringArray(["", line])


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
	var def := ItemRegistry.item(item_class)
	if def == null:
		return ""
	var swap := def.is_gun and (def.slot == ItemDef.Slot.PRIMARY or def.slot == ItemDef.Slot.PISTOL) \
		and you.inventory != null and you.inventory.item_in(def.slot, def.slot_position) != null
	return (SWAP_PREFIX if swap else PICK_UP_PREFIX) + def.name
