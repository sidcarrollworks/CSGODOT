class_name Scoreboard
extends HudElement

## CS2's scoreboard, over the middle of the screen while Tab is held
## (+showscores): the match and map with the time on it, then the team now
## on the counter-terrorist side, the round timeline, and the terrorists.
## Built to CS2's own layout and styles (panorama/layout/scoreboard.xml,
## its snippet_scoreboard-classic__row--comp; styles/scoreboard.css;
## scripts/scoreboard.js; reference/research/round-hud-bots.md A4) and
## Sid's CS2 screenshot of 2026-09-30.
##
## A team: its score in 70 px over its name and "Alive: 4/5", and a row a
## player, in competitive's order (scoreboard.js sortOrder_tmm: the most
## damage first, then kills, MVPs, assists, the fewest deaths, who joined
## first). A row: a skull when dead (the C4 or the kit on your own team's
## carriers), the bot's mark or the ping, the portrait in the player's
## colour, the name, then the first of CS2's two sets of numbers (Money,
## Kills, Deaths, Assists, HS%) and DMG. Money is shown only for your own
## team, as the server sends CS2's scoreboard -1 for the rest. Your row is
## lit in your side's colour; the dead are greyed.
##
## The timeline between them: each half's score, a column per round of the
## half's period with how the round was won on the winning team's side
## (scoreboard.js's dictRoundResultImage: elimination, the bomb, the kit,
## the clock) and every fifth numbered, the trophy on the round each team
## would clinch the match in if it won every round till then, and the loss
## bonus's four dashes, lit for each loss in a row.
##
## Everything it shows the server has: MatchState (the score, the rounds'
## history, the players, who is alive), MatchStats (the numbers) and the
## Economy (money, the loss ladder). It only reads them.
##
## Left out: the flair and rank cells, the second set of numbers (MVPs,
## utility damage, enemies flashed, K/D, ADR; CS2 cycles to it with the
## mouse), the music kit line, the mouse (MOUSE2 enables CS2's cursor for
## the report and commend buttons), the survivors under each round (CS2
## shows them only under the mouse), the overtime's own score column and
## the spectators.

## What CS2 names the match and the map on the first line
## (SFUI_GameModeCompetitive, SFUI_Map_<name>).
const MODE_TITLE := "Competitive"
const MAP_TITLES := {"de_dust2": "Dust II", "de_mirage": "Mirage", "de_inferno": "Inferno",
	"de_nuke": "Nuke", "de_overpass": "Overpass", "de_ancient": "Ancient", "de_anubis": "Anubis",
	"de_vertigo": "Vertigo", "de_train": "Train"}

## The panel (.sb-main): 20 px of padding round what it holds but under
## it, 30 px below the screen's middle, black at 0.88 with CS2's dots at
## 0.015, corners of 5.
const PAD := 20.0
const DROP := 30.0
const BACKGROUND := Color(0, 0, 0, 0.88)
const DOTS_OPACITY := 0.015
const DOTS_SIZE := 360.0
const CORNER := 5
## The team's column on the left (left-panel-width) and the gap after it,
## a row (sb-row-width-inner: the part drawn without the mouse's buttons).
const INFO := 80.0
const INFO_GAP := 10.0
const ROW_WIDTH := 770.0
const WIDTH := PAD + INFO + INFO_GAP + 830.0 + PAD
## Heights, down the panel: the first lines (.sb-meta), the labels' row,
## a team (its column: the 80 px score, two lines of name and "Alive"), the
## timeline (its segments' 100 and 2 px either side), the spectators'
## padding and the footer.
const META := 75.0
const LABELS := 26.0
const TEAM := 156.0
const TIMELINE := 104.0
const SPECTATORS := 20.0
const FOOTER := 48.0
const HEIGHT := PAD + META + LABELS + TEAM + TIMELINE + TEAM + SPECTATORS + FOOTER
## A row: 24 px of cells with a pixel either side.
const CELL := 24.0
const ROW_PITCH := 26.0
## The cells, left to right, by where each starts in the row and how wide it
## is (.sb-row__cell--status and the rest): the name takes what is left.
const STATUS := Vector2(0.0, 24.0)
const PING := Vector2(24.0, 37.0)
const FLAIR := Vector2(61.0, 32.4)
const AVATAR := Vector2(93.4, 24.0)
const NAME := Vector2(117.4, 322.6)
const MONEY := Vector2(440.0, 66.0)
const KILLS := Vector2(506.0, 50.0)
const DEATHS := Vector2(556.0, 50.0)
const ASSISTS := Vector2(606.0, 50.0)
const HSP := Vector2(656.0, 64.0)
const DAMAGE := Vector2(720.0, 50.0)
## The numbers' columns and CS2's word over each (Scoreboard_money and the
## rest).
const COLUMNS := [["Money", MONEY], ["Kills", KILLS], ["Deaths", DEATHS], ["Assists", ASSISTS],
	["HS%", HSP], ["DMG", DAMAGE]]
