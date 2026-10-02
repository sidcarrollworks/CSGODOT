class_name GameHud
extends CanvasLayer

## The HUD, laid out as today's CS2 lays it out (reference/cs2 _screenshots/
## In_game_ui.webp; the layout's regions are in
## reference/research/round-hud-bots.md A0): health, armour and ammo in one
## cluster at the bottom in the middle round the team's emblem
## (HealthAmmoCenter); your money in the bottom left with the buy zone's
## cart while you may buy (MoneyPanel); in a match, the clock, the scores,
## who is alive and a card for each player at the top in the middle
## (TeamCounter), what you carry in the bottom right for a moment after
## each switch (WeaponSelection), and a bar over the cluster saying what part of the match
## it is (HudAlert: warmup, the round's announcement, half time); from a
## round's end to the next round, CS2's win panel under the team counter,
## ROUND WON or ROUND LOST with the round's fun fact and its MVP (WinPanel,
## read from the RoundReport). A red arc
## round the crosshair on the side each hit came from; when dead, a bar
## across the middle counting down to the respawn or saying whom you are
## watching; "You picked up the bomb" as you walk over it, the bomb's C4
## on its carrier's card for your team; and CS2's buy menu on B, over the
## rest; in the top right, CS2's kill feed, a row per death read from the
## game's player_death events (KillFeed). The rest of a round's HUD (the
## radar, the scoreboard) is roadmap item 15.
##
## Each piece is a HudElement: it draws itself with HudStyle's colours, font
## and icons and redraws only when what it shows changes, so a frame where
## nothing changed costs the HUD only the reading of a few numbers here.
##
## And, small in the top left, where you are and where you are looking,
## like CS2's getpos: the feet's position in units and the view's yaw and
## pitch in degrees, the numbers a render of the same view is set up from,
## so a screenshot says exactly where it was taken; under it the frame rate
## and the slowest frame of the last second (FrameMeter). F3 hides them.

var player: PlayerController
## The match, where there is one; it is only read.
var match_state: MatchState
## Money and buying, where there is an economy, and whose; only read, and
## asked for purchases through the menu.
var economy: Economy
var userid: int = GameEvents.NOBODY
## The server's word on the last round (its MVP and fun fact), where there is
## a match; only read.
var round_report: RoundReport
## CS2's buy menu (B), over the rest of the HUD; null without an economy.
var buy_menu: BuyMenu
## The bomb, where the match has one; only read, for who carries it.
var bomb: C4
## The game whose deaths the kill feed shows, where there is one; only its
## events are read.
var game: GameSystems

var _crosshair: Crosshair
## A sniper's scope, over the view while scoped in.
var scope: ScopeOverlay
## The AUG's and SG 553's dot while up at the eye.
var iron_sight: IronSightOverlay
var health_ammo: HealthAmmoCenter
var money: MoneyPanel
var team_counter: TeamCounter
## What you carry, in the bottom right, for a moment after each switch.
var weapon_selection: WeaponSelection
## ROUND WON or ROUND LOST, with the fun fact and the MVP, at a round's end.
var win_panel: WinPanel
## Who killed whom with what, in the top right.
var kill_feed: KillFeed
## What part of the match it is, over the health and ammo.
var alert: HudAlert
## Why B would not open the menu, for a moment, under the alert.
var hint: HudAlert
## What E would pick up, under the crosshair, including a bot's bomb.
var use_prompt: UsePrompt
## Ground item selected with sight rays on the last physics frame.
var _pickup_item: String = ""
## Across the middle while dead.
var dead_bar: HudAlert
var damage_indicator: DamageIndicator
var _where: Label
var _frames := FrameMeter.new()
var _notice_left: float = 0.0
## The side your agent in the buy menu was built for.
var _agent_team: String = ""
## The bomb's state and carrier last frame, to see it picked up.
var _bomb_was := C4.State.NONE
var _carrier_was: int = C4.NOBODY
## How long a refusal stays up, in seconds.
const NOTICE_SECONDS := 2.0
## Where the line across the middle while dead starts, down from the top.
const DEAD_BAR_TOP := 580.0


