class_name TeamCounter
extends HudElement

## The top of CS2's HUD in the middle (CSGOHudTeamCounter; CS2's
## panorama/layout/hud/hudteamcounter.xml with styles/hud/hudteamcounter.css
## and hudteamcounter-equipmentinfo.css): the round's clock on a dark block,
## under it the two scores and how many are alive on each side, and out from
## the block a card for each player on their side.
##
## The counter-terrorists are always on the left: CS2's styles colour the
## left side's score, alive count and cards in color-CT and the right side's
## in color-T whoever you play (hudteamcounter.css .TeamScoreL, .TeamScoreR,
## .team__large_container--left and --right), and its screenshot, playing a
## terrorist, has the terrorists on the right.
##
## The block is CS2's own shape (masks/score-time-mask.vsvg: the clock's
## rectangle, then a column under each score fading to nothing) cut from
## 94 % black (teamcounter-bg-clock), with the faint dot pattern; the clock,
## scores and counts add their light (`additive`). The clock turns red in a
## live round's last ten seconds; CS2 decides when in its code (the class is
## teamcounter_red_timer), so the ten seconds are the research's guess
## (reference/research/round-hud-bots.md A2).
##
## A card (AvatarLargeSnippet) is a 54 px portrait, bordered in the player's
## colour for your team and the team's colour for the other (bots show CS2's
## bot portrait, players a plain head and shoulders), with your team's health
## in a bar under it; dead, it fades to a fifth under a skull. In the round's
## down time (warmup, freeze time, its end), or while you are dead, your
## team's cards stretch down over a darkening column with each one's money
## and best gun (snippet-equipment-info). Whoever on your team carries the
## bomb has CS2's C4 icon on their card, washed yellow 255,255,95, at all
## times (round-hud-bots.md A3); the other side's cards never show it.
##
## GameHud gives it the match each frame; it redraws only when something it
## shows changed (HudElement).

## The block: 84 wide (ScoreAndTimeWidth), its dark 98 % of that and 106
## tall (#ScoreAndTimeAndBomb .equipinfo__bg-container); on CS2's screenshot
## it starts 4 px down. The mask's parts, in its 106 by 130 drawing: the
## clock's rectangle 0 to 39.92 down, the columns from 41.97, each 52 wide
## with 2 between.
const TOP := 4.0
const BLOCK_WIDTH := 84.0
const DARK_WIDTH := 84.0 * 0.98
const DARK_HEIGHT := 106.0
const CLOCK_BOTTOM := 39.9213 / 130.0 * DARK_HEIGHT
const COLUMNS_TOP := 41.9685 / 130.0 * DARK_HEIGHT
const COLUMN_WIDTH := 52.0 / 106.0 * DARK_WIDTH
const DARK := Color(0, 0, 0, 240.0 / 255.0)
## The dot pattern: 360 px, 2.5 % (background-img-opacity .025).
const DOTS_SIZE := 360.0
const DOTS_OPACITY := 0.025
## The clock (28 px, bold TF, white, 82 wide), the scores (28 px, bold TF,
## 42 wide each), and the players alive (Stratum2 Bold 16 px after a 10 px
## person, 10 px in from the block's left, 12 in from its right). The
## baselines are where CS2's screenshot has them; the clock's, empty there,
## is the css's with the same 2 px the scores sit below theirs.
const CLOCK_SIZE := 28
const CLOCK_BASELINE := 30.3
const SCORE_SIZE := 28
const SCORE_BASELINE := 64.0
const ALIVE_SIZE := 16
const ALIVE_BASELINE := 88.6
const ALIVE_ICON := 10.0
const ALIVE_INSET_LEFT := 10.0
const ALIVE_INSET_RIGHT := 12.0
const RED_SECONDS := 10.0
const CLOCK_RED := Color(1, 0, 0)
## A card: the portrait 54 px square with a 2.5 px border, starting 2.5 px
## out from the block (CS2's screenshot), a card every 56 px (the health
## bar's 52 with its 2 px margins); the health bar 52 wide, 14 tall with its
## number in the down time and 4 otherwise, 2 px under the portrait; the
## column 176 tall (54 once dead is 101); the money 17 px centred, the gun
## in a 16 px row, then the grenades' and armour's rows
## (hudteamcounter-equipmentinfo.css).
const CARD := 54.0
const CARD_GAP := 2.5
const CARD_PITCH := 56.0
const BORDER := 2.5
const HEALTH_BAR := Rect2(1.0, CARD + 2.0, 52.0, 14.0)
const HEALTH_BAR_THIN := 4.0
const COLUMN_HEIGHT := 176.0
const MONEY_SIZE := 17
const MONEY_BASELINE := 103.1
const GUN_ROW := Rect2(2.0, 108.0, 50.0, 16.0)
const NADE_ROW_TOP := 128.0
const ROW := 16.0
const NADE_WIDTH := 13.5
## The five cards a side has room for, at most.
const MOST_CARDS := 5
## The portraits' grey (.AvatarL__Internal), a bot's portrait's wash
## (.Avatar__Bot--T and --CT), a player's default portrait (.AvatarImageT__Color
## and --CT).
const PORTRAIT_GREY := Color8(127, 127, 127)
const BOT_WASH := {"T": Color8(255, 241, 207, 221), "CT": Color8(208, 240, 255, 221)}
const DEFAULT_PORTRAIT := {"T": Color8(145, 109, 65), "CT": Color8(114, 137, 163)}
## CS2's top-bottom-fade-4 mask, under the column of a card's equipment:
## opaque at the top, fading in its curve to nothing at the bottom (the
## mask's image read at eighths).
const FADE_4 := [1.0, 0.953, 0.886, 0.804, 0.702, 0.58, 0.443, 0.141, 0.0]
## The carrier's C4 icon: CS2's wash (.Avatar__C4), and where on the card.
## The research has the wash, not the place, so the lower right corner of
## the portrait, 20 px, is a guess to set beside CS2 (playtest issue 18).
const C4_WASH := Color8(255, 255, 95)
const C4_BOX := Rect2(CARD - 22.0, CARD - 16.0, 20.0, 14.0)