## The cells' backgrounds: the player's own cells darker than the numbers'.
const CELL_DARK := Color(1, 1, 1, 0.02)
const CELL_LIGHT := Color(1, 1, 1, 0.031)
## A dead player's row, washed grey (#999).
const DEAD_WASH := Color8(153, 153, 153)
## Your row: lit in your side's colour. scoreboard.css gives 0.07; Sid's
## screenshot shows it far brighter, which is what this follows.
const YOU_LIGHT := 0.35
const TEXT_SIZE := 18
const GREY := Color8(128, 128, 128)
const PING_GREY := Color8(136, 136, 136)
## The team's column: the score (70 px, .stratum-bold-mono), its emblem
## behind at 0.2, the name (20 px condensed, two lines at most) and "Alive"
## at 0.2.
const SCORE_SIZE := 70
const TEAM_TEXT := 20
const TEAM_LINE := 24.0
const EMBLEM_OPACITY := 0.2
const TEAM_NAMES := {"CT": ["COUNTER-", "TERRORISTS"], "T": ["TERRORISTS"]}
## The timeline: each half's score column (40 px), a round 20 px wide with
## its result icon 14 px (20 less 3 each side) at 0.6, 2 px off the tick
## line, a divider of 2 px with 10 either side between the halves, the
## tick's number every fifth round at 14 px and 0.6.
const HALF_COLUMN := 40.0
const ROUNDS_LEFT := INFO
const ROUNDS_WIDTH := 650.0
const ROUNDS_PADDING := 10.0
const ROUND := 20.0
const RESULT := 14.0
const RESULT_OPACITY := 0.6
const DIVIDER := 22.0
const TICK_LABEL := 14
## The loss bonus, where Sid's screenshot has it (its centre 844 px into
## the panel; the styles would put it 60 px further left): four dashes of
## 14 by 2 a side, black at 0.6 until lit.
const LOSS_CENTRE := 844.0
const DASH := Vector2(14.0, 2.0)
const DASHES := 4
## The round result icons (gamerules_constants.js dictRoundResultImage), by
## round_end's reason.
const RESULT_ICONS := {
	"CTsWin": "icons/ui/kill", "TerroristsWin": "icons/ui/kill", "TargetBombed": "icons/ui/bomb",
	"BombDefused": "icons/equipment/defuser", "TargetSaved": "icons/ui/timer",
}
const TROPHY := "icons/ui/trophy"
## The status cell's icons (dictPlayerStatusImage), by Row.status.
const STATUS_ICONS := {"dead": "icons/ui/elimination", "c4": "icons/ui/bomb_c4", "kit": "icons/equipment/defuser"}


## Every image it draws by a name held in a constant, for GameHud to read
## ahead.
static func images() -> Array:
	var out: Array = RESULT_ICONS.values() + STATUS_ICONS.values()
	out.append(TROPHY)
	return out

## One player's row.
class Row:
	var userid: int = GameEvents.NOBODY
	var name: String = ""
	var side: String = "T"
	var bot: bool = false
	var alive: bool = true
	var you: bool = false
	var colour: Color = Color.WHITE
	## "dead", "c4", "kit" or "".
	var status: String = ""
	## -1 where it is not shown.
	var money: int = -1
	var kills: int = 0
	var deaths: int = 0
	var assists: int = 0
	var hsp: int = 0
	var damage: int = 0
	var mvps: int = 0
	var joined: int = 0

	func signature() -> Array:
		return [userid, name, side, bot, alive, you, colour, status, money, kills, deaths, assists, hsp, damage]


