class_name KillFeed
extends HudElement

## CS2's kill feed (CSGOHudDeathNotice; its panorama/layout/hud/
## huddeathnotice.xml and styles/hud/huddeathnotice.css, read from
## GameTracking-CS2 at its 2026-09-25 commit; reference/research/
## round-hud-bots.md A1): in the top right, 72 px down and 10 px in, one row
## per death, the newest at the bottom. A row reads left to right: revenge,
## domination, a blind attacker's mark, the attacker, "+" and the assister
## (a flash's icon before them for a flash assist), an in-air kill's mark
## raised on the weapon, the weapon, then no-scope, through smoke, a
## wallbang, a headshot (or a suicide's skull in the weapon's place), and
## the victim.
##
## What it shows is read from the game's player_death events as they are
## handed out (after the tick), and drawn on the frames that follow: it
## never changes the game. A row stays 5 s (DeathNoticeLifetime), half as
## long again when you killed, died or assisted
## (DeathNoticeLocalPlayerLifetimeMod), then fades out over 1 s; the rows
## under a row that goes slide up into its place over .2 s, ease-out.
##
## Its look is CS2's: names 16 px Stratum2 bold with a 1 px black shadow,
## cut off past 160 px, in the feed's own team colours (CTColor, TColor);
## each row on the world blurred behind hud-blur-bg-color, 3 px round; a row
## where you killed is ringed 2 px in #e10000 on #000000e7 with 15 px names,
## a row where you died is on #630606d2. A bot's name carries CS2's clan tag
## "[BOT]" (cl_show_clan_in_death_notice, on by default), thinner, as the
## screenshot of 2026-09-26 shows it.
##
## Without the extraction (scripts/extract_assets.sh hud) the weapon shows as
## its name and each mark as a short word in a grey box, so a missing icon
## is plain to see.
##
## Left out: Danger Zone's squad wipe strip, and the numbers
## cl_deathnotices_show_numbers adds. Guesses, named: how many rows show at
## once (MOST_SHOWN; CS2 sets it in C++), that a new row appears at once
## where it goes, and that your own suicide is drawn as a death, not a kill.

## huddeathnotice.css: CSGOHudDeathNotice's margin-top and padding-right,
## each row's margin-top, its content's padding (top, right, bottom, left),
## its corners.
const TOP := 72.0
const RIGHT := 10.0
const GAP := 3.0
const PAD_TOP := 6.0
const PAD_SIDE := 10.0
const PAD_BOTTOM := 3.0
const CORNER := 3.0
## A row's height at 1080p, measured on CS2's screenshot (2026-09-26, 64 px
## at 2160p): the padding round the 24 px icons less their -2 px margin.
const ROW_HEIGHT := 32.0
## The widest a row is let be: five names at their cap and every icon.
const WIDTH := 960.0
## Labels: 16 px, 2 px either side and under, cut off with an ellipsis past
## 160 px; yours 15 px (CS2 sets them black weight with .5 px between
## letters, which Stratum2's bold stands in for).
const NAME_SIZE := 16
const YOUR_NAME_SIZE := 15
const NAME_MARGIN := 2.0
const NAME_MAX := 160.0
const SHADOW := Color(0, 0, 0, 1)
## Icons: 24 px high, 2 px either side, 2 px up (margin -2 2 0 2); the in-air
## mark 14 px up and 4 px into the weapon's place.
const ICON_HEIGHT := 24.0
const ICON_MARGIN := 2.0
const ICON_RAISE := 2.0
const IN_AIR_RAISE := 14.0
const IN_AIR_OVERLAP := 4.0
## A missing icon's word: 11 px in a grey box.
const FALLBACK_SIZE := 11
const FALLBACK_BOX := Color(1, 1, 1, 0.18)

## huddeathnotice.css's colours.
const CT_COLOUR := Color8(0x6f, 0x9c, 0xe6)
const T_COLOUR := Color8(0xea, 0xbe, 0x54)
const FADED_COLOUR := Color8(0x88, 0x88, 0x88)
## Behind a row: hud-blur-bg-color (#000000a0) over the blurred world, at
## full strength (the cl_hud_background_alpha halving is not on this
## panel; on the screenshot the row is darker than the halved tint allows).
const BACKGROUND := Color(0, 0, 0, 0xa0 / 255.0)
const KILLER_BACKGROUND := Color(0, 0, 0, 0xe7 / 255.0)
const KILLER_BORDER := Color8(0xe1, 0x00, 0x00)
const KILLER_BORDER_WIDTH := 2
const VICTIM_BACKGROUND := Color(0x63 / 255.0, 0x06 / 255.0, 0x06 / 255.0, 0xd2 / 255.0)