## Every image the HUD's parts ask HudStyle.icon() for by name, to be read
## before the match (images_to_read): the first death drew the dead card's
## skull, the first round won the panel's arrows, a side swap the other
## emblem, each read from the disk on the frame that first drew it. A part
## that draws a new one names it here; tests/run_hud_checks.gd reads the
## parts' scripts and holds this list to them.
const IMAGES: Array[String] = [
	"backgrounds/bluedots_large_png",
	"hud/armor",
	"hud/armor_helmet",
	"hud/teamcounter/armor",
	"hud/teamcounter/armor_helmet",
	"hud/teamcounter/damage-report-frame",
	"hud/teamcounter/teamcounter_botavatar",
	"icons/person",
	"icons/ui/alert",
	"icons/ui/buyzone",
	"icons/ui/ct_logo_1c",
	"icons/ui/elimination",
	"icons/ui/t_logo_1c",
]


## IMAGES, the kill feed's marks and every gun's reserve icon: what is read
## before the match beside the faces and the items' icons.
static func images_to_read() -> Array:
	var images: Array = IMAGES.duplicate()
	images.append_array(KillFeed.ICONS.values())
	images.append_array(TeamCounter.KILLTYPE_ICONS.values())
	images.append(HealthAmmoCenter.reserve_icon(""))
	for gun: String in HealthAmmoCenter.RESERVE_ICONS:
		images.append(HealthAmmoCenter.reserve_icon(gun))
	return images


func _ready() -> void:
	# What the HUD's parts draw is read from the disk now, not on the frame
	# or the tick that first shows it.
	HudStyle.read_ahead(images_to_read())
	# The scope under the rest, so health and ammo stay readable through it.
	scope = ScopeOverlay.new()
	scope.player = player
	add_child(scope)
	_crosshair = Crosshair.new()
	add_child(_crosshair)
	iron_sight = IronSightOverlay.new()
	iron_sight.player = player
	iron_sight.crosshair = _crosshair
	add_child(iron_sight)
	damage_indicator = DamageIndicator.new()
	damage_indicator.player = player
	add_child(damage_indicator)
	if player != null:
		player.hurt.connect(func(_amount: float, _zone: StringName, from: Vector3) -> void:
			damage_indicator.hit_from(from))
	if economy != null:
		# Under the rest of the HUD, as CS2 has it: the team counter and your
		# money stay over the menu; what else the HUD shows goes while it is
		# open (_process).
		buy_menu = BuyMenu.new()
		buy_menu.name = "BuyMenu"
		buy_menu.economy = economy
		buy_menu.userid = userid
		buy_menu.match_state = match_state
		add_child(buy_menu)
		buy_menu.refused.connect(_on_buy_refused)
		if player != null:
			buy_menu.build_agent(player.team)
			_agent_team = player.team
	health_ammo = HealthAmmoCenter.new()
	add_child(health_ammo)
	weapon_selection = WeaponSelection.new()
	add_child(weapon_selection)
	money = MoneyPanel.new()
	money.visible = economy != null
	add_child(money)
	team_counter = TeamCounter.new()
	team_counter.visible = match_state != null
	add_child(team_counter)
	win_panel = WinPanel.new()
	add_child(win_panel)
	kill_feed = KillFeed.new()
	add_child(kill_feed)
	if game != null:
		kill_feed.watch(game, userid)
	alert = HudAlert.new()
	add_child(alert)
	hint = HudAlert.new()
	hint.kind = HudAlert.Kind.HINT
	add_child(hint)
	use_prompt = UsePrompt.new()
	add_child(use_prompt)
	dead_bar = HudAlert.new()
	dead_bar.kind = HudAlert.Kind.NOTE
	dead_bar.top = DEAD_BAR_TOP
	add_child(dead_bar)
	_where = Label.new()
	_where.position = Vector2(12, 8)
	_where.add_theme_font_size_override("font_size", 16)
	_where.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_where.add_theme_constant_override("outline_size", 4)
	add_child(_where)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_where.visible = not _where.visible