## Whether Tab is held.
var held: bool = false
## The map's name (de_dust2), for the first line.
var map_name: String = ""

## What is shown: the rows by side, the scores, players alive and on each
## side, the timeline, the loss ladder, the time.
var rows := {"CT": [], "T": []}
var scores := {"CT": 0, "T": 0}
var alive := {"CT": 0, "T": 0}
## [top, bottom] a half of the period, as [score, side it was played on].
var halves: Array = []
## The period's rounds: {"top": bool, "icon": String, "side": String} a
## round played; {} for one still to come.
var rounds: Array = []
## Where the trophy goes: [round index, top] each.
var clinches: Array = []
var losses := {"CT": 0, "T": 0}
var clock: String = ""


func _init() -> void:
	super()
	visible = false


func _ready() -> void:
	place(Vector2(0.5, 0.5), Rect2(-WIDTH * 0.5, DROP - HEIGHT * 0.5, WIDTH, HEIGHT))


func _input(event: InputEvent) -> void:
	if event.is_action(&"showscores") and not event.is_echo():
		held = event.is_pressed()


## Reads the match for `you` and shows the board while Tab is held.
func show_match(state: MatchState, stats: MatchStats, economy: Economy, you: PlayerSim, now_usec: int,
		carrier: int = C4.NOBODY) -> void:
	visible = held
	if not held:
		return
	rows = rows_for(state, stats, economy, you, carrier)
	var signature: Array = []
	for side: String in MatchState.SIDES:
		scores[side] = state.score(side)
		alive[side] = state.alive_on(side)
		losses[side] = economy.losses(side) if economy != null else 0
		signature.append_array([scores[side], alive[side], losses[side], rows[side].size()])
		for row: Row in rows[side]:
			signature.append_array(row.signature())
	var period := period_of(state)
	halves = half_scores(state, period)
	rounds = timeline(state, period)
	clinches = clinch_rounds(state, period)
	@warning_ignore("integer_division")
	var seconds := now_usec / 1_000_000
	@warning_ignore("integer_division")
	clock = "%d:%02d" % [seconds / 60, seconds % 60]
	signature.append_array([halves, rounds, clinches, clock, map_name])
	show_state(signature)


## Each side's rows, sorted as competitive sorts them.
static func rows_for(state: MatchState, stats: MatchStats, economy: Economy, you: PlayerSim,
		carrier: int = C4.NOBODY) -> Dictionary:
	var out := {"CT": [], "T": []}
	var mine := you.team if you != null else ""
	for n in state.players.size():
		var player := state.players[n]
		if not out.has(player.team):
			continue
		var row := Row.new()
		row.userid = player.userid
		row.name = str(player.name)
		row.side = player.team
		row.bot = player is Bot
		row.alive = player.alive
		row.you = you != null and player == you
		row.colour = GameHud.player_colour(state, player)
		row.joined = n
		var friendly := player.team == mine
		if not player.alive:
			row.status = "dead"
		elif friendly and carrier != C4.NOBODY and player.userid == carrier:
			row.status = "c4"
		elif friendly and player.inventory != null and player.inventory.has_defuser:
			row.status = "kit"
		row.money = economy.money(player.userid) if economy != null and friendly else -1
		var numbers := stats.of(player.userid) if stats != null else MatchStats.ZERO.duplicate()
		row.kills = numbers["kills"]
		row.deaths = numbers["deaths"]
		row.assists = numbers["assists"]
		row.hsp = MatchStats.headshot_percent(numbers)
		row.damage = numbers["damage"]
		row.mvps = numbers["mvps"]
		out[player.team].append(row)
	for side: String in out:
		out[side].sort_custom(Scoreboard.before)
	return out


## Competitive's order (scoreboard.js sortOrder_tmm, less the round impact
## score and the commends, which are not kept): the most damage, kills,
## MVPs, assists, then the fewest deaths, then who joined first.
static func before(a: Row, b: Row) -> bool:
	for pair in [[a.damage, b.damage], [a.kills, b.kills], [a.mvps, b.mvps], [a.assists, b.assists],
			[b.deaths, a.deaths], [b.joined, a.joined]]:
		if pair[0] != pair[1]:
			return pair[0] > pair[1]
	return false