## DeathNoticeLifetime, DeathNoticeLocalPlayerLifetimeMod,
## DeathNoticeFadeOutTime; the rows' slide (.DeathNotice's transition).
const LIFETIME := 5.0
const YOUR_LIFETIME_SCALE := 1.5
const FADE_SECONDS := 1.0
const SLIDE_SECONDS := 0.2
## How many rows at once, the oldest going first to make room. CS2 sets it
## in C++; five is a guess, what fits at 1080p over the view without
## reaching the crosshair's half of the screen.
const MOST_SHOWN := 5

## The icons under panorama/images, by the class that shows them.
const ICONS := {
	"revenge": "hud/deathnotice/revenge",
	"domination": "hud/deathnotice/domination",
	"blind": "hud/deathnotice/blind_kill",
	"flash": "icons/equipment/flashbang_assist",
	"in_air": "hud/deathnotice/inairkill",
	"noscope": "hud/deathnotice/noscope",
	"smoke": "hud/deathnotice/smoke_kill",
	"penetrate": "hud/deathnotice/penetrate",
	"headshot": "hud/deathnotice/icon_headshot",
	"suicide": "hud/deathnotice/icon_suicide",
}
## The word that stands in for each icon without the extraction.
const FALLBACK_WORDS := {
	"revenge": "REVENGE", "domination": "DOMINATING", "blind": "BLIND", "flash": "FLASH",
	"in_air": "AIR", "noscope": "NOSCOPE", "smoke": "SMOKE", "penetrate": "WALL",
	"headshot": "HS", "suicide": "SKULL",
}

## Whose you are: DeathNotice_Killer and DeathNotice_Victim.
enum Yours { NONE, KILLER, VICTIM }


## One row: who, with what, which marks, and how long it has been up.
class Notice extends RefCounted:
	var attacker: String = ""
	var attacker_side: String = ""
	var attacker_bot: bool = false
	var assister: String = ""
	var assister_side: String = ""
	var assister_bot: bool = false
	var victim: String = ""
	var victim_side: String = ""
	var victim_bot: bool = false
	## A CS2 class ("weapon_ak47"); "" for none.
	var weapon: String = ""
	## The marks shown, by ICONS' names, in the order they are drawn.
	var marks := PackedStringArray()
	var yours: int = Yours.NONE
	## Whether you are on it at all (the killer, the victim or the assister).
	var involves_you: bool = false
	var age: float = 0.0
	## Where it is, down from the element's top, and where it slides from.
	var y: float = 0.0
	var from_y: float = 0.0
	var slide: float = 1.0

	func lifetime() -> float:
		return LIFETIME * (YOUR_LIFETIME_SCALE if involves_you else 1.0)

	func has(mark: String) -> bool:
		return mark in marks


var game: GameSystems
## Whose eyes the feed is for: their rows are marked and stay longer.
var you: int = GameEvents.NOBODY
var _notices: Array[Notice] = []
## Deaths handed out on a tick that are not rows yet: they are on the next
## frame (_take_in).
var _waiting: Array[Notice] = []


func _ready() -> void:
	place(Vector2(1.0, 0.0), Rect2(-WIDTH - RIGHT, TOP, WIDTH, (ROW_HEIGHT + GAP) * MOST_SHOWN))


## Reads a game's deaths, for `viewer`'s eyes.
func watch(p_game: GameSystems, viewer: int) -> void:
	game = p_game
	you = viewer
	game.events.listen(&"player_death", _on_death)


func _exit_tree() -> void:
	if game != null:
		game.events.unlisten(&"player_death", _on_death)


## A death, told on the tick it happened in. What it says is read now, from
## the roster as it is; the row is made on the next frame, since a row laid
## out measures its names and reads its icons, which is the frame's work and
## was the tick's: 0.1 ms of every tick with a death, and 5 ms of the first,
## which read the gun's icon and a face from the disk.
func _on_death(event: GameEvent) -> void:
	_waiting.append(notice_for(event.fields, game.roster if game != null else null, you))
	set_process(true)


## The deaths told since the last frame become rows, in the order they
## were told.
func _take_in() -> void:
	if _waiting.is_empty():
		return
	var told := _waiting
	_waiting = []
	for notice in told:
		add(notice)


