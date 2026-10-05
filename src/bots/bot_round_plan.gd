class_name BotRoundPlan
extends RefCounted

## Competitive's round goals, on the tick thread before worker thinking.
## Navigation and combat remain Bot's. Timings, lane allocation and search
## order are implementation choices, not a decompilation of CS2's AI.
enum Task { OPENING, HUNT, PICKUP, PLANT, RETAKE, DEFUSE, GUARD }
const REVIEW_SECONDS := 0.5
const HOLD_SECONDS := 8.0
const MEMORY_SECONDS := 10.0
const USE_DISTANCE := 48.0

var bomb_system: BombSystem
var data: Dictionary
var slot: int
var task: Task = Task.OPENING
var active := false
var look_at := Vector3.ZERO
var _round := -1
var _next_review := -1
var _signature: Array = []
var _goal_key := ""
var _arrived_tick := -1
var _investigated_tick := -1
var _search_cursor := 0

func _init(system: BombSystem = null, map_data: Dictionary = {}, nth: int = 0) -> void:
	bomb_system = system
	data = map_data
	slot = nth

func reset() -> void:
	_round = -1
	_signature.clear()
	_next_review = -1
	_goal_key = ""
	_arrived_tick = -1
	_investigated_tick = -1
	active = false

func update(bot: Bot, tick: int) -> void:
	var match_state := bot.world.match_state
	active = match_state != null and match_state.phase == MatchState.Phase.LIVE
	if not active:
		return
	if _round != match_state.round_number:
		reset()
		active = true
		_round = match_state.round_number
		_search_cursor = posmod(slot + _round, maxi(1, (data["search"] as PackedVector3Array).size()))
		var lanes: Array = data["lanes"][bot.team]
		var lane: PackedVector3Array = lanes[posmod(slot + _round - 1, lanes.size())]
		_goal(bot, "opening", Task.OPENING, lane)
	var bomb := bomb_system.bomb
	var signature: Array = [bomb.state, bomb.carrier, bomb.defuser, bot.team]
	if tick < _next_review and signature == _signature:
		return
	_signature = signature
	_next_review = tick + SimClock.ticks_in(REVIEW_SECONDS)
	if bomb.state == C4.State.PLANTED:
		if bot.team == "CT":
			if assigned(bot.world.players, "CT", bomb.position, bomb.defuser, true) == bot.userid:
				_goal(bot, "defuse", Task.DEFUSE, PackedVector3Array([bomb.position]))
			else:
				_guard(bot, bomb.position, Task.RETAKE)
		else:
			_guard(bot, bomb.position, Task.GUARD)
		return
	if bot.team == "T":
		if bomb.state == C4.State.DROPPED and not defers(bot.world.players, bomb.rules.bot_defer_to_human_items) \
				and assigned(bot.world.players, "T", bomb.position) == bot.userid:
			_goal(bot, "pickup", Task.PICKUP, PackedVector3Array([bomb.position]))
			return
		if bomb.carrier == bot.userid and not defers(bot.world.players, bomb.rules.bot_defer_to_human_goals) \
				and not (data["plant_sites"] as PackedVector3Array).is_empty():
			var sites: PackedVector3Array = data["plant_sites"]
			var site_index := posmod(hash(["bot_plant_site", _round]), sites.size())
			var site := sites[site_index]
			# Keep an opening lane to the chosen site, rather than cutting
			# straight through Mid just because its path is shorter.
			var lanes: Array = data["lanes"]["T"]
			var choices: Array[PackedVector3Array] = []
			for lane: PackedVector3Array in lanes:
				if lane[-1].distance_to(data["sites"][site_index]) < 8.0:
					choices.append(lane)
			var route := PackedVector3Array([site])
			if not choices.is_empty():
				route = choices[posmod(slot, choices.size())].duplicate()
				route[-1] = site
			_goal(bot, "plant", Task.PLANT, route)
			return
	# Pursue a position actually seen, never an enemy's hidden current pose.
	if bot.last_enemy_tick > _investigated_tick and tick - bot.last_enemy_tick < SimClock.ticks_in(MEMORY_SECONDS):
		_goal(bot, "enemy", Task.HUNT, PackedVector3Array([bot.last_enemy_position]))
		if bot.round_goal_reached:
			_investigated_tick = bot.last_enemy_tick
		return
	if task in [Task.DEFUSE, Task.RETAKE, Task.GUARD, Task.PICKUP, Task.PLANT]:
		_search(bot)
	elif bot.round_goal_reached or bot.round_path_failed():
		if _arrived_tick < 0:
			_arrived_tick = tick
		if task != Task.OPENING or tick - _arrived_tick >= SimClock.ticks_in(HOLD_SECONDS):
			_search(bot)