func _physics_process(_delta: float) -> void:
	_pickup_item = ""
	var you := player.pawn() if player != null else null
	if game != null and you != null and you.alive and (buy_menu == null or not buy_menu.is_open()):
		_pickup_item = str(game.query(&"use_pickup_item", [you.userid], ""))


func _process(delta: float) -> void:
	_frames.frame(Time.get_ticks_usec())
	var team := player.team if player != null else "T"
	# Driving a bot, the HUD is the bot's: its health, its gun, its money
	# (PlayerSim.pawn).
	var you := player.pawn() if player != null else null
	var you_id := you.userid if you != null and you.userid != GameEvents.NOBODY else userid
	if buy_menu != null:
		buy_menu.userid = you_id
	scope.player = you
	iron_sight.player = you
	if economy != null:
		_show_money(team, delta, you_id)
	if player == null:
		use_prompt.say("")
		return
	var buying := buy_menu != null and buy_menu.is_open()
	if buy_menu != null and not buying and player.team != _agent_team:
		# The sides swapped: your agent is the other side's now.
		buy_menu.build_agent(player.team)
		_agent_team = player.team
	health_ammo.visible = you.alive and not buying
	if you.alive and not buying:
		weapon_selection.show_inventory(team, WeaponSelection.rows_for(you.inventory), you.in_hand_class())
	elif weapon_selection.is_showing():
		weapon_selection.hide_now()
	alert.visible = not buying
	hint.visible = not buying
	dead_bar.visible = not buying
	if you.alive and you.hit_target != null:
		var gun := you.weapon
		var has_ammo := gun != null and gun.data.magazine_size > 0
		health_ammo.show_values(team, player_colour(match_state, you), roundi(you.hit_target.health),
			roundi(you.hit_target.armor), you.hit_target.helmet, gun.data.item_class if gun != null else "",
			has_ammo, gun.ammo if has_ammo else 0, gun.data.magazine_size if has_ammo else 1,
			gun.reserve if has_ammo else 0, gun.data.reserve_as_clips if has_ammo else true,
			has_ammo and gun.is_reloading(SimClock.now_usec()))
	_crosshair.visible = shows_crosshair(you) and not buying
	dead_bar.say("" if you.alive else dead_line(player), "", HudStyle.team_colour(team))
	if match_state != null:
		team_counter.show_match(match_state, player, economy, SimClock.now_usec(), bomb, round_report)
		_show_win_panel(team)
		win_panel.visible = not buying
		var line := alert_line(match_state)
		# The note under the alert gives way to a refusal's bar, which sits there.
		alert.say(line[0], "" if hint.is_showing() else line[1], HudStyle.team_colour(team))
	var carrier: PlayerSim = null
	if bomb != null:
		var picked := bomb_hint(_bomb_was, _carrier_was, bomb, you_id)
		if not picked.is_empty():
			hint.say(picked, "", HudStyle.team_colour("T"))
			_notice_left = NOTICE_SECONDS
		_bomb_was = bomb.state
		_carrier_was = bomb.carrier
		if match_state != null and bomb.state == C4.State.CARRIED:
			for sim in match_state.players:
				if sim.userid == bomb.carrier:
					carrier = sim
	var use_line := "" if buying else UsePrompt.line_for(you, bomb, carrier, _pickup_item,
		game.now_usec() if game != null else SimClock.now_usec())
	use_prompt.say(use_line, UsePrompt.TAKE_BOMB_COLOUR if use_line == UsePrompt.TAKE_BOMB else Color.WHITE)
	if _where.visible:
		_where.text = where_line(you.global_position, player.input.yaw_degrees, player.input.pitch_degrees) \
			+ "\n" + _frames.line()