## The row for a death (player_death's fields), its names and sides read
## from the roster as the death is handed out, so a side swap later does not
## recolour it.
static func notice_for(fields: Dictionary, roster: Roster, viewer: int) -> Notice:
	var n := Notice.new()
	var victim: int = fields.get("userid", GameEvents.NOBODY)
	var attacker: int = fields.get("attacker", GameEvents.NOBODY)
	var assister: int = fields.get("assister", GameEvents.NOBODY)
	n.weapon = String(fields.get("weapon", ""))
	# A suicide: by your own hand, or the world's with nothing to show for
	# it (a fall). The bomb's kill has no killer but shows the C4.
	var suicide := attacker == victim or (attacker == GameEvents.NOBODY and n.weapon in ["", "worldspawn"])
	n.victim = _name(roster, victim)
	n.victim_side = _side(roster, victim)
	n.victim_bot = _is_bot(roster, victim)
	if not suicide and attacker != GameEvents.NOBODY:
		n.attacker = _name(roster, attacker)
		n.attacker_side = _side(roster, attacker)
		n.attacker_bot = _is_bot(roster, attacker)
	if not suicide and assister != GameEvents.NOBODY:
		n.assister = _name(roster, assister)
		n.assister_side = _side(roster, assister)
		n.assister_bot = _is_bot(roster, assister)
	if int(fields.get("revenge", 0)) > 0:
		n.marks.append("revenge")
	if int(fields.get("dominated", 0)) > 0:
		n.marks.append("domination")
	if bool(fields.get("attackerblind", false)) and not n.attacker.is_empty():
		n.marks.append("blind")
	if bool(fields.get("assistedflash", false)) and not n.assister.is_empty():
		n.marks.append("flash")
	if bool(fields.get("attackerinair", false)) and not n.attacker.is_empty():
		n.marks.append("in_air")
	if bool(fields.get("noscope", false)):
		n.marks.append("noscope")
	if bool(fields.get("thrusmoke", false)):
		n.marks.append("smoke")
	if int(fields.get("penetrated", 0)) > 0:
		n.marks.append("penetrate")
	if bool(fields.get("headshot", false)):
		n.marks.append("headshot")
	if suicide:
		n.marks.append("suicide")
	if viewer != GameEvents.NOBODY:
		if victim == viewer:
			n.yours = Yours.VICTIM
		elif attacker == viewer:
			n.yours = Yours.KILLER
		n.involves_you = victim == viewer or attacker == viewer or assister == viewer
	return n


static func _name(roster: Roster, who: int) -> String:
	var node: Node = roster.player(who) if roster != null and who != GameEvents.NOBODY else null
	return str(node.name) if node != null else ""


static func _side(roster: Roster, who: int) -> String:
	return roster.team_of(who) if roster != null and who != GameEvents.NOBODY else ""


static func _is_bot(roster: Roster, who: int) -> bool:
	return roster != null and who != GameEvents.NOBODY and roster.player(who) is Bot


## Puts a row at the bottom, the oldest going if there is no room.
func add(notice: Notice) -> void:
	_notices.append(notice)
	while _notices.size() > MOST_SHOWN:
		_notices.pop_front()
	_settle()
	notice.y = row_top(_notices.size() - 1)
	notice.from_y = notice.y
	notice.slide = 1.0
	set_process(true)
	redraw()


## The rows up now, oldest first, those told and not yet drawn among them.
## A copy.
func notices() -> Array[Notice]:
	_take_in()
	return _notices.duplicate()


## Where row `index` sits, down from the element's top.
static func row_top(index: int) -> float:
	return GAP + index * (ROW_HEIGHT + GAP)


## Starts every row sliding to its place.
func _settle() -> void:
	for i in _notices.size():
		var n := _notices[i]
		var target := row_top(i)
		if not is_equal_approx(n.y, target):
			n.from_y = n.y
			n.slide = 0.0


## How much of a row shows: 1 until its time is up, then ease-out to 0.
static func opacity_of(n: Notice) -> float:
	var over := (n.age - n.lifetime()) / FADE_SECONDS
	if over <= 0.0:
		return 1.0
	return 1.0 - _ease_out(over)


## CSS's ease-out: cubic-bezier(0, 0, .58, 1), close enough as a square.
static func _ease_out(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)


## Ages the rows; only redraws while one is fading or sliding, so a still
## feed costs a few additions a frame. Stops once the feed is empty.
func _process(delta: float) -> void:
	_take_in()
	var changed := false
	for i in _notices.size():
		var n := _notices[i]
		if n.slide < 1.0:
			n.slide = minf(n.slide + delta / SLIDE_SECONDS, 1.0)
			n.y = lerpf(n.from_y, row_top(i), _ease_out(n.slide))
			changed = true
	var kept: Array[Notice] = []
	for n in _notices:
		var was_fading := n.age > n.lifetime()
		n.age += delta
		if n.age > n.lifetime() or was_fading:
			changed = true
		if n.age < n.lifetime() + FADE_SECONDS:
			kept.append(n)
	if kept.size() != _notices.size():
		# The rows under a gone one slide up from the next frame on.
		_notices = kept
		_settle()
		changed = true
	if changed:
		redraw()
	if _notices.is_empty():
		set_process(false)


