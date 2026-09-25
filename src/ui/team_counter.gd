class_name TeamCounter
extends HudElement

## The top of CS2's HUD in the middle (CSGOHudTeamCounter,
## hudteamcounter.xml and .css): the round's clock on a dark block, under
## it the counter-terrorists' score on the left and the terrorists' on the
## right, each with how many of them are alive; and a card for each player
## out from the middle on their side: a portrait in their colour, and for
## your own team their health, and in the round's down time (warmup,
## freeze time, the round's end) or while you are dead, their money and
## best gun.
##
## The counter-terrorists are always on the left, as they are in CS2
## (In_game_ui.webp, playing a terrorist; ScoreCT comes first in the
## layout). The clock turns red in a live round's last ten seconds; CS2
## decides that in code, so the ten seconds are the research's guess
## (round-hud-bots.md A2).
##
## GameHud gives it the match each frame; it redraws only when something it
## shows changed (HudElement).

## Sizes from hudteamcounter.css (the middle block 84 px, a score 42 px,
## the clock 28 px bold), the rest measured from In_game_ui.webp at 4K and
## halved to the base size.
const BLOCK_WIDTH := 84.0
const CLOCK_HEIGHT := 34.0
const SCORE_HEIGHT := 64.0
const CLOCK_SIZE := 26
const SCORE_SIZE := 26
const ALIVE_SIZE := 14
const CARD_WIDTH := 54.0
const CARD_GAP := 3.0
const PORTRAIT := 50.0
const TOP := 2.0
## The five cards a side has room for, at most.
const MOST_CARDS := 5
const RED_SECONDS := 10.0
const CLOCK_BACK := Color(0.07, 0.10, 0.13, 0.92)
const COLUMN_TOP := Color(0.20, 0.27, 0.34, 0.85)
const COLUMN_BOTTOM := Color(0.20, 0.27, 0.34, 0.0)
const CLOCK_RED := Color(1.0, 0.27, 0.27)

## One player's card, as the frame's state gives it.
class Card:
	var name: String
	var bot: bool
	var alive: bool
	var health: int
	var colour: Color
	var friendly: bool
	var money: int
	var weapon: String


var clock: String = ""
var clock_red: bool = false
var scores := {"T": 0, "CT": 0}
var alive := {"T": 0, "CT": 0}
## Cards by side, nearest the middle first.
var cards := {"T": [] as Array[Card], "CT": [] as Array[Card]}
## Whether your team's cards show money and guns now.
var show_equipment: bool = false


func _ready() -> void:
	var width := BLOCK_WIDTH + 2.0 * MOST_CARDS * (CARD_WIDTH + CARD_GAP) + 8.0
	place(Vector2(0.5, 0.0), Rect2(-width * 0.5, 0.0, width, 160.0))


## Reads the match for `you`, and redraws if anything shown changed.
func show_match(state: MatchState, you: PlayerSim, economy: Economy, now_usec: int) -> void:
	var mine := you.team if you != null else "T"
	var seconds := state.seconds_left(now_usec)
	var live := state.phase == MatchState.Phase.LIVE
	clock = "" if state.phase == MatchState.Phase.OVER else GameHud.clock_text(seconds)
	clock_red = live and seconds <= RED_SECONDS
	show_equipment = state.phase != MatchState.Phase.LIVE or (you != null and not you.alive)
	var signature: Array = [clock, clock_red, show_equipment, mine]
	var teammate := 0
	for side: String in MatchState.SIDES:
		scores[side] = state.score(side)
		alive[side] = state.alive_on(side)
		signature.append_array([scores[side], alive[side]])
		var list: Array[Card] = []
		for player in state.players:
			if player.team != side or list.size() >= MOST_CARDS:
				continue
			var card := Card.new()
			card.name = str(player.name)
			card.bot = player is Bot
			card.alive = player.alive
			card.friendly = side == mine
			card.health = roundi(player.hit_target.health) if player.hit_target != null and player.alive else 0
			if card.friendly:
				card.colour = HudStyle.TEAMMATE_COLOURS[teammate % HudStyle.TEAMMATE_COLOURS.size()]
				teammate += 1
			else:
				card.colour = HudStyle.team_colour(side)
			card.money = economy.money(player.userid) if economy != null else -1
			card.weapon = player.weapon.data.item_class if player.weapon != null and player.alive else ""
			list.append(card)
			signature.append_array([card.name, card.alive, card.health, card.money, card.weapon, card.friendly])
		cards[side] = list
	show_state(signature)