## The rounds the timeline shows, as [first round's index, how many]: the
## regulation's, or in overtime the overtime being played.
static func period_of(state: MatchState) -> Vector2i:
	var rules := state.rules if state.rules != null else MatchRules.new()
	var index := maxi(state.rounds_played - (1 if state.phase == MatchState.Phase.OVER else 0), 0)
	if index < rules.max_rounds or rules.overtime_rounds <= 0:
		return Vector2i(0, rules.max_rounds)
	@warning_ignore("integer_division")
	var overtime := (index - rules.max_rounds) / rules.overtime_rounds
	return Vector2i(rules.max_rounds + overtime * rules.overtime_rounds, rules.overtime_rounds)


## Each half of the period: [[top's score, the side it played], [bottom's
## score, its side]], the top being the team now on the counter-terrorist
## side.
static func half_scores(state: MatchState, period: Vector2i) -> Array:
	var top_team := state.started_as("CT")
	@warning_ignore("integer_division")
	var half := period.y / 2
	var out: Array = []
	for h in 2:
		var first := period.x + h * half
		var top := 0
		var bottom := 0
		var top_side := ""
		for i in range(first, mini(first + half, state.history.size())):
			var entry: Dictionary = state.history[i]
			if entry["team"] == top_team:
				top += 1
				top_side = entry["side"]
			else:
				bottom += 1
				top_side = MatchState.other(entry["side"])
		if top_side.is_empty():
			# Nothing played yet this half: the sides as they will be.
			var swapped_now := top_team != "CT"
			var swapped_then := h % 2 == 1
			top_side = "CT" if swapped_now == swapped_then else "T"
		out.append([[top, top_side], [bottom, MatchState.other(top_side)]])
	return out


## A column a round of the period: how a round played went, and on which
## side of the timeline; {} for one still to come.
static func timeline(state: MatchState, period: Vector2i) -> Array:
	var top_team := state.started_as("CT")
	var out: Array = []
	for i in range(period.x, period.x + period.y):
		if i >= state.history.size():
			out.append({})
			continue
		var entry: Dictionary = state.history[i]
		out.append({"top": entry["team"] == top_team, "icon": RESULT_ICONS.get(entry["reason"], TROPHY),
			"side": entry["side"]})
	return out


## Where each team would win the match if it won every round from now: the
## round (its index in the period) and whether it is the top team's; the
## sooner of the two, both where they fall together. None in overtime.
static func clinch_rounds(state: MatchState, period: Vector2i) -> Array:
	if period.x > 0 or state.phase == MatchState.Phase.OVER:
		return []
	@warning_ignore("integer_division")
	var needed := period.y / 2 + 1
	var top := state.rounds_played + needed - state.score("CT") - 1
	var bottom := state.rounds_played + needed - state.score("T") - 1
	var out: Array = []
	if top <= bottom and top < period.y:
		out.append([top, true])
	if bottom <= top and bottom < period.y:
		out.append([bottom, false])
	return out


func _blur_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size) if visible else Rect2()


func _draw_blur(on: CanvasItem) -> void:
	_draw_panel(on, Color.WHITE)


func _draw() -> void:
	_draw_panel(self, BACKGROUND)
	var dots := HudStyle.icon("backgrounds/bluedots_large_png")
	if dots != null:
		var inside := Rect2(Vector2.ZERO, size)
		var dot_scale := dots.get_size().x / DOTS_SIZE
		draw_texture_rect_region(dots, inside, Rect2(Vector2.ZERO, inside.size * dot_scale), Color(1, 1, 1, DOTS_OPACITY))
	_draw_meta()
	var y := PAD + META
	_draw_labels(y)
	y += LABELS
	_draw_team("CT", y)
	y += TEAM
	_draw_timeline(y)
	y += TIMELINE
	_draw_team("T", y)