## One player's card, as the frame's state gives it.
class Card:
	var side: String
	var name: String
	var bot: bool
	var alive: bool
	var health: int
	var colour: Color
	var friendly: bool
	var money: int
	var weapon: String
	var grenades: PackedStringArray
	var armour: int
	var helmet: bool
	## Carrying the bomb; only ever true on your own team's cards.
	var bomb: bool


var clock: String = ""
var clock_red: bool = false
var scores := {"T": 0, "CT": 0}
var alive := {"T": 0, "CT": 0}
## Cards by side, nearest the block first.
var cards := {"T": [] as Array[Card], "CT": [] as Array[Card]}
## Whether your team's cards show money and guns now.
var show_equipment: bool = false


func _init() -> void:
	super()
	additive = true


func _ready() -> void:
	var width := BLOCK_WIDTH + 2.0 * (CARD_GAP + MOST_CARDS * CARD_PITCH) + 8.0
	place(Vector2(0.5, 0.0), Rect2(-width * 0.5, 0.0, width, TOP + COLUMN_HEIGHT + 8.0))


## Reads the match for `you`, and redraws if anything shown changed. `bomb`
## says who carries it, where there is one.
func show_match(state: MatchState, you: PlayerSim, economy: Economy, now_usec: int, bomb: C4 = null) -> void:
	var mine := you.team if you != null else "T"
	var seconds := state.seconds_left(now_usec)
	var live := state.phase == MatchState.Phase.LIVE
	clock = "" if state.phase == MatchState.Phase.OVER or is_inf(seconds) else GameHud.clock_text(seconds)
	clock_red = live and seconds <= RED_SECONDS
	show_equipment = not live or (you != null and not you.alive)
	var signature: Array = [clock, clock_red, show_equipment, mine]
	var carrier := bomb.carrier if bomb != null and bomb.state == C4.State.CARRIED else C4.NOBODY
	for side: String in MatchState.SIDES:
		scores[side] = state.score(side)
		alive[side] = state.alive_on(side)
		signature.append_array([scores[side], alive[side]])
		var list: Array[Card] = []
		for player in state.players:
			if player.team != side or list.size() >= MOST_CARDS:
				continue
			var card := Card.new()
			card.side = side
			card.name = str(player.name)
			card.bot = player is Bot
			card.alive = player.alive
			card.friendly = side == mine
			card.health = roundi(player.hit_target.health) if player.hit_target != null and player.alive else 0
			card.colour = GameHud.player_colour(state, player) if card.friendly else HudStyle.counter_colour(side)
			card.money = economy.money(player.userid) if economy != null else -1
			card.weapon = GameHud.best_weapon(player)
			card.grenades = GameHud.grenades_of(player)
			card.armour = roundi(player.hit_target.armor) if player.hit_target != null and player.alive else 0
			card.helmet = player.hit_target != null and player.hit_target.helmet
			card.bomb = card.friendly and player.alive and carrier != C4.NOBODY and player.userid == carrier
			list.append(card)
			signature.append_array([card.name, card.alive, card.health, card.money, card.weapon, card.friendly,
				card.colour, card.grenades, card.armour, card.helmet, card.bomb])
		cards[side] = list
	show_state(signature)


