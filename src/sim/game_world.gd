class_name GameWorld
extends Node

## The simulation's owner: it runs the tick.
##
## Every tick it asks each player for one command (your keys, a bot's
## choices, later what a client sends: PlayerSim.command_for), runs the
## players one after another in the order they joined, and then the rules on
## the tick they have just run: the match, and after it the economy when
## there is one (roadmap item 13). No player ticks itself and neither does the
## match, so nothing that decides the game runs anywhere else, and the order
## things run in is this one rather than whatever order they were added to the
## scene. It is what CS2's server is to its players; single player is this
## running on the same machine as the one who plays, a listen server.
##
## It counts its own ticks from the moment it starts, and SimClock reads the
## count, so simulation time starts with the game rather than with the
## process, and a check can hold the world and step it itself (step()). What
## is only drawn or heard of the players (the view, footsteps, ragdolls) runs
## on the engine's ticks as before, after the world's, so it reads the tick
## just run.
##
## It also holds what a tick gives out, so each tick starts afresh: the nav
## mesh's path searches, and the game's shared state (game): its events,
## its simulated things (grenades, the bomb, dropped guns), who is playing
## and what each carries, and the systems that run after the match
## (reference/systems/contracts.md).

## How many paths over the nav mesh may be searched for in one tick. A search
## takes half a millisecond, and at a round's start every bot wants one on the
## same tick: nine to twenty searches, a tick of five to ten ms. The rest wait
## a tick or two, standing, which freeze time hides.
const PATH_SEARCHES_PER_TICK := 2

## The world being run, whose tick SimClock reads: the last one into the
## scene tree. There is one at a time, as a server runs one match.
static var current: GameWorld

## Everyone in the game, in the order they run in a tick, which is the order
## they joined in.
var players: Array[PlayerSim] = []

## The match, run after the players every tick; null where there is none
## (the test range). Everyone in the world is in it, whenever they joined,
## and it says what the round is doing into the world's events.
var match_state: MatchState:
	set(value):
		if is_instance_valid(match_state) and match_state != value:
			match_state.events = null
		match_state = value
		if value != null:
			value.events = game.events
			for player in players:
				value.add_player(player)

## The tick being run, or between ticks the last one run. The first is 1.
var tick: int = 0

## The game's events, entities, roster, inventories and systems, stepped at
## the end of every tick, after the match (GameSystems.step).
var game := GameSystems.new()

var _path_searches_left: int = PATH_SEARCHES_PER_TICK


func _init() -> void:
	# Before every other node's physics callback, so what is drawn or heard of
	# the players reads the tick they have just run.
	process_physics_priority = -1000


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Someone joins, to run from the next tick on, after everyone already here.
func add_player(player: PlayerSim) -> void:
	if players.has(player):
		return
	players.append(player)
	player.world = self
	player.userid = game.add_player(player, player.hit_target, player.inventory)
	# What is in hand is drawn on this world's clock, from now.
	player.draw_again()
	if match_state != null:
		match_state.add_player(player)


## Someone leaves the game, and its match; a player out of the scene tree
## leaves by itself.
func remove_player(player: PlayerSim) -> void:
	players.erase(player)
	game.roster.remove(game.roster.userid_of(player))
	if player.world == self:
		player.world = null
		player.userid = GameEvents.NOBODY
	if is_instance_valid(match_state):
		match_state.remove_player(player)


func _physics_process(_delta: float) -> void:
	step()


## One tick: each player's command run, in order, then the rules.
func step() -> void:
	begin_tick()
	var dt := SimClock.tick_seconds()
	for player: PlayerSim in players.duplicate():
		if player.is_inside_tree():
			player.run_command(player.command_for(tick, dt), dt)
	end_tick()


## A tick starts: its number, and what it has to give out.
func begin_tick() -> void:
	tick += 1
	_path_searches_left = PATH_SEARCHES_PER_TICK


## The tick ends, every player having run it: the match judges it, then the
## game's own systems run and the tick's events are handed out.
func end_tick() -> void:
	if is_instance_valid(match_state):
		match_state.tick(SimClock.tick_end_usec(tick))
	var viewport := get_viewport() if is_inside_tree() else null
	game.step(tick, viewport.find_world_3d().direct_space_state if viewport != null else null)


## Whether a path over the nav mesh may be searched for this tick, counting
## the search if so (PATH_SEARCHES_PER_TICK).
func may_search_path() -> bool:
	if _path_searches_left <= 0:
		return false
	_path_searches_left -= 1
	return true