func _draw() -> void:
	var middle := size.x * 0.5
	var block := Rect2(middle - BLOCK_WIDTH * 0.5, TOP, BLOCK_WIDTH, CLOCK_HEIGHT)
	# The clock's block, dark, the scores' columns fading down from it.
	draw_rect(block, CLOCK_BACK)
	if not clock.is_empty():
		HudStyle.draw_text(self, Vector2(middle, block.get_center().y + HudStyle.cap_height(CLOCK_SIZE) * 0.5),
			clock, CLOCK_SIZE, CLOCK_RED if clock_red else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var column_width := BLOCK_WIDTH * 0.5 - 1.0
	for i in 2:
		var side := "CT" if i == 0 else "T"
		var column := Rect2(block.position.x + i * (column_width + 2.0), block.end.y + 2.0, column_width, SCORE_HEIGHT)
		_draw_fade(column, COLUMN_TOP, COLUMN_BOTTOM)
		var colour := HudStyle.team_colour(side)
		HudStyle.draw_text(self, Vector2(column.get_center().x, column.position.y + 8.0 + HudStyle.cap_height(SCORE_SIZE)),
			str(scores[side]), SCORE_SIZE, colour, HORIZONTAL_ALIGNMENT_CENTER)
		var alive_y := column.position.y + 48.0
		_draw_person(Vector2(column.get_center().x - 7.0, alive_y - 5.0), colour)
		HudStyle.draw_text(self, Vector2(column.get_center().x + 1.0, alive_y), str(alive[side]), ALIVE_SIZE,
			colour)
		# The cards, out from the middle: leftwards for the left column.
		var list: Array[Card] = cards[side]
		for n in list.size():
			var x := block.end.x + 3.0 + n * (CARD_WIDTH + CARD_GAP) if i == 1 \
				else block.position.x - 3.0 - (n + 1) * (CARD_WIDTH + CARD_GAP) + CARD_GAP
			_draw_card(Rect2(x, TOP, CARD_WIDTH, 150.0), list[n])


func _draw_card(box: Rect2, card: Card) -> void:
	var extended := card.friendly and show_equipment
	_draw_fade(Rect2(box.position, Vector2(box.size.x, 96.0 if extended else 76.0)), COLUMN_TOP, COLUMN_BOTTOM)
	var portrait := Rect2(box.position + Vector2((box.size.x - PORTRAIT) * 0.5, 2.0), Vector2.ONE * PORTRAIT)
	var dim := 1.0 if card.alive else 0.35
	draw_rect(portrait, Color(0.05, 0.07, 0.09, 0.9))
	var icon := HudStyle.icon("hud/teamcounter/teamcounter_botavatar") if card.bot else null
	if icon != null:
		HudStyle.draw_fitted(self, icon, portrait.grow(-4.0), Color(card.colour, dim))
	else:
		_draw_silhouette(portrait, Color(card.colour, dim))
	draw_rect(portrait.grow(-1.0), Color(card.colour, dim), false, 2.0)
	if not card.alive:
		_draw_skull(portrait.get_center(), Color(1, 1, 1, 0.85))
	var y := portrait.end.y + 4.0
	if card.friendly and card.alive:
		# Health: a white bar, the number on it in black.
		var bar := Rect2(Vector2(portrait.position.x, y), Vector2(PORTRAIT, 13.0))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(card.health / 100.0, 0.0, 1.0), bar.size.y)),
			Color.WHITE if card.health > 20 else HudStyle.DAMAGE_RED)
		HudStyle.draw_text(self, Vector2(bar.position.x + 3.0, bar.end.y - 2.0), str(card.health), 12, Color.BLACK)
	y += 16.0
	if not extended:
		return
	if card.money >= 0:
		HudStyle.draw_text(self, Vector2(box.get_center().x, y + 14.0), GameHud.money_text(card.money), 14,
			Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if not card.weapon.is_empty():
		var gun := HudStyle.item_icon(card.weapon)
		var gun_box := Rect2(Vector2(box.position.x + 4.0, y + 20.0), Vector2(box.size.x - 8.0, 16.0))
		if gun != null:
			HudStyle.draw_fitted(self, gun, gun_box, Color.WHITE)
		else:
			var label := card.weapon.trim_prefix("weapon_")
			if ItemRegistry.has(card.weapon):
				label = ItemRegistry.item(card.weapon).name
			HudStyle.draw_text(self, Vector2(gun_box.get_center().x, gun_box.end.y - 3.0), label, 11,
				Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)


## A box fading from one colour at the top to another at the bottom.
func _draw_fade(box: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Head and shoulders, where there is no portrait.
func _draw_silhouette(box: Rect2, colour: Color) -> void:
	var c := box.get_center()
	var s := box.size.x / 50.0
	draw_circle(c + Vector2(0, -6) * s, 9.0 * s, colour)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-17, 22) * s, c + Vector2(-14, 9) * s, c + Vector2(-6, 5) * s,
		c + Vector2(6, 5) * s, c + Vector2(14, 9) * s, c + Vector2(17, 22) * s,
	]), colour)


## The small person the alive counts stand beside.
func _draw_person(centre: Vector2, colour: Color) -> void:
	draw_circle(centre + Vector2(0, -3), 2.5, colour)
	draw_rect(Rect2(centre + Vector2(-3, 0), Vector2(6, 6)), colour)


## A skull on a dead player's card.
func _draw_skull(centre: Vector2, colour: Color) -> void:
	var skull := HudStyle.icon("hud/teamcounter/teamcounter_skull_png")
	if skull != null:
		HudStyle.draw_fitted(self, skull, Rect2(centre - Vector2(12, 12), Vector2(24, 24)), colour)
		return
	draw_circle(centre + Vector2(0, -2), 9.0, colour)
	draw_rect(Rect2(centre + Vector2(-5, 4), Vector2(10, 6)), colour)
	var hole := Color(0.05, 0.07, 0.09)
	draw_circle(centre + Vector2(-3.5, -2), 2.5, hole)
	draw_circle(centre + Vector2(3.5, -2), 2.5, hole)