## The block's left edge, in this element's coordinates.
func _block_left() -> float:
	return size.x * 0.5 - BLOCK_WIDTH * 0.5


## Where the cards' blur is: your team's side in the down time, else
## nowhere.
func _blur_rect() -> Rect2:
	if not show_equipment:
		return Rect2()
	var area := Rect2()
	for i in 2:
		var list: Array[Card] = cards["CT" if i == 0 else "T"]
		for n in list.size():
			if list[n].friendly:
				var column := Rect2(_card_left(i == 0, n), TOP, CARD, COLUMN_HEIGHT)
				area = column if not area.has_area() else area.merge(column)
	return area


## The world behind your team's cards' columns in the down time, blurred
## and faded out downwards as their dark is (.equipinfo__blurbg).
func _draw_blur(on: CanvasItem) -> void:
	if not show_equipment:
		return
	for i in 2:
		var side := "CT" if i == 0 else "T"
		var list: Array[Card] = cards[side]
		for n in list.size():
			var card := list[n]
			if card.friendly:
				_draw_masked_fade(on, Rect2(_card_left(i == 0, n), TOP, CARD, COLUMN_HEIGHT if card.alive else 101.0),
					Color.WHITE)


## The dark block and the cards, with the ordinary blend, under the numbers.
func _draw_under(on: CanvasItem) -> void:
	var dark := Rect2(size.x * 0.5 - DARK_WIDTH * 0.5, TOP, DARK_WIDTH, DARK_HEIGHT)
	var clock_box := Rect2(dark.position, Vector2(dark.size.x, CLOCK_BOTTOM))
	on.draw_rect(clock_box, DARK)
	_draw_dots(on, clock_box, DOTS_OPACITY)
	for i in 2:
		var column := Rect2(dark.position.x + i * (dark.size.x - COLUMN_WIDTH), TOP + COLUMNS_TOP,
			COLUMN_WIDTH, DARK_HEIGHT - COLUMNS_TOP)
		_draw_fade(on, column, DARK, Color(DARK, 0.0))
	for i in 2:
		var side := "CT" if i == 0 else "T"
		var list: Array[Card] = cards[side]
		for n in list.size():
			_draw_card(on, _card_left(i == 0, n), list[n])


## The clock, scores and players alive, adding their light.
func _draw() -> void:
	var middle := size.x * 0.5
	var left := _block_left()
	if not clock.is_empty():
		HudStyle.draw_text(self, Vector2(middle, CLOCK_BASELINE), clock, CLOCK_SIZE,
			CLOCK_RED if clock_red else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var dark_left := middle - DARK_WIDTH * 0.5
	for i in 2:
		var side := "CT" if i == 0 else "T"
		var colour := HudStyle.counter_colour(side)
		var column_middle := dark_left + COLUMN_WIDTH * 0.5 + i * (DARK_WIDTH - COLUMN_WIDTH)
		HudStyle.draw_text(self, Vector2(column_middle, SCORE_BASELINE), str(scores[side]), SCORE_SIZE, colour,
			HORIZONTAL_ALIGNMENT_CENTER)
		# The person and the count: from the block's left for the left side,
		# ending at its right for the right side.
		var count := str(alive[side])
		var count_width := HudStyle.face(&"bold").get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, ALIVE_SIZE).x
		var icon_left := left + ALIVE_INSET_LEFT if i == 0 else left + BLOCK_WIDTH - ALIVE_INSET_RIGHT - count_width - ALIVE_ICON
		var icon_box := Rect2(icon_left, ALIVE_BASELINE - 10.0, ALIVE_ICON, ALIVE_ICON)
		var person := HudStyle.icon("icons/person")
		if person != null:
			HudStyle.draw_fitted(self, person, icon_box, colour)
		else:
			draw_circle(icon_box.get_center() + Vector2(0, -3), 2.5, colour)
			draw_rect(Rect2(icon_box.get_center() + Vector2(-2.5, 0), Vector2(5, 5)), colour)
		HudStyle.draw_text(self, Vector2(icon_box.end.x, ALIVE_BASELINE), count, ALIVE_SIZE, colour,
			HORIZONTAL_ALIGNMENT_LEFT, &"bold")


