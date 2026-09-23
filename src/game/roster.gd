class_name Roster
extends RefCounted

## Who is playing, each by a userid: an int given in the order they joined
## (0, 1, 2 ...) and kept for the match. Events, damage, inventories and
## accounts name players by it, never by node, so what they hold is plain
## data. Finding players goes through here rather than a scan of a group.
##
## A player is whatever node the game has for them (a PlayerSim), with the
## HitTarget that takes their damage, which is told its userid here.

var _players := {}
var _hit_targets := {}
var _ids: Array[int] = []
var _next: int = 0


## Adds a player, and returns the userid they now have.
func add(player: Node3D, hit_target: HitTarget = null) -> int:
	var existing := userid_of(player)
	if existing != GameEvents.NOBODY:
		return existing
	var userid := _next
	_next += 1
	_players[userid] = player
	_ids.append(userid)
	if hit_target != null:
		_hit_targets[userid] = hit_target
		hit_target.userid = userid
	return userid


## Takes a player out (a disconnect). Their userid is never given again.
func remove(userid: int) -> void:
	_players.erase(userid)
	_hit_targets.erase(userid)
	_ids.erase(userid)


func player(userid: int) -> Node3D:
	return _players.get(userid)


func hit_target(userid: int) -> HitTarget:
	return _hit_targets.get(userid)


## A player's userid, or GameEvents.NOBODY for someone not on it.
func userid_of(player_node: Node) -> int:
	for userid in _ids:
		if _players[userid] == player_node:
			return userid
	return GameEvents.NOBODY


## Every userid, in the order they joined. A copy.
func ids() -> Array[int]:
	return _ids.duplicate()


## The side a player is on, as their node says ("T" or "CT"); "" for
## someone not on it or a node with no side.
func team_of(userid: int) -> String:
	var node := player(userid)
	if node == null:
		return ""
	var team = node.get(&"team")
	return team if team is String else ""


## Everyone on a side, by userid, in the order they joined.
func on_team(team: String) -> Array[int]:
	var out: Array[int] = []
	for userid in _ids:
		if team_of(userid) == team:
			out.append(userid)
	return out