func _draw_panel(on: CanvasItem, colour: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(CORNER)
	box.anti_aliasing = false
	on.draw_style_box(box, Rect2(Vector2.ZERO, size))


## The first line: the mode's icon, "Competitive | Dust II", the time.
func _draw_meta() -> void:
	var baseline := HudStyle.baseline_centred(PAD + 16.0, 22, &"condensed")
	var mode := HudStyle.icon("icons/ui/competitive_teams")
	if mode != null:
		HudStyle.draw_fitted(self, mode, Rect2(PAD + 6.0, PAD + 4.0, 24.0, 24.0), GREY)
	var map_title: String = MAP_TITLES.get(map_name, map_name)
	var title := MODE_TITLE + (" | " + map_title if not map_title.is_empty() else "")
	HudStyle.draw_text(self, Vector2(PAD + 48.0, baseline), title, 22, GREY, HORIZONTAL_ALIGNMENT_LEFT, &"condensed")
	HudStyle.draw_text(self, Vector2(size.x - PAD, HudStyle.baseline_centred(PAD + 16.0, 18, &"mono_bold")), clock,
		18, GREY, HORIZONTAL_ALIGNMENT_RIGHT, &"mono_bold")
	draw_line(Vector2(PAD, PAD + 36.0), Vector2(size.x - PAD, PAD + 36.0), Color(1, 1, 1, 0.06), 1.0)


## The labels over the numbers, and the ping's bars over its column.
func _draw_labels(top: float) -> void:
	var left := PAD + INFO + INFO_GAP
	var baseline := HudStyle.baseline_centred(top + 5.0 + CELL * 0.5, TEXT_SIZE, &"condensed")
	for column: Array in COLUMNS:
		var cell: Vector2 = column[1]
		HudStyle.draw_text(self, Vector2(left + cell.x + cell.y * 0.5, baseline), column[0], TEXT_SIZE,
			Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, &"condensed")
	# Four rising bars, CS2's ping_4.
	var bars_left := left + PING.x + PING.y * 0.5 - 7.0
	for i in 4:
		var bar := 4.0 + i * 3.0
		draw_rect(Rect2(bars_left + i * 4.0, top + 20.0 - bar, 2.0, bar), Color(1, 1, 1, 0.8))


func _draw_team(side: String, top: float) -> void:
	var colour := HudStyle.counter_colour(side)
	# The team's column: its emblem behind the score, the name, who is alive.
	var score_box := Rect2(PAD, top, INFO, INFO)
	var emblem := HudStyle.icon("icons/ui/ct_logo_1c" if side == "CT" else "icons/ui/t_logo_1c")
	if emblem != null:
		HudStyle.draw_fitted(self, emblem, score_box.grow(-4.0), Color(colour, EMBLEM_OPACITY))
	else:
		draw_arc(score_box.get_center(), INFO * 0.42, 0.0, TAU, 48, Color(colour, EMBLEM_OPACITY), 3.0)
	HudStyle.draw_text(self, Vector2(score_box.get_center().x, HudStyle.baseline_centred(score_box.get_center().y,
		SCORE_SIZE, &"mono_bold")), str(scores[side]), SCORE_SIZE, colour, HORIZONTAL_ALIGNMENT_CENTER, &"mono_bold",
		Color(0, 0, 0, 0.5), 3)
	var line_top := top + INFO + 2.0
	for line: String in TEAM_NAMES[side]:
		HudStyle.draw_text(self, Vector2(PAD + INFO * 0.5, HudStyle.baseline_from_top(line_top, TEAM_TEXT, &"condensed")),
			line, TEAM_TEXT, colour, HORIZONTAL_ALIGNMENT_CENTER, &"condensed", Color(0, 0, 0, 1), 1)
		line_top += TEAM_LINE
	HudStyle.draw_text(self, Vector2(PAD + INFO * 0.5, HudStyle.baseline_from_top(line_top + 2.0, TEAM_TEXT, &"condensed")),
		"Alive: %d/%d" % [alive[side], rows[side].size()], TEAM_TEXT, Color(colour, 0.2), HORIZONTAL_ALIGNMENT_CENTER,
		&"condensed")
	var left := PAD + INFO + INFO_GAP
	var list: Array = rows[side]
	for n in list.size():
		_draw_row(list[n], Vector2(left, top + 1.0 + n * ROW_PITCH))


func _draw_row(row: Row, at: Vector2) -> void:
	var tint := HudStyle.counter_colour(row.side) if row.alive else DEAD_WASH
	if row.you:
		draw_rect(Rect2(at, Vector2(ROW_WIDTH, CELL)), Color(HudStyle.team_colour(row.side), YOU_LIGHT))
	if row.alive:
		for cell: Vector2 in [STATUS, PING, FLAIR, AVATAR, NAME]:
			draw_rect(Rect2(at.x + cell.x, at.y, cell.y, CELL), CELL_DARK)
		for column: Array in COLUMNS:
			var cell: Vector2 = column[1]
			draw_rect(Rect2(at.x + cell.x, at.y, cell.y, CELL), CELL_LIGHT)
	var baseline := HudStyle.baseline_centred(at.y + CELL * 0.5, TEXT_SIZE, &"regular")
	# The status: a skull when dead, your team's C4 or kit.
	var status_box := Rect2(at.x + STATUS.x + 2.0, at.y + 2.0, CELL - 4.0, CELL - 4.0)
	var status_icon: String = STATUS_ICONS.get(row.status, "")
	if not status_icon.is_empty():
		var texture := HudStyle.icon(status_icon)
		if texture != null:
			HudStyle.draw_fitted(self, texture, status_box, tint)
		else:
			draw_circle(status_box.get_center(), 5.0, tint)
	# The ping, or a bot's mark.
	var ping_centre := at.x + PING.x + PING.y * 0.5
	if row.bot:
		var bot := HudStyle.icon("icons/ui/bot")
		var bot_box := Rect2(ping_centre - 8.0, at.y + 4.0, 16.0, 16.0)
		if bot != null:
			HudStyle.draw_fitted(self, bot, bot_box, tint)
		else:
			draw_rect(bot_box.grow(-3.0), tint, false, 1.5)
	else:
		HudStyle.draw_text(self, Vector2(ping_centre, baseline), "0", TEXT_SIZE, PING_GREY,
			HORIZONTAL_ALIGNMENT_CENTER, &"mono_bold")
	# The portrait in the player's colour.
	var portrait := Rect2(at.x + AVATAR.x, at.y, AVATAR.y, CELL)
	draw_rect(portrait, TeamCounter.DEFAULT_PORTRAIT[row.side] if row.alive else Color(0.3, 0.3, 0.3))
	var face := HudStyle.icon("hud/teamcounter/teamcounter_botavatar") if row.bot else null
	if face != null:
		HudStyle.draw_fitted(self, face, portrait.grow(-2.0), TeamCounter.BOT_WASH[row.side])
	draw_rect(portrait.grow(-0.75), row.colour if row.alive else Color.BLACK, false, 1.5)
	var shown_name := (KillFeed.BOT_TAG if row.bot else "") + row.name
	HudStyle.draw_text(self, Vector2(at.x + NAME.x + 6.0, baseline), shown_name, TEXT_SIZE,
		Color.WHITE if row.you else tint, HORIZONTAL_ALIGNMENT_LEFT, &"medium")
	if row.money >= 0:
		HudStyle.draw_text(self, Vector2(at.x + MONEY.x + MONEY.y - 6.0, baseline), "$%d" % row.money, TEXT_SIZE,
			tint, HORIZONTAL_ALIGNMENT_RIGHT, &"regular")
	for pair in [[KILLS, row.kills], [DEATHS, row.deaths], [ASSISTS, row.assists], [HSP, row.hsp],
			[DAMAGE, row.damage]]:
		var cell: Vector2 = pair[0]
		HudStyle.draw_text(self, Vector2(at.x + cell.x + cell.y * 0.5, baseline), str(pair[1]), TEXT_SIZE, tint,
			HORIZONTAL_ALIGNMENT_CENTER, &"regular")


## The halves' scores, the rounds and the loss bonus.
func _draw_timeline(top: float) -> void:
	var middle := top + TIMELINE * 0.5
	# Each half: the top team's score, "1st" or "2nd", the bottom's.
	for h in halves.size():
		var x := PAD + HALF_COLUMN * (h + 0.5)
		var half: Array = halves[h]
		HudStyle.draw_text(self, Vector2(x, HudStyle.baseline_centred(middle - 27.0, 20, &"condensed")),
			str(half[0][0]), 20, HudStyle.counter_colour(half[0][1]), HORIZONTAL_ALIGNMENT_CENTER, &"condensed",
			Color(0, 0, 0, 1), 1)
		HudStyle.draw_text(self, Vector2(x, HudStyle.baseline_centred(middle, 18, &"condensed")),
			"1st" if h == 0 else "2nd", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, &"condensed")
		HudStyle.draw_text(self, Vector2(x, HudStyle.baseline_centred(middle + 27.0, 20, &"condensed")),
			str(half[1][0]), 20, HudStyle.counter_colour(half[1][1]), HORIZONTAL_ALIGNMENT_CENTER, &"condensed",
			Color(0, 0, 0, 1), 1)
	# The rounds: two halves of columns with a divider between, centred in
	# their 650 px after 10 px of padding.
	@warning_ignore("integer_division")
	var half_count := rounds.size() / 2
	var span := rounds.size() * ROUND + (DIVIDER if half_count > 0 else 0.0)
	var left := PAD + ROUNDS_LEFT + ROUNDS_PADDING + (ROUNDS_WIDTH - ROUNDS_PADDING - span) * 0.5
	var played := 0
	for i in rounds.size():
		if not rounds[i].is_empty():
			played = i + 1
	for i in rounds.size():
		var x := left + i * ROUND + (DIVIDER if i >= half_count else 0.0)
		var column: Dictionary = rounds[i]
		var tick_colour := Color(1, 1, 1, 0.15)
		if not column.is_empty():
			tick_colour = Color(HudStyle.counter_colour(column["side"]), 0.8)
		elif i == played:
			tick_colour = Color(1, 1, 1, 0.5)
		draw_rect(Rect2(x + ROUND * 0.05, middle - 1.0, ROUND * 0.9, 2.0), tick_colour)
		if (i + 1) % 5 == 0:
			HudStyle.draw_text(self, Vector2(x + ROUND * 0.5, HudStyle.baseline_centred(middle, TICK_LABEL, &"condensed")),
				str(i + 1), TICK_LABEL, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, &"condensed", Color(0, 0, 0, 1), 2)
		if not column.is_empty():
			_draw_result(column["icon"], x, middle, column["top"], Color(HudStyle.counter_colour(column["side"]), RESULT_OPACITY))
	if half_count > 0:
		var divider_x := left + half_count * ROUND + DIVIDER * 0.5 - 1.0
		draw_rect(Rect2(divider_x, middle - TIMELINE * 0.25, 2.0, TIMELINE * 0.5), Color(0.5, 0.5, 0.5, 0.1))
	for clinch: Array in clinches:
		var i: int = clinch[0]
		var x := left + i * ROUND + (DIVIDER if i >= half_count else 0.0)
		_draw_result(TROPHY, x, middle, clinch[1], Color(1, 1, 1, 0.4))
	# The loss bonus: the counter-terrorists' dashes, the words, the
	# terrorists'.
	for side: String in MatchState.SIDES:
		var y := middle - 22.0 if side == "CT" else middle + 20.0
		var dashes_left := LOSS_CENTRE - (DASHES * (DASH.x + 1.0)) * 0.5
		for d in DASHES:
			var lit: bool = d < int(losses[side])
			draw_rect(Rect2(dashes_left + d * (DASH.x + 1.0), y, DASH.x, DASH.y),
				HudStyle.counter_colour(side) if lit else Color(0, 0, 0, 0.6))
	HudStyle.draw_text(self, Vector2(LOSS_CENTRE, HudStyle.baseline_centred(middle, 18, &"condensed")), "Loss Bonus",
		18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, &"condensed")


## A round's icon above the tick line (the top team's) or under it.
func _draw_result(path: String, x: float, middle: float, top: bool, colour: Color) -> void:
	var box := Rect2(x + (ROUND - RESULT) * 0.5, middle - 2.0 - RESULT if top else middle + 2.0 + 1.0, RESULT, RESULT)
	var texture := HudStyle.icon(path)
	if texture != null:
		HudStyle.draw_fitted(self, texture, box, colour)
	else:
		draw_circle(box.get_center(), RESULT * 0.3, colour)