## Where the `n`th card from the block starts, on the left side or the
## right.
func _card_left(left_side: bool, n: int) -> float:
	var block := _block_left()
	if left_side:
		return block - CARD_GAP - CARD - n * CARD_PITCH
	return block + BLOCK_WIDTH + CARD_GAP + n * CARD_PITCH


func _draw_card(on: CanvasItem, x: float, card: Card) -> void:
	var extended := card.friendly and show_equipment
	var portrait := Rect2(x, TOP, CARD, CARD)
	if extended:
		# The column the equipment sits on: black, faded out downwards by
		# CS2's top-bottom-fade-4 mask.
		var height := COLUMN_HEIGHT if card.alive else 101.0
		_draw_masked_fade(on, Rect2(x, TOP, CARD, height))
	var inside := portrait.grow(-BORDER)
	var faded := 1.0 if card.alive else 0.2
	if card.bot:
		on.draw_rect(inside, Color(PORTRAIT_GREY, faded))
		var bot := HudStyle.icon("hud/teamcounter/teamcounter_botavatar")
		var wash: Color = BOT_WASH[card.side]
		var bot_box := Rect2(Vector2(x + (CARD - 42.0) * 0.5, TOP + 9.0), Vector2(42, 42))
		if bot != null:
			HudStyle.draw_fitted(on, bot, bot_box, Color(wash, wash.a * faded) if card.alive else Color(0.8, 0.8, 0.8, 0.2))
		else:
			_draw_silhouette(on, inside, Color(1, 1, 1, 0.6 * faded))
	else:
		var base: Color = DEFAULT_PORTRAIT[card.side]
		on.draw_rect(inside, Color(base, faded) if card.alive else Color(Color(0.45, 0.45, 0.45), faded))
		_draw_silhouette(on, inside, Color(1, 1, 1, 0.45 * faded))
	# The border: the player's or the team's colour, black once dead.
	on.draw_rect(portrait.grow(-BORDER * 0.5), card.colour if card.alive else Color.BLACK, false, BORDER)
	if not card.alive:
		var skull := HudStyle.icon("icons/ui/elimination")
		if skull != null:
			HudStyle.draw_fitted(on, skull, portrait.grow(-4.0), Color(1, 1, 1, 0.5))
		return
	if not card.friendly:
		return
	if card.bomb:
		_draw_c4(on, Rect2(portrait.position + C4_BOX.position, C4_BOX.size))
	# Health: red where it is gone, fading to nothing at the right, a white
	# fill (the bar adds ten times its light, which is white), and in the down
	# time its number in black.
	var bar := HEALTH_BAR
	bar.position += Vector2(x, TOP)
	if not extended:
		bar.size.y = HEALTH_BAR_THIN
	var fill := bar.size.x * clampf(card.health / 100.0, 0.0, 1.0)
	if fill < bar.size.x:
		_draw_fade_across(on, Rect2(bar.position.x + fill, bar.position.y, bar.size.x - fill, bar.size.y), bar)
	on.draw_rect(Rect2(bar.position, Vector2(fill, bar.size.y)), Color.WHITE)
	if not extended:
		return
	HudStyle.draw_text(on, Vector2(bar.position.x + 1.0, bar.end.y - 2.5), str(card.health), 14, Color.BLACK,
		HORIZONTAL_ALIGNMENT_LEFT, &"mono_bold")
	var shadow := Color(0, 0, 0, 1)
	if card.money >= 0:
		HudStyle.draw_text(on, Vector2(x + CARD * 0.5, MONEY_BASELINE), GameHud.money_text(card.money), MONEY_SIZE,
			Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, &"mono_bold", shadow, 1)
	if not card.weapon.is_empty():
		var gun_box := GUN_ROW
		gun_box.position.x += x
		var gun := HudStyle.item_icon(card.weapon)
		if gun != null:
			_draw_shadowed(on, gun, gun_box)
		else:
			var label := card.weapon.trim_prefix("weapon_")
			if ItemRegistry.has(card.weapon):
				label = ItemRegistry.item(card.weapon).name
			HudStyle.draw_text(on, Vector2(gun_box.get_center().x, gun_box.end.y - 3.0), label, 11, Color.WHITE,
				HORIZONTAL_ALIGNMENT_CENTER, &"medium", shadow, 1)
	# The grenades, right to left from the middle (flow-children: left).
	var nades := card.grenades
	var row_width := nades.size() * NADE_WIDTH
	for n in nades.size():
		var icon := HudStyle.item_icon(nades[n])
		if icon == null:
			continue
		var box := Rect2(x + CARD * 0.5 + row_width * 0.5 - (n + 1) * NADE_WIDTH, NADE_ROW_TOP, NADE_WIDTH, ROW)
		_draw_shadowed(on, icon, box)
	if card.armour > 0:
		var armour := HudStyle.icon("hud/teamcounter/armor_helmet" if card.helmet else "hud/teamcounter/armor")
		if armour != null:
			var top := NADE_ROW_TOP + (ROW + 4.0 if nades.size() > 0 else 0.0)
			_draw_shadowed(on, armour, Rect2(x + (CARD - 20.0) * 0.5, top, 20.0, ROW))