## The win panel from a round's end until the next starts: who won as you
## see it, the fun fact (or, without one, why the round ended) and the MVP.
func _show_win_panel(team: String) -> void:
	if match_state.phase != MatchState.Phase.ROUND_END:
		win_panel.show_round("")
		return
	var winner := match_state.last_winner
	var report: Dictionary = round_report.last if round_report != null else {}
	var roster: Roster = round_report.game.roster if round_report != null and round_report.game != null else null
	var fact := WinPanel.fun_fact_text(String(report.get("funfact_token", "")),
		name_of(roster, int(report.get("funfact_player", GameEvents.NOBODY))), int(report.get("funfact_data1", 0)))
	if fact.is_empty():
		fact = WinPanel.reason_text(GameEvents.round_end_reason(match_state.last_reason))
	var mvp := int(report.get("mvp", GameEvents.NOBODY))
	var mvp_node: Node = roster.player(mvp) if roster != null and mvp != GameEvents.NOBODY else null
	# A bot's name carries CS2's clan tag, "[BOT] Efe" on its screenshot.
	var mvp_name := ((KillFeed.BOT_TAG if mvp_node is Bot else "") + name_of(roster, mvp)) if mvp_node != null else ""
	win_panel.show_round(WinPanel.title_for(winner, team), winner, team != winner, fact, mvp_name,
		WinPanel.mvp_reason_text(int(report.get("mvp_reason", 0))),
		roster.team_of(mvp) if mvp_node != null else winner, mvp_node is Bot)


## A player's name as the HUD shows it: their node's; empty for nobody.
static func name_of(roster: Roster, who: int) -> String:
	if roster == null or who == GameEvents.NOBODY:
		return ""
	var node := roster.player(who)
	return str(node.name) if node != null else ""


## CS2's hint as you pick up the bomb from the ground, "You picked up the
## bomb" (research round-bomb-grenades.md 1.6), from how the bomb was last
## frame and is now; "" otherwise. Being handed it at a round's start says
## nothing here: your card's C4 shows it (TeamCounter).
static func bomb_hint(was: C4.State, carrier_was: int, c4: C4, you: int) -> String:
	var yours := c4.state == C4.State.CARRIED and c4.carrier == you
	if yours and was == C4.State.DROPPED and carrier_was != you:
		return "You picked up the bomb"
	return ""


## Whether the crosshair is drawn: not for a sniper (the game's
## m_bShowCrosshair), whose aim is its scope, nor through the scope, nor
## while an AUG or SG 553 is up at the eye, whose aim is its dot.
static func shows_crosshair(who: PlayerSim) -> bool:
	if who.weapon == null:
		return true
	return who.weapon.data.shows_crosshair and not ScopeOverlay.shown_for(who) \
		and IronSightOverlay.amount_for(who) <= 0.0


## Your money, with the cart while you may buy; and a refusal, for a
## moment.
func _show_money(team: String, delta: float, whose: int) -> void:
	var may_buy := economy.shop_refusal(whose) == Economy.OK
	money.show_values(team, economy.money(whose), may_buy and not buy_menu.is_open())
	_notice_left = maxf(_notice_left - delta, 0.0)
	if _notice_left == 0.0:
		hint.say("")


static func money_text(amount: int) -> String:
	return "$%d" % amount


## A player's colour among their team (CS2's cl_teammate_color_1 to 5), as
## the match drew it for them (MatchState.colour_of). Where there is no match
## of teams there are no player colours, and CS2 shows the team's own (its
## deathmatch: the ring round the emblem gold for a terrorist and light blue
## for a counter-terrorist, like the rest of the HUD).
static func player_colour(state: MatchState, who: PlayerSim) -> Color:
	var index := state.colour_of(who) if state != null else -1
	if index < 0:
		return HudStyle.team_colour(who.team)
	return HudStyle.TEAMMATE_COLOURS[index % HudStyle.TEAMMATE_COLOURS.size()]


## The gun a player's card shows: their primary, else their pistol; none
## while dead.
static func best_weapon(who: PlayerSim) -> String:
	if not who.alive or who.inventory == null:
		return ""
	var best := who.inventory.best_gun()
	return best.item_class() if best != null else ""


