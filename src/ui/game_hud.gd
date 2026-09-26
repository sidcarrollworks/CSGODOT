class_name GameHud
extends CanvasLayer

## The HUD, laid out as today's CS2 lays it out (reference/cs2 _screenshots/
## In_game_ui.webp; the layout's regions are in
## reference/research/round-hud-bots.md A0): health, armour and ammo in one
## cluster at the bottom in the middle round the team's emblem
## (HealthAmmoCenter); your money in the bottom left with the buy zone's
## cart while you may buy (MoneyPanel); in a match, the clock, the scores,
## who is alive and a card for each player at the top in the middle
## (TeamCounter), and a bar over the cluster saying what part of the match
## it is (HudAlert: warmup, the round's announcement, who won). A red arc
## round the crosshair on the side each hit came from; when dead, a bar
## across the middle counting down to the respawn or saying whom you are
## watching; and CS2's buy menu on B, over the rest. The rest of a round's
## HUD (the kill feed, the radar, the scoreboard) is roadmap item 15.
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
## CS2's buy menu (B), over the rest of the HUD; null without an economy.
var buy_menu: BuyMenu

var _crosshair: Crosshair
## A sniper's scope, over the view while scoped in.
var scope: ScopeOverlay
var health_ammo: HealthAmmoCenter
var money: MoneyPanel
var team_counter: TeamCounter
## What part of the match it is, over the health and ammo.
var alert: HudAlert
## Why B would not open the menu, for a moment, under the alert.
var hint: HudAlert
## Across the middle while dead.
var dead_bar: HudAlert
var damage_indicator: DamageIndicator
var _where: Label
var _frames := FrameMeter.new()
var _notice_left: float = 0.0
## The side your agent in the buy menu was built for.
var _agent_team: String = ""
## How long a refusal stays up, in seconds.
const NOTICE_SECONDS := 2.0
## Where the line across the middle while dead starts, down from the top.
const DEAD_BAR_TOP := 580.0


func _ready() -> void:
	# The scope under the rest, so health and ammo stay readable through it.
	scope = ScopeOverlay.new()
	scope.player = player
	add_child(scope)
	_crosshair = Crosshair.new()
	add_child(_crosshair)
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
	money = MoneyPanel.new()
	money.visible = economy != null
	add_child(money)
	team_counter = TeamCounter.new()
	team_counter.visible = match_state != null
	add_child(team_counter)
	alert = HudAlert.new()
	add_child(alert)
	hint = HudAlert.new()
	hint.kind = HudAlert.Kind.HINT
	add_child(hint)
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


func _process(delta: float) -> void:
	_frames.frame(Time.get_ticks_usec())
	var team := player.team if player != null else "T"
	if economy != null:
		_show_money(team, delta)
	if player == null:
		return
	var buying := buy_menu != null and buy_menu.is_open()
	if buy_menu != null and not buying and player.team != _agent_team:
		# The sides swapped: your agent is the other side's now.
		buy_menu.build_agent(player.team)
		_agent_team = player.team
	health_ammo.visible = player.alive and not buying
	alert.visible = not buying
	hint.visible = not buying
	dead_bar.visible = not buying
	if player.alive and player.hit_target != null:
		var gun := player.weapon
		var has_ammo := gun != null and gun.data.magazine_size > 0
		health_ammo.show_values(team, player_colour(match_state, player), roundi(player.hit_target.health),
			roundi(player.hit_target.armor), player.hit_target.helmet, gun.data.item_class if gun != null else "",
			has_ammo, gun.ammo if has_ammo else 0, gun.data.magazine_size if has_ammo else 1,
			gun.reserve if has_ammo else 0, gun.data.reserve_as_clips if has_ammo else true,
			has_ammo and gun.is_reloading(SimClock.now_usec()))
	_crosshair.visible = shows_crosshair(player) and not buying
	dead_bar.say("" if player.alive else dead_line(player), "", HudStyle.team_colour(team))
	if match_state != null:
		team_counter.show_match(match_state, player, economy, SimClock.now_usec())
		var line := alert_line(match_state)
		# The note under the alert gives way to a refusal's bar, which sits there.
		alert.say(line[0], "" if hint.is_showing() else line[1], HudStyle.team_colour(team))
	if _where.visible:
		_where.text = where_line(player.global_position, player.input.yaw_degrees, player.input.pitch_degrees) \
			+ "\n" + _frames.line()


## Whether the crosshair is drawn: not for a sniper (the game's
## m_bShowCrosshair), whose aim is its scope, nor through the scope.
static func shows_crosshair(who: PlayerSim) -> bool:
	if who.weapon == null:
		return true
	return who.weapon.data.shows_crosshair and not ScopeOverlay.shown_for(who)


## Your money, with the cart while you may buy; and a refusal, for a
## moment.
func _show_money(team: String, delta: float) -> void:
	var may_buy := economy.shop_refusal(userid) == Economy.OK
	money.show_values(team, economy.money(userid), may_buy and not buy_menu.is_open())
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
## back, or, with no respawn coming, whose eyes you are in and how to move
## on.
static func dead_line(dead: PlayerSim) -> String:
	if dead.respawns:
		return "You died. Back in %d" % ceili(dead.seconds_to_respawn())
	var watched := dead.observing
	if watched == null or not is_instance_valid(watched):
		return "You died"
	return "Watching %s    fire: next    jump: %s" % [
		watched.name, "their eyes" if dead.observing_chase else "from behind",
	]


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
			return PackedStringArray(["%s win" % side_name(state.last_winner),
				"Half time: the sides swap" if state.swapping_next() else ""])
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

