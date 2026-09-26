class_name BotSteering
extends RefCounted

## How a bot makes way for its own side: the layer between following its
## path and building its command that Booth's GDC 2004 talk on CS's bot
## calls reactive obstacle avoidance ("Pathfinding -> Path Following ->
## Reactive Obstacle Avoidance Behavior -> Generation of Movement Commands",
## reference/research/round-hud-bots.md B4). CS2's bot keeps the same
## fields (m_isFriendInTheWay, m_avoidFriendTimer, m_politeTimer,
## m_isWaitingBehindFriend).
##
## Teammates' hulls are solid to each other, as CS2's are
## (mp_solid_teammates 1), and a head-on meeting of two axis-aligned boxes
## clips both velocities to nothing, so without this two bots whose paths
## cross push at each other forever (reference/playtest-2026-09-25.md,
## issue 6). Given the way a bot means to walk, this says which way to walk
## instead:
##
## - a friend ahead going the same way: follow it at a gap, never pass
##   through it (FOLLOW);
## - a friend ahead coming towards it or standing: as Sid saw CS2's bots do
##   it (2026-09-26, the playtest page's issue 6), it walks on until they
##   bump, backs up a moment (BACK_UP), goes forward again (RETRY), and if
##   the friend is still in the way, goes forward and to the side, away
##   from the friend's side, and to its own right when they are square on,
##   so both keep right and a head-on pair parts the same way every time
##   (SIDESTEP). The stage it is at is kept in a Memory the bot holds;
##   without one it steps aside at once;
## - no room on the nav mesh to step aside (a doorway one hull wide): the one
##   with the higher userid backs off the way it came until there is room
##   (YIELD), and the other holds until the way clears (WAIT). Whoever the
##   friend is and whatever it is doing, so two that meet always settle it.
##
## It reads only plain data (positions, velocities, userids and the nav
## mesh) and traces nothing, so it costs a server no hull traces and can move
## into the planned BotBrain (reference/systemization.md step 3.4) whole.
##
## Its distances are choices: CS2's are in no file this project has, and
## Booth's slides give the method, not the numbers. Sid can pin them with
## CS2's own bot (bot_goto_mark, the playtest page's issue 6, Local part).

enum { CLEAR, SIDESTEP, FOLLOW, WAIT, YIELD, BACK_UP, RETRY }

## Where a bot is in making way for a friend coming at it or standing:
## walking on, backing up, going forward again, or stepping aside.
enum { WALKING_ON, BACKING_UP, RETRYING, STEPPING_ASIDE }

## A friend counts as in the way this far ahead along the bot's heading, in
## units: three hull widths. A choice.
const LOOK_AHEAD := 96.0
## And this close to its line either side: two half hulls (16 + 16) and a
## margin, so a friend that would brush it counts. A choice.
const IN_THE_WAY := 40.0
## Friends more than this far above or below are on another floor.
const SAME_FLOOR := 64.0
## Room to step aside is floor on the nav mesh over from the bot by its
## share of what the two need to be IN_THE_WAY apart (half, since the friend
## steps too), up to this far, in units. The mesh is already the hull's
## half width in from every wall (it is eroded by it), so no trace is
## needed. A choice.
const SIDE_PROBE := 16.0
## Hulls this far apart across the line are clear of each other (16 + 16
## and a hair): with no more room to step, it walks on past.
const CLEAR_ACROSS := 33.0
## The floor there may be this far up or down: a stair's step and a bit.
const SIDE_FLOOR := 24.0
## Two hulls touching, centre to centre: at or inside this a sidestep is
## sideways only, since any forward is into the friend.
const CONTACT := 36.0
## Following a friend it keeps this far behind, centre to centre, in units:
## a hull and a half between them. A choice.
const FOLLOW_GAP := 56.0
## A friend moving along the bot's heading faster than this, in units per
## second, is going its way; slower the other way, it is coming at it.
## The stuck speed, so a friend that has stopped counts as standing.
const MOVING := 20.0
## A friend within this of the bot's line is square on to it.
const SQUARE_ON := 4.0
## A friend this close ahead, centre to centre, has bumped it (two half
## hulls, 32, and a margin).
const BUMPED := 40.0
## Bumped, it backs up this long, then goes forward again for up to
## RETRY_SECONDS before stepping aside if the friend is still in the way.
## Choices: Sid saw the order in CS2 (back up, forward again, then forward
## and to the side), not the timings.
const BACK_UP_SECONDS := 0.3
const RETRY_SECONDS := 0.5


## What a bot remembers of making way from one tick to the next: the stage
## and the tick it ends on (-1 for none).
class Memory:
	var stage: int = WALKING_ON
	var until: int = -1

	func reset() -> void:
		stage = WALKING_ON
		until = -1


## What steer() decided: the way to walk (flat, unit or zero), why, and
## which friend it was making way for (its index in the lists given; -1
## when the way was clear).
class Steer:
	var way := Vector3.ZERO
	var mode: int = CLEAR
	var friend: int = -1