## Every grenade a player carries, one class per grenade.
static func grenades_of(who: PlayerSim) -> PackedStringArray:
	var out := PackedStringArray()
	if not who.alive or who.inventory == null:
		return out
	for entry in who.inventory.items_in(ItemDef.Slot.GRENADE):
		for i in entry.count:
			out.append(entry.item_class())
	return out


func _on_buy_refused(why: StringName) -> void:
	hint.say(Economy.MESSAGES.get(why, ""), "", HudStyle.DAMAGE_RED)
	_notice_left = NOTICE_SECONDS


## What the line across the middle says while you are dead: when you are
## back, or, with no respawn coming, how you are watching and the keys CS2's
## spectator bar names (PANOHUD_Spectate_Navigation_*): fire the next
## player, the right button the one before, jump the camera, and E to take
## over the bot watched where you may.
static func dead_line(dead: PlayerSim) -> String:
	if dead.respawns:
		return "You died. Back in %d" % ceili(dead.seconds_to_respawn())
	if dead.observer_mode == PlayerSim.ObserverMode.ROAMING:
		return "Free Look    fire: watch a teammate    jump: camera"
	var watched := dead.observing
	if watched == null or not is_instance_valid(watched):
		return "You died    jump: free look" if dead.free_look else "You died"
	var mode := "Chase Camera" if dead.observing_chase else "First Person"
	var line := "Watching %s (%s)    fire: next    right: previous    jump: camera" % [watched.name, mode]
	if dead.can_control(watched):
		line += "    E: control bot"
	return line


## A clock the way CS2 draws it: minutes and seconds, the seconds rounded up
## so it reads 0:00 only when time is out.
static func clock_text(seconds: float) -> String:
	var whole := ceili(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [whole / 60, whole % 60]


## The alert over the health and ammo: which part of the match this is,
## and under it, where there is one, a smaller note. Warmup says so, as CS2
## does; freeze time gives the round and its announcement (CS2's alerts
## "Match point", "Final round", "Last round of first half"); a live round
## has none; the round's end says who won, the match's end the result.
static func alert_line(state: MatchState) -> PackedStringArray:
	match state.phase:
		MatchState.Phase.WARMUP:
			return PackedStringArray(["Warmup", "F5 starts the match"])
		MatchState.Phase.FREEZE:
			var round_name := "Round %d" % state.round_number if not state.in_overtime() \
				else "Round %d, overtime" % state.round_number
			var announced: String = {
				&"round_announce_match_start": "Match start",
				&"round_announce_final": "Final round",
				&"round_announce_match_point": "Match point",
				&"round_announce_last_round_half": "Last round of first half",
			}.get(state.announce_round(), "")
			return PackedStringArray([announced if not announced.is_empty() else round_name,
				round_name if not announced.is_empty() else ""])
		MatchState.Phase.ROUND_END:
			# Who won is the win panel's (WinPanel); the alert says only
			# that the sides swap.
			if state.swapping_next():
				return PackedStringArray(["Half time", "The sides swap"])
		MatchState.Phase.OVER:
			if state.winner.is_empty():
				return PackedStringArray(["Draw", "%d to %d" % [state.score("T"), state.score("CT")]])
			return PackedStringArray(["%s win the match" % side_name(state.winner), "%d to %d" % [
				state.score(state.winner), state.score(MatchState.other(state.winner)),
			]])
	return PackedStringArray(["", ""])


static func side_name(side: String) -> String:
	return "Counter-terrorists" if side == "CT" else "Terrorists"


## Where a player is and looks, in one line: the feet's position in units,
## the yaw from 0 to 360 and the pitch, up positive.
static func where_line(position: Vector3, yaw_degrees: float, pitch_degrees: float) -> String:
	return "pos %.1f %.1f %.1f   yaw %.1f   pitch %.1f" % [
		position.x, position.y, position.z, fposmod(yaw_degrees, 360.0), pitch_degrees,
	]