## The carrier's mark: CS2's C4 icon washed yellow, or where it was not
## extracted (scripts/extract_assets.sh hud), a yellow block lettered C4.
func _draw_c4(on: CanvasItem, box: Rect2) -> void:
	var c4 := HudStyle.item_icon("weapon_c4")
	if c4 != null:
		HudStyle.draw_fitted(on, c4, Rect2(box.position + Vector2.ONE, box.size), Color(0, 0, 0, 0.56))
		HudStyle.draw_fitted(on, c4, box, C4_WASH)
		return
	on.draw_rect(box, Color(C4_WASH, 0.9))
	HudStyle.draw_text(on, Vector2(box.get_center().x, box.end.y - 3.0), "C4", 10, Color.BLACK,
		HORIZONTAL_ALIGNMENT_CENTER, &"bold")


## An icon in white with CS2's 1 px dark shadow (img-shadow 1px 1px 1px).
func _draw_shadowed(on: CanvasItem, texture: Texture2D, box: Rect2) -> void:
	HudStyle.draw_fitted(on, texture, Rect2(box.position + Vector2.ONE, box.size), Color(0, 0, 0, 0.56))
	HudStyle.draw_fitted(on, texture, box, Color.WHITE)


## A box fading from `top` at the top to `bottom` at the bottom.
func _draw_fade(on: CanvasItem, box: Rect2, top: Color, bottom: Color) -> void:
	on.draw_polygon(
		PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Black under CS2's top-bottom-fade-4 mask (FADE_4).
func _draw_masked_fade(on: CanvasItem, box: Rect2, colour: Color = Color.BLACK) -> void:
	var step := box.size.y / (FADE_4.size() - 1)
	for i in FADE_4.size() - 1:
		_draw_fade(on, Rect2(box.position.x, box.position.y + i * step, box.size.x, step),
			Color(colour, FADE_4[i]), Color(colour, FADE_4[i + 1]))


## The health bar's red behind what is gone: solid to the bar's middle,
## fading to nothing at its right end (.healthbar__bg).
func _draw_fade_across(on: CanvasItem, part: Rect2, bar: Rect2) -> void:
	var middle := bar.position.x + bar.size.x * 0.5
	var stops := [part.position.x] if part.position.x >= middle else [part.position.x, middle]
	stops.append(part.end.x)
	for i in stops.size() - 1:
		var a: float = stops[i]
		var b: float = stops[i + 1]
		var ca := Color(1, 0, 0, 1.0 if a <= middle else lerpf(1.0, 0.0, (a - middle) / (bar.end.x - middle)))
		var cb := Color(1, 0, 0, 1.0 if b <= middle else lerpf(1.0, 0.0, (b - middle) / (bar.end.x - middle)))
		on.draw_polygon(PackedVector2Array([Vector2(a, part.position.y), Vector2(b, part.position.y),
			Vector2(b, part.end.y), Vector2(a, part.end.y)]), PackedColorArray([ca, cb, cb, ca]))


## CS2's dot pattern over `box`, at `opacity`.
func _draw_dots(on: CanvasItem, box: Rect2, opacity: float) -> void:
	var dots := HudStyle.icon("backgrounds/bluedots_large_png")
	if dots == null:
		return
	var scale := dots.get_size().x / DOTS_SIZE
	on.draw_texture_rect_region(dots, box, Rect2(Vector2.ZERO, box.size * scale), Color(1, 1, 1, opacity))


## Head and shoulders, where there is no portrait.
func _draw_silhouette(on: CanvasItem, box: Rect2, colour: Color) -> void:
	var c := box.get_center()
	var s := box.size.x / 50.0
	on.draw_circle(c + Vector2(0, -6) * s, 9.0 * s, colour)
	on.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-17, 22) * s, c + Vector2(-14, 9) * s, c + Vector2(-6, 5) * s,
		c + Vector2(6, 5) * s, c + Vector2(14, 9) * s, c + Vector2(17, 22) * s,
	]), colour)