## Which way a bot at `position` walks this tick when it means to walk `way`,
## given its own side's living players (not itself) as parallel lists of
## positions, velocities and userids, and the floor it walks on (null walks
## without one, and always has room). `memory` carries its stage from tick
## to tick on the world's `tick`; null steps aside at once.
static func steer(
	position: Vector3,
	way: Vector3,
	userid: int,
	positions: PackedVector3Array,
	velocities: PackedVector3Array,
	userids: PackedInt32Array,
	nav_mesh: SourceNavMesh,
	memory: Memory = null,
	tick: int = 0
) -> Steer:
	var out := Steer.new()
	var heading := Vector3(way.x, 0.0, way.z)
	if heading.length_squared() < 1e-6:
		return out
	heading = heading.normalized()
	out.way = heading
	# The game's yaw 0 looks down -Z with +X to the right, so a heading's
	# right is (-z, 0, x).
	var right := Vector3(-heading.z, 0.0, heading.x)

	var nearest := -1
	var nearest_along := INF
	var its_side := 0.0
	for i in positions.size():
		var offset := positions[i] - position
		if absf(offset.y) > SAME_FLOOR:
			continue
		var along := offset.x * heading.x + offset.z * heading.z
		var side := offset.x * right.x + offset.z * right.z
		if along <= 0.0 or along > LOOK_AHEAD or absf(side) >= IN_THE_WAY:
			continue
		if along < nearest_along:
			nearest = i
			nearest_along = along
			its_side = side
	if nearest < 0:
		# Backing up can take it out of the look ahead: it finishes backing
		# up, and goes forward again till the friend is back in the way or
		# its time is up.
		if memory != null and memory.stage == BACKING_UP and not _next_stage(memory, tick):
			out.mode = BACK_UP
			out.way = -heading
		elif memory != null and memory.stage == RETRYING and tick < memory.until:
			out.mode = RETRY
		elif memory != null:
			memory.reset()
		return out
	out.friend = nearest

	var their_along := velocities[nearest].x * heading.x + velocities[nearest].z * heading.z
	# Going its way: it follows, and holds at the gap. Not once they have
	# bumped, since a friend backing up out of the bump is going its way
	# only for a moment: it sees the bump out.
	if their_along > MOVING and (memory == null or memory.stage == WALKING_ON):
		out.mode = FOLLOW
		out.way = heading if nearest_along > FOLLOW_GAP else Vector3.ZERO
		return out

	if memory != null:
		var bumped := nearest_along < BUMPED
		if memory.stage == WALKING_ON:
			if not bumped:
				return out
			memory.stage = BACKING_UP
			memory.until = tick + _ticks(BACK_UP_SECONDS)
		if memory.stage == BACKING_UP:
			if not _next_stage(memory, tick):
				out.mode = BACK_UP
				out.way = -heading
				return out
		if memory.stage == RETRYING:
			if not bumped and tick < memory.until:
				out.mode = RETRY
				return out
			memory.stage = STEPPING_ASIDE
			memory.until = -1

	# Coming at it, or standing: aside, away from the friend, to its right
	# when square on; the friend's side only when the friend is near enough
	# its line that stepping there still clears it.
	var away := 1.0 if absf(its_side) <= SQUARE_ON else -signf(its_side)
	var sides := [away]
	if absf(its_side) < IN_THE_WAY * 0.5:
		sides.append(-away)
	var needed := clampf((IN_THE_WAY - absf(its_side)) * 0.5, 1.0, SIDE_PROBE)
	for direction: float in sides:
		var step := right * direction
		if has_room(nav_mesh, position, step, needed):
			out.mode = SIDESTEP
			var forward := clampf((nearest_along - CONTACT) / (LOOK_AHEAD - CONTACT), 0.0, 1.0)
			out.way = (heading * forward + step).normalized()
			return out
	if absf(its_side) >= CLEAR_ACROSS:
		# Stepped as far as the floor goes, and clear of it: on past.
		out.mode = SIDESTEP
		return out

	# No room either side. The higher userid backs off the way it came; the
	# other holds while it makes way.
	if userid > userids[nearest]:
		out.mode = YIELD
		out.way = -heading
	else:
		out.mode = WAIT
		out.way = Vector3.ZERO
	return out


## Moves a bot backing up on to going forward again once its time is up;
## whether it did.
static func _next_stage(memory: Memory, tick: int) -> bool:
	if memory.stage != BACKING_UP or tick < memory.until:
		return false
	memory.stage = RETRYING
	memory.until = tick + _ticks(RETRY_SECONDS)
	return true


static func _ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds / SimClock.tick_seconds()))


## Whether there is floor on the nav mesh `across` units over from
## `position` towards `step` (flat, unit), about as high as its feet. No
## mesh, room.
static func has_room(nav_mesh: SourceNavMesh, position: Vector3, step: Vector3, across: float = SIDE_PROBE) -> bool:
	if nav_mesh == null:
		return true
	return nav_mesh.area_at(position + step * across, SIDE_FLOOR, SIDE_FLOOR) != null