func _guard(bot: Bot, centre: Vector3, role: Task) -> void:
	var spot := Competitive.site_spot(bot.nav_mesh, centre, bot.team, slot + 10)
	_goal(bot, "guard", role, PackedVector3Array([spot]))
	look_at = data["enemy_spawn"][bot.team]

func _search(bot: Bot) -> void:
	var points: PackedVector3Array = data["search"]
	if points.is_empty():
		return
	var index := posmod(_search_cursor, points.size())
	_search_cursor += 1
	_goal(bot, "search_%d" % _search_cursor, Task.HUNT, PackedVector3Array([points[index]]))
	look_at = data["enemy_spawn"][bot.team]

func _goal(bot: Bot, key: String, role: Task, points: PackedVector3Array) -> void:
	task = role
	# Small changes in a moving enemy/bomb don't discard a path every review.
	if key == _goal_key and not bot.route.is_empty() and bot.route[-1].distance_to(points[-1]) < 32.0:
		return
	_goal_key = key
	_arrived_tick = -1
	look_at = points[-2] if points.size() > 1 else data["enemy_spawn"][bot.team]
	bot.set_round_route(points)

## A stable assignment, preserving an active defuser. Human-controlled bots
## are left to their controller; a kit is preferred within 200 units.
static func assigned(players: Array[PlayerSim], side: String, at: Vector3, current: int = C4.NOBODY,
		prefer_kit: bool = false) -> int:
	var chosen := C4.NOBODY
	var nearest := INF
	for player in players:
		if not player.alive or player.team != side:
			continue
		if player.userid == current:
			return current
		if not player.is_bot or is_instance_valid(player.controlled_by):
			continue
		var score := player.global_position.distance_to(at)
		if prefer_kit and not player.inventory.has_defuser:
			score += 200.0
		if score < nearest or (is_equal_approx(score, nearest) and player.userid < chosen):
			chosen = player.userid
			nearest = score
	return chosen

static func defers(players: Array[PlayerSim], enabled: bool) -> bool:
	if enabled:
		for player in players:
			if player.alive and player.team == "T" and (not player.is_bot or is_instance_valid(player.controlled_by)):
				return true
	return false

## Called during worker thinking, writing only this bot's UserCmd. A plant
## or defuse goes through BombSystem's usual held-button/angle checks.
func objective_command(bot: Bot, cmd: UserCmd) -> bool:
	if not active or bot.frozen:
		return false
	var bomb := bomb_system.bomb
	if task == Task.PLANT and bomb.state == C4.State.CARRIED and bomb.carrier == bot.userid and bot.on_ground:
		var in_site := false
		for site in bomb_system.sites:
			in_site = in_site or site.contains(bot.global_position)
		if in_site:
			cmd.buttons |= UserCmd.DUCK
			if bot.in_hand_class() != "weapon_c4":
				cmd.weapon_select = int(ItemDef.Slot.C4) + 1
			elif bot.hand_ready():
				cmd.buttons |= UserCmd.ATTACK
			return true
	if task not in [Task.DEFUSE, Task.PICKUP] or bot.global_position.distance_to(bomb.position) > USE_DISTANCE:
		return false
	if task == Task.DEFUSE and bomb.state != C4.State.PLANTED:
		return false
	if task == Task.PICKUP and bomb.state != C4.State.DROPPED:
		return false
	# Once begun, keep defusing. Before that, fight an already acquired enemy.
	if task == Task.DEFUSE and bomb.defuser != bot.userid and is_instance_valid(bot.target):
		return false
	var angles := PlayerInput.angles_from_direction(bomb.position - (bot.global_position + Vector3.UP * bot.eye_height()))
	cmd.yaw_degrees = angles.x
	cmd.pitch_degrees = angles.y
	cmd.buttons |= UserCmd.USE
	if bot.last_command == null or not bot.last_command.held(UserCmd.USE):
		cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.USE, true, 0.0, angles.x, angles.y))
	return true