func is_animating() -> bool:
	return is_processing()


func _blur_rect() -> Rect2:
	var area := Rect2()
	for n in _notices:
		var row := _row_rect(n)
		area = row if not area.has_area() else area.merge(row)
	return area


## The world blurred behind each row (world-blur: hudWorldBlur).
func _draw_blur(on: CanvasItem) -> void:
	for n in _notices:
		on.draw_style_box(_rounded(Color(1, 1, 1, opacity_of(n))), _row_rect(n))


func _draw() -> void:
	for n in _notices:
		_draw_row(n)


static func _rounded(colour: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(int(CORNER))
	box.anti_aliasing = true
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	return box


## A row's box, right-aligned in the element.
func _row_rect(n: Notice) -> Rect2:
	var width := row_width(n)
	return Rect2(size.x - width, n.y, width, ROW_HEIGHT)


## What a row holds, left to right: [kind, ...] parts, each "name" [text,
## side, bot], "plus", "icon" [mark] or "weapon" [class].
static func parts_of(n: Notice) -> Array:
	var parts := []
	for mark in ["revenge", "domination", "blind"]:
		if n.has(mark):
			parts.append(["icon", mark])
	if not n.attacker.is_empty():
		parts.append(["name", n.attacker, n.attacker_side, n.attacker_bot])
	if not n.assister.is_empty():
		parts.append(["plus"])
		if n.has("flash"):
			parts.append(["icon", "flash"])
		parts.append(["name", n.assister, n.assister_side, n.assister_bot])
	if n.has("in_air"):
		parts.append(["icon", "in_air"])
	if not n.has("suicide") and not n.weapon.is_empty() and n.weapon != "worldspawn":
		parts.append(["weapon", n.weapon])
	for mark in ["noscope", "smoke", "penetrate", "headshot", "suicide"]:
		if n.has(mark):
			parts.append(["icon", mark])
	parts.append(["name", n.victim, n.victim_side, n.victim_bot])
	return parts


static func name_size(n: Notice) -> int:
	return YOUR_NAME_SIZE if n.yours == Yours.KILLER else NAME_SIZE


static func side_colour(side: String) -> Color:
	match side:
		"CT":
			return CT_COLOUR
		"T":
			return T_COLOUR
	return FADED_COLOUR


## The clan tag before a bot's name.
const BOT_TAG := "[BOT] "


## A name as it is drawn: the tag and the name, cut to NAME_MAX with an
## ellipsis. Returns [tag, name].
static func fit_name(text: String, bot: bool, font_size: int) -> PackedStringArray:
	var tag := BOT_TAG if bot else ""
	var tag_width := _tag_width(tag, font_size)
	var bold := HudStyle.face(&"bold")
	if tag_width + bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= NAME_MAX:
		return PackedStringArray([tag, text])
	var cut := text
	while cut.length() > 1 and tag_width + bold.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x > NAME_MAX:
		cut = cut.left(cut.length() - 1)
	return PackedStringArray([tag, cut + "…"])


static func _tag_width(tag: String, font_size: int) -> float:
	if tag.is_empty():
		return 0.0
	return HudStyle.face(&"light_condensed").get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


static func _part_width(part: Array, font_size: int) -> float:
	match part[0]:
		"name":
			var fitted := fit_name(part[1], part[3], font_size)
			return NAME_MARGIN * 2.0 + _tag_width(fitted[0], font_size) \
				+ HudStyle.face(&"bold").get_string_size(fitted[1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		"plus":
			return NAME_MARGIN * 2.0 + HudStyle.face(&"bold").get_string_size("+", HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x
		"icon":
			var width := _icon_width(HudStyle.icon(ICONS[part[1]]), FALLBACK_WORDS[part[1]])
			if part[1] == "in_air":
				width -= IN_AIR_OVERLAP
			return width + ICON_MARGIN * 2.0
		"weapon":
			return _icon_width(HudStyle.item_icon(part[1]), _weapon_name(part[1])) + ICON_MARGIN * 2.0
	return 0.0


## An icon's width at 24 px high, or its stand-in word's box.
static func _icon_width(texture: Texture2D, word: String) -> float:
	if texture != null and texture.get_height() > 0:
		return ICON_HEIGHT * texture.get_width() / texture.get_height()
	return HudStyle.face(&"bold").get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, FALLBACK_SIZE).x + 8.0


static func _weapon_name(item_class: String) -> String:
	return ItemRegistry.item(item_class).name if ItemRegistry.has(item_class) else item_class.trim_prefix("weapon_")


## A row's width: its parts and the padding either side.
static func row_width(n: Notice) -> float:
	var width := PAD_SIDE * 2.0
	var font_size := name_size(n)
	for part in parts_of(n):
		width += _part_width(part, font_size)
	return width


func _draw_row(n: Notice) -> void:
	var fade := opacity_of(n)
	if fade <= 0.0:
		return
	var row := _row_rect(n)
	match n.yours:
		Yours.KILLER:
			draw_style_box(_rounded(Color(KILLER_BACKGROUND, KILLER_BACKGROUND.a * fade),
				Color(KILLER_BORDER, fade), KILLER_BORDER_WIDTH), row)
		Yours.VICTIM:
			draw_style_box(_rounded(Color(VICTIM_BACKGROUND, VICTIM_BACKGROUND.a * fade)), row)
		_:
			draw_style_box(_rounded(Color(BACKGROUND, BACKGROUND.a * fade)), row)
	var font_size := name_size(n)
	# The content's middle: inside the padding, the labels' 2 px margin
	# under them and the icons' 2 px up leaving both a pixel high.
	var middle := row.position.y + PAD_TOP + (ROW_HEIGHT - PAD_TOP - PAD_BOTTOM) * 0.5 - 1.0
	var x := row.position.x + PAD_SIDE
	var shadow := Color(SHADOW, SHADOW.a * fade)
	for part: Array in parts_of(n):
		var width := _part_width(part, font_size)
		match part[0]:
			"name":
				var fitted := fit_name(part[1], part[3], font_size)
				var colour := Color(side_colour(part[2]), fade)
				var baseline := HudStyle.baseline_centred(middle, font_size, &"bold")
				var at := x + NAME_MARGIN
				if not fitted[0].is_empty():
					at += HudStyle.draw_text(self, Vector2(at, baseline), fitted[0], font_size, colour,
						HORIZONTAL_ALIGNMENT_LEFT, &"light_condensed", shadow, 1)
				HudStyle.draw_text(self, Vector2(at, baseline), fitted[1], font_size, colour,
					HORIZONTAL_ALIGNMENT_LEFT, &"bold", shadow, 1)
			"plus":
				HudStyle.draw_text(self, Vector2(x + NAME_MARGIN, HudStyle.baseline_centred(middle, font_size, &"bold")),
					"+", font_size, Color(1, 1, 1, fade), HORIZONTAL_ALIGNMENT_LEFT, &"bold", shadow, 1)
			"icon":
				# The in-air mark sits raised, its right 4 px over the weapon.
				var raise := IN_AIR_RAISE if part[1] == "in_air" else ICON_RAISE
				var texture := HudStyle.icon(ICONS[part[1]])
				_draw_icon(texture, FALLBACK_WORDS[part[1]], Rect2(x + ICON_MARGIN, middle - ICON_HEIGHT * 0.5 - raise + 1.0,
					_icon_width(texture, FALLBACK_WORDS[part[1]]), ICON_HEIGHT), fade)
			"weapon":
				_draw_icon(HudStyle.item_icon(part[1]), _weapon_name(part[1]),
					Rect2(x + ICON_MARGIN, middle - ICON_HEIGHT * 0.5 - ICON_RAISE + 1.0, width - ICON_MARGIN * 2.0,
						ICON_HEIGHT), fade)
		x += width


## An icon in white (CS2 draws them as they are, white), or its word on a
## grey box where it was not extracted.
func _draw_icon(texture: Texture2D, word: String, box: Rect2, fade: float) -> void:
	if texture != null:
		draw_texture_rect(texture, box, false, Color(1, 1, 1, fade))
		return
	var inner := Rect2(box.position.x, box.get_center().y - 8.0, box.size.x, 16.0)
	draw_style_box(_rounded(Color(FALLBACK_BOX, FALLBACK_BOX.a * fade)), inner)
	HudStyle.draw_text(self, Vector2(inner.get_center().x,
		HudStyle.baseline_centred(inner.get_center().y, FALLBACK_SIZE, &"bold")), word, FALLBACK_SIZE,
		Color(1, 1, 1, fade), HORIZONTAL_ALIGNMENT_CENTER, &"bold")
