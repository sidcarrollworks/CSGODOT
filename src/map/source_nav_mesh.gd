class_name SourceNavMesh
extends RefCounted

## A map's nav mesh as CS2 ships it: maps/<map>.nav in the map's VPK
## (scripts/extract_assets.sh nav), the floor the game's own bots walk. It is
## cut into areas, convex polygons of three or four corners on dust2 (2,242 of
## them), and each edge of an area carries links to the areas across it. The
## links are the path graph.
##
## Valve does not document the format. This follows Source 2 Viewer's reader
## (ValveResourceFormat/NavMesh/NavMeshFile.cs, MIT), which takes versions 30
## to 36; dust2's is 36. Between the sections, and at the end, the file keeps
## blocks of KV3 (the game's KeyValues3, binary), which this steps over rather
## than reads. The last is the game's analysis of the mesh: hiding spots,
## where the two sides meet on each route, which areas lead into which, and
## how early each team can reach each area. `analysis_bytes` says how big it
## is; reading it needs a KV3 reader.
##
## Everything here is in game space (SourceEntities.to_game): inches, Y up.

const MAGIC := 0xFEEDFACE
const OLDEST_VERSION := 30
const NEWEST_VERSION := 36

## An area's attributes (NavAttributeFlags), as version 35 and later store
## them; older files use other bits, which Source 2 Viewer does not map, so on
## those these mean nothing. dust2 (version 36) marks only CROUCH, on the 14
## areas under a ceiling too low to stand.
const FLAG_JUMP := 0x2
const FLAG_NO_JUMP := 0x8
const FLAG_STOP := 0x10
const FLAG_RUN := 0x20
const FLAG_WALK := 0x40
const FLAG_AVOID := 0x80
const FLAG_STAIRS := 0x1000
const FLAG_CROUCH := 0x10000

## Links whose edges are further apart than this, in plan, cross a gap.
const TOUCHING := 1.0

## The spatial index's cells, in units.
const CELL := 128.0


## Where a link leads: `area` is the area across, and `edge` its edge the link
## arrives at. Most links join edges that touch; the rest, about one in six on
## dust2, cross a gap to floor higher or lower, which is a jump or a drop.
class Link:
	var area: int
	var edge: int
	## How far apart the two edges are across the floor, in plan.
	var gap: float
	## How far the far edge's middle is above the near one's.
	var rise: float


## One convex piece of floor.
class Area:
	var id: int
	## Which of the mesh's hulls (SourceNavMesh.hulls) it was built for.
	var hull: int
	var flags: int
	var corners: PackedVector3Array
	var centre: Vector3
	## The links across each edge, edge i running from corner i to corner i + 1.
	var edges: Array[Array] = []
	var ladders_up: PackedInt32Array
	var ladders_down: PackedInt32Array

	## Every link out of the area.
	func links() -> Array[Link]:
		var out: Array[Link] = []
		for edge_links in edges:
			for link: Link in edge_links:
				out.append(link)
		return out

	## Edge i's two ends.
	func edge_ends(i: int) -> PackedVector3Array:
		return PackedVector3Array([corners[i], corners[(i + 1) % corners.size()]])

	## Whether a point is over (or under) the area, in plan.
	func covers(point: Vector3) -> bool:
		var inside := false
		var j := corners.size() - 1
		for i in corners.size():
			var a := corners[i]
			var b := corners[j]
			if (a.z > point.z) != (b.z > point.z) \
					and point.x < (b.x - a.x) * (point.z - a.z) / (b.z - a.z) + a.x:
				inside = not inside
			j = i
		return inside

	## How far a point is from the area in plan: 0 over it.
	func distance_in_plan(point: Vector3) -> float:
		if covers(point):
			return 0.0
		var nearest := INF
		for i in corners.size():
			var ends := edge_ends(i)
			var on := Geometry2D.get_closest_point_to_segment(
				Vector2(point.x, point.z), Vector2(ends[0].x, ends[0].z), Vector2(ends[1].x, ends[1].z)
			)
			nearest = minf(nearest, on.distance_to(Vector2(point.x, point.z)))
		return nearest

	## The floor's height under a point over the area, on the fan of triangles
	## its corners make (a four-cornered area need not be flat).
	func floor_at(point: Vector3) -> float:
		for i in range(1, corners.size() - 1):
			var weights := _barycentric(point, corners[0], corners[i], corners[i + 1])
			if weights.x >= -0.001 and weights.y >= -0.001 and weights.z >= -0.001:
				return weights.x * corners[0].y + weights.y * corners[i].y + weights.z * corners[i + 1].y
		return centre.y

	static func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(c.x - a.x, c.z - a.z)
		var v2 := Vector2(p.x - a.x, p.z - a.z)
		var denominator := v0.x * v1.y - v1.x * v0.y
		if absf(denominator) < 1e-9:
			return Vector3(-1, -1, -1)
		var v := (v2.x * v1.y - v1.x * v2.y) / denominator
		var w := (v0.x * v2.y - v2.x * v0.y) / denominator
		return Vector3(1.0 - v - w, v, w)


## A ladder, with the areas at either end (0 where there is none).
class Ladder:
	var id: int
	var width: float
	var length: float
	var top: Vector3
	var bottom: Vector3
	## Which way it faces: 0 to 3, Source's north, east, south, west.
	var direction: int
	## The areas off its top, ahead, left, right and behind.
	var top_areas: PackedInt32Array
	## The areas off its foot, ahead, left and right.
	var bottom_areas: PackedInt32Array


var version: int = 0
var sub_version: int = 0
## Whether the game has analysed the mesh (hiding spots and the rest).
var analyzed: bool = false
## Area id to Area.
var areas: Dictionary = {}
var ladders: Array[Ladder] = []
## What the mesh was built for, one entry per hull: {"radius", "height",
## "crouch_height", "max_climb", "max_slope", "jump_up", "jump_down",
## "jump_across"}, in units and degrees. CS2's maps have one, the player's
## (dust2's: 16 by 71, 35.5 crouched, 16 to step up, 68 to jump up, 157 to
## drop); older files kept several, the smallest first.
var hulls: Array[Dictionary] = []
## How the mesh was generated: {"version", "tile_size", "cell_size",
## "cell_height", "verts_per_poly"}.
var generation: Dictionary = {}
## The analysis block's size in the file, 0 where there is none.
var analysis_bytes: int = 0
## Bytes left after the last section: 0 when the file was read as it was
## written.
var unread_bytes: int = 0
## Why the file could not be read; empty when it was.
var error: String = ""

var _grid: Dictionary = {}
## Hull to its path graph, built the first time it is asked for.
var _graphs: Dictionary = {}


## Reads a .nav file. Check `error` on what comes back.
static func load_file(path: String) -> SourceNavMesh:
	if not FileAccess.file_exists(path):
		var missing := SourceNavMesh.new()
		missing.error = "no nav mesh at %s (scripts/extract_assets.sh nav)" % path
		return missing
	return parse(FileAccess.get_file_as_bytes(path))


static func parse(bytes: PackedByteArray) -> SourceNavMesh:
	var mesh := SourceNavMesh.new()
	mesh._read(_Reader.new(bytes))
	if mesh.error.is_empty():
		mesh._measure_links()
		mesh._index()
	return mesh


## The area under a point: the highest whose floor there is no more than
## `above` over the point and no more than `below` under it, of one hull's
## areas or, with `hull` -1, any. Null over no area.
func area_at(point: Vector3, below: float = 120.0, above: float = 24.0, hull: int = -1) -> Area:
	var best: Area = null
	var best_floor := -INF
	for id: int in _grid.get(_cell(point), PackedInt32Array()):
		var area: Area = areas[id]
		if (hull >= 0 and area.hull != hull) or not area.covers(point):
			continue
		var floor_height := area.floor_at(point)
		if floor_height <= point.y + above and floor_height >= point.y - below and floor_height > best_floor:
			best = area
			best_floor = floor_height
	return best


## The area nearest a point within `radius`, in plan with the height
## difference added: the area under it where there is one. `hull` as for
## area_at().
func nearest_area(point: Vector3, radius: float = 256.0, hull: int = -1) -> Area:
	var under := area_at(point, 120.0, 24.0, hull)
	if under != null:
		return under
	var best: Area = null
	var best_distance := INF
	var reach := int(ceil(radius / CELL))
	var centre_cell := _cell(point)
	var seen := {}
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for id: int in _grid.get(centre_cell + Vector2i(dx, dz), PackedInt32Array()):
				if seen.has(id):
					continue
				seen[id] = true
				var area: Area = areas[id]
				if hull >= 0 and area.hull != hull:
					continue
				var across := area.distance_in_plan(point)
				var distance := across + absf(point.y - area.floor_at(point) if across == 0.0 else point.y - area.centre.y)
				if distance < best_distance and across <= radius:
					best = area
					best_distance = distance
	return best


## The areas a walk from one point to another passes through, in order, the
## start's first, over one hull's areas (0, the only one on CS2's maps). A
## point off the mesh starts or ends at the nearest area within 256 units;
## empty when there is none, or when no links lead from one to the other.
func route(from: Vector3, to: Vector3, hull: int = 0) -> Array[Area]:
	var out: Array[Area] = []
	var start := nearest_area(from, 256.0, hull)
	var end := nearest_area(to, 256.0, hull)
	if start == null or end == null:
		return out
	for id in _graph(hull).get_id_path(start.id, end.id):
		out.append(areas[id])
	return out


## A path from one point to another as points to walk through: the start,
## the middle of each edge the route crosses where the two areas share it,
## and the end. Where a link is a jump or a drop, the path has both the
## take-off and the landing. It runs through edge middles, not tight round
## corners: pulling it taut is for whoever walks it. Empty where route() is.
func find_path(from: Vector3, to: Vector3, hull: int = 0) -> PackedVector3Array:
	var areas_on_route := route(from, to, hull)
	var points := PackedVector3Array()
	if areas_on_route.is_empty():
		return points
	points.append(from)
	for i in areas_on_route.size() - 1:
		var here := areas_on_route[i]
		var next := areas_on_route[i + 1]
		for edge in here.edges.size():
			var crossing: Link = null
			for link: Link in here.edges[edge]:
				if link.area == next.id and link.gap < INF:
					crossing = link
			if crossing == null:
				continue
			var landing_edge := next.edge_ends(crossing.edge)
			var take_off := _portal(here.edge_ends(edge), landing_edge)
			points.append(take_off)
			# Where the floors part, across a gap or up or down a ledge, the
			# landing too. On a slope the edges' middles can differ by more
			# than a step while the floors meet: then it is the same point.
			var landing := Geometry3D.get_closest_point_to_segment(take_off, landing_edge[0], landing_edge[1])
			if landing.distance_to(take_off) > TOUCHING:
				points.append(landing)
			break
	points.append(to)
	return points


## A path pulled taut, for a player to walk: `points` are the corners it
## turns at, the start first and the end last. Across a jump or a drop it
## keeps both the take-off and the landing, and `jumps` marks the take-offs
## whose landing is too high to step up to (1 at the take-off's index), which
## is where a walker jumps. `areas` are the areas it crosses, in order, for
## whoever needs to know what the floor asks of them (FLAG_CROUCH).
class WalkPath:
	var points := PackedVector3Array()
	var jumps := PackedByteArray()
	var areas: Array[Area] = []

	func is_empty() -> bool:
		return points.is_empty()

	## Whether the leg from point i is a jump up.
	func jumps_from(i: int) -> bool:
		return i >= 0 and i < jumps.size() and jumps[i] != 0


## How far in from the ends of the edge it crosses a taut path keeps its
## corners, in units. The mesh is already the floor the middle of a player's
## hull can reach (it was built eroded by the hull's 16-unit radius), so a
## path through a corner of it has the hull touching the wall; this is the
## room left for the hull's square corners and for a walker who turns late.
const CORNER_CLEARANCE := 10.0

## A landing more than this over the take-off is a jump, not a step: the
## movement's step_height.
const STEP_UP := 18.0

## How far onto the floor across a jump or a drop its landing is.
const LANDING_IN := 12.0

## A gap wider than this in plan, to floor no lower than a step down, is
## jumped rather than walked over.
const JUMP_ACROSS := 32.0


## The way from one point to another over one hull's areas, pulled taut: the
## same route as find_path(), but turning only where a wall makes it turn,
## at the corners of the edges it crosses (kept CORNER_CLEARANCE in from
## them), the way the game's own bots cut across a room rather than walking
## through the middle of every piece of floor. The pulling is the funnel
## algorithm (Mononen's "simple stupid funnel") in plan, run between the
## start, each jump or drop, and the end, since those points have to be
## walked through as they are. Empty where route() is.
func walk_path(from: Vector3, to: Vector3, hull: int = 0) -> WalkPath:
	var path := WalkPath.new()
	path.areas = route(from, to, hull)
	if path.areas.is_empty():
		return path
	# Stretches of floor walked without leaving it, each a list of portals
	# (the edge crossed, as its left and right ends seen walking), joined at
	# the take-offs and landings of the jumps and drops between them.
	var start := from
	var portals: Array[PackedVector3Array] = []
	for i in path.areas.size() - 1:
		var here := path.areas[i]
		var next := path.areas[i + 1]
		var crossing := _crossing(here, next)
		if crossing.is_empty():
			continue
		var near: PackedVector3Array = crossing[0]
		var far: PackedVector3Array = crossing[1]
		var take_off := _portal(near, far)
		var landing := Geometry3D.get_closest_point_to_segment(take_off, far[0], far[1])
		if landing.distance_to(take_off) > TOUCHING:
			_pull_taut(start, take_off, portals, path)
			# Landed a little way onto the floor across, not on its lip: up a
			# ledge the lip is straight over the take-off, which gives the jump
			# no way to go.
			landing += Vector3(next.centre.x - landing.x, 0.0, next.centre.z - landing.z).limit_length(LANDING_IN)
			landing.y = next.floor_at(landing)
			var gap := Vector2(landing.x - take_off.x, landing.z - take_off.z).length()
			var rise := landing.y - take_off.y
			_end_at(path, take_off, rise > STEP_UP or (gap > JUMP_ACROSS and rise > -STEP_UP))
			start = landing
			portals.clear()
			continue
		portals.append(_portal_ends(near, far, here.centre, next.centre))
	_pull_taut(start, to, portals, path)
	_end_at(path, to, false)
	return path


## The end of a stretch, where the funnel may already have put it as its
## last corner.
static func _end_at(path: WalkPath, point: Vector3, jump: bool) -> void:
	if not _same(path.points[-1], point) or path.points.size() == 1:
		path.points.append(point)
		path.jumps.append(0)
	path.jumps[-1] = 1 if jump else 0


## The edge of `here` a walk into `next` crosses and the edge of `next` it
## arrives at, or empty where no link leads there.
func _crossing(here: Area, next: Area) -> Array:
	for edge in here.edges.size():
		for link: Link in here.edges[edge]:
			if link.area == next.id and link.gap < INF:
				return [here.edge_ends(edge), next.edge_ends(link.edge)]
	return []


## The stretch of `near` that `far` shares, seen along `near`, drawn in by
## CORNER_CLEARANCE at each end (to its middle where it is narrower than
## that), as [left, right] for someone walking from `from` towards `to`.
static func _portal_ends(near: PackedVector3Array, far: PackedVector3Array, from: Vector3, to: Vector3) -> PackedVector3Array:
	var along := Vector2(near[1].x - near[0].x, near[1].z - near[0].z)
	var length_squared := along.length_squared()
	if length_squared < 1e-6:
		return PackedVector3Array([near[0], near[0]])
	var t0 := Vector2(far[0].x - near[0].x, far[0].z - near[0].z).dot(along) / length_squared
	var t1 := Vector2(far[1].x - near[0].x, far[1].z - near[0].z).dot(along) / length_squared
	var low := clampf(minf(t0, t1), 0.0, 1.0)
	var high := clampf(maxf(t0, t1), 0.0, 1.0)
	var inset := minf(CORNER_CLEARANCE / sqrt(length_squared), (high - low) * 0.5)
	var a := near[0].lerp(near[1], low + inset)
	var b := near[0].lerp(near[1], high - inset)
	# Left of the way walked is where the cross product of the way and the
	# point (in plan, x and z) is positive.
	var way := Vector2(to.x - from.x, to.z - from.z)
	var middle := (a + b) * 0.5
	if _cross(way, Vector2(a.x - middle.x, a.z - middle.z)) >= 0.0:
		return PackedVector3Array([a, b])
	return PackedVector3Array([b, a])


## The corners of a taut walk from `from` to `to` through `portals` (each
## [left, right]), appended to `path` from `from` on; `to` is left for the
## caller. The funnel: an apex, and the left and right edges of the view
## through the portals from it. Each portal narrows one side or the other;
## when a side would cross over the other, the other's end is a corner, and
## it becomes the apex.
static func _pull_taut(from: Vector3, to: Vector3, portals: Array[PackedVector3Array], path: WalkPath) -> void:
	path.points.append(from)
	path.jumps.append(0)
	var ends: Array[PackedVector3Array] = portals.duplicate()
	ends.append(PackedVector3Array([to, to]))
	var apex := from
	var left := from
	var right := from
	var left_at := -1
	var right_at := -1
	var i := 0
	while i < ends.size():
		var new_left: Vector3 = ends[i][0]
		var new_right: Vector3 = ends[i][1]
		# The right side narrows...
		if _cross(_plan(right - apex), _plan(new_right - apex)) >= 0.0:
			if _same(apex, right) or _cross(_plan(left - apex), _plan(new_right - apex)) < 0.0:
				right = new_right
				right_at = i
			else:
				# ...past the left: the left's end is a corner.
				apex = left
				_corner(path, apex)
				right = apex
				right_at = left_at
				i = left_at + 1
				continue
		# The left side narrows...
		if _cross(_plan(left - apex), _plan(new_left - apex)) <= 0.0:
			if _same(apex, left) or _cross(_plan(right - apex), _plan(new_left - apex)) > 0.0:
				left = new_left
				left_at = i
			else:
				# ...past the right: the right's end is a corner.
				apex = right
				_corner(path, apex)
				left = apex
				left_at = right_at
				i = right_at + 1
				continue
		i += 1


## A corner of the path, unless it is where the path already is (two edges
## that end at the same point can make the same corner twice).
static func _corner(path: WalkPath, point: Vector3) -> void:
	if not _same(path.points[-1], point):
		path.points.append(point)
		path.jumps.append(0)


static func _plan(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


static func _same(a: Vector3, b: Vector3) -> bool:
	return _plan(a - b).length_squared() < 1e-6


## A mesh made of areas built by hand, linked as each area's edges say, for
## a test to walk without a .nav file.
static func from_areas(list: Array[Area]) -> SourceNavMesh:
	var mesh := SourceNavMesh.new()
	mesh.hulls = [{"radius": 16.0, "height": 71.0}]
	for area in list:
		var sum := Vector3.ZERO
		for corner in area.corners:
			sum += corner
		area.centre = sum / maxf(area.corners.size(), 1)
		while area.edges.size() < area.corners.size():
			area.edges.append([])
		mesh.areas[area.id] = area
	mesh._measure_links()
	mesh._index()
	return mesh


## One line of what the mesh is, for reports.
func summary() -> String:
	if not error.is_empty():
		return error
	var sizes := PackedStringArray()
	for hull in hulls:
		sizes.append("%.0f by %.0f" % [hull.get("radius", 0.0), hull.get("height", 0.0)])
	return "version %d, %d areas, %d ladders, for %s %s" % [
		version, areas.size(), ladders.size(), "the hull" if hulls.size() == 1 else "the hulls", ", ".join(sizes),
	]


# --- Reading ---------------------------------------------------------------

func _read(r: _Reader) -> void:
	if r.u32() != MAGIC:
		error = "not a nav mesh (its first four bytes are not 0xFEEDFACE)"
		return
	version = r.u32()
	if version < OLDEST_VERSION or version > NEWEST_VERSION:
		error = "nav mesh version %d; this reads %d to %d" % [version, OLDEST_VERSION, NEWEST_VERSION]
		return
	sub_version = r.u32()
	analyzed = (r.u32() & 1) != 0
	if version >= 36 and _skip_kv3(r) < 0:
		_fail(r, "the KV3 block after the header is not one this can step over")
		return

	var polygons: Array[PackedVector3Array] = []
	if version >= 31:
		var corners := PackedVector3Array()
		corners.resize(r.count(12))
		for i in corners.size():
			corners[i] = r.vector()
		for i in r.count(5):
			var polygon := PackedVector3Array()
			polygon.resize(r.u8())
			for corner in polygon.size():
				var index := r.u32()
				polygon[corner] = corners[index] if index < corners.size() else Vector3.ZERO
			if version >= 35:
				r.u32()  # the movable mesh it rides, if any
			polygons.append(polygon)
			if r.overran:
				break
	if version >= 32:
		r.u32()
	if version >= 35:
		for i in r.count(49):
			r.string()
			r.skip(48)  # the movable mesh's transform
	if version >= 36 and _skip_kv3(r) < 0:
		_fail(r, "the KV3 block before the areas is not one this can step over")
		return

	for i in r.count(34):
		var area := _read_area(r, polygons)
		if r.overran:
			break
		areas[area.id] = area
	for i in r.count(60):
		ladders.append(_read_ladder(r))
		if r.overran:
			break
	for i in r.count(24 + 48):
		r.skip(24 + 48)  # a box and its 3x4 transform
		if r.overran:
			break
	_read_generation(r)
	if version >= 36 and _skip_kv3(r) < 0:
		_fail(r, "the KV3 block after the generation parameters is not one this can step over")
		return
	if sub_version > 0:
		analysis_bytes = _skip_kv3(r)
		if analysis_bytes < 0:
			_fail(r, "the analysis block is not KV3 this can step over")
			return
	if r.overran:
		_fail(r, "")
		return
	unread_bytes = r.bytes.size() - r.at


## Says why the file could not be read: that it is cut short or damaged, if
## a read ran past its end or a size could not be right, since everything
## read after that is zeros and fails for that reason.
func _fail(r: _Reader, message: String) -> void:
	error = "the file is cut short or damaged: %d bytes, and it asks for more" % r.bytes.size() if r.overran else message


func _read_area(r: _Reader, polygons: Array[PackedVector3Array]) -> Area:
	var area := Area.new()
	area.id = r.u32()
	area.flags = r.s64()
	area.hull = r.u8()
	if version >= 31:
		var index := r.u32()
		area.corners = polygons[index] if index < polygons.size() else PackedVector3Array()
	else:
		var corners := PackedVector3Array()
		corners.resize(r.count(12))
		for i in corners.size():
			corners[i] = r.vector()
		area.corners = corners
	r.f32()  # nearly always 0
	for i in area.corners.size():
		var edge_links: Array[Link] = []
		for j in r.count(8):
			var link := Link.new()
			link.area = r.u32()
			link.edge = r.u32()
			edge_links.append(link)
			if r.overran:
				break
		area.edges.append(edge_links)
	r.u8()  # legacy hiding spots, none
	r.u32()  # legacy spot encounters, none
	area.ladders_up = _ids(r)
	area.ladders_down = _ids(r)
	var sum := Vector3.ZERO
	for corner in area.corners:
		sum += corner
	area.centre = sum / maxf(area.corners.size(), 1)
	return area


func _read_ladder(r: _Reader) -> Ladder:
	var ladder := Ladder.new()
	ladder.id = r.u32()
	ladder.width = r.f32()
	ladder.top = r.vector()
	ladder.bottom = r.vector()
	ladder.length = r.f32()
	ladder.direction = r.u32()
	ladder.top_areas = PackedInt32Array([r.u32(), r.u32(), r.u32(), r.u32()])
	ladder.bottom_areas = PackedInt32Array([r.u32(), r.u32(), r.u32()] if version >= 35 else [r.u32()])
	return ladder


## A count and that many ids.
static func _ids(r: _Reader) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for i in r.count(4):
		ids.append(r.u32())
	return ids


func _read_generation(r: _Reader) -> void:
	var gen := r.s32()
	r.u32()  # uses the project's defaults
	generation = {"version": gen, "tile_size": r.f32(), "cell_size": r.f32(), "cell_height": r.f32()}
	r.skip(4 + 4 + 4 + 4 + 4 + 4)  # region sizes, detail sampling, edge length and error
	generation["verts_per_poly"] = r.s32()
	if gen >= 7:
		r.f32()  # small-area removal
	if gen >= 12:
		r.string()  # hull preset name
		r.string()  # hull definitions file
	# A hull is 28 bytes at the least (seven fields before version 9).
	var hull_count := r.count(28)
	# Up to version 11 three hulls are written whether or not they are used.
	for i in maxi(hull_count, 3 if gen <= 11 else 0):
		var hull := {}
		if gen >= 9:
			r.u8()  # enabled
		hull["radius"] = r.f32()
		hull["height"] = r.f32()
		hull["crouch_height"] = hull["height"]
		if gen >= 9:
			var crouch_enabled := r.u8() != 0
			var crouch := r.f32()
			if crouch_enabled:
				hull["crouch_height"] = crouch
		if gen >= 13:
			r.u8()  # crawling
			r.f32()
		hull["max_climb"] = r.f32()
		hull["max_slope"] = float(r.s32())
		hull["jump_down"] = r.f32()
		hull["jump_across"] = r.f32()
		hull["jump_up"] = r.f32()
		if gen >= 11:
			r.s32()  # border erosion
		if i < hull_count:
			hulls.append(hull)
		if r.overran:
			break
	if gen >= 12:
		r.u8()  # gravity follows rotation


## Steps over a binary KV3 block, which the file keeps on an eight-byte
## boundary. Returns its size, or -1 where it is not one whose size its header
## gives: KV3 before version 2, and LZ4 with binary blobs, whose sizes are
## inside the compressed data. None of CS2's nav files has either.
func _skip_kv3(r: _Reader) -> int:
	r.align(8)
	var start := r.at
	var magic := r.u32()
	var kv3_version := magic & 0xFF
	if (magic & 0xFFFFFF00) != 0x4B563300 or kv3_version < 2 or kv3_version > 5:
		return -1
	r.skip(16)  # the format's GUID
	var compression := r.u32()
	r.skip(2 + 2 + 4 * 4 + 2 + 2)  # dictionary, frame size, counts
	var uncompressed := r.s32()
	var compressed := r.s32()
	var blocks := r.s32()
	var blob_bytes := r.s32()
	if kv3_version >= 4:
		r.skip(8)
	var buffer1 := uncompressed
	var buffer2 := 0
	if kv3_version >= 5:
		buffer1 = r.s32()
		r.skip(4)
		buffer2 = r.s32()
		r.skip(4 + 8 * 4)
	var body := 0
	if compression == 0:
		body = buffer1 + buffer2 + (blob_bytes if blocks > 0 else 0)
	elif compression == 1 and blocks > 0:
		return -1
	else:
		body = compressed
	if blocks > 0:
		body += 4  # the trailer
	r.skip(body)
	return -1 if r.overran else r.at - start


# --- After reading ------------------------------------------------------------

func _measure_links() -> void:
	for area: Area in areas.values():
		for edge in area.edges.size():
			var ends := area.edge_ends(edge)
			for link: Link in area.edges[edge]:
				var other: Area = areas.get(link.area)
				if other == null or link.edge >= other.corners.size():
					link.gap = INF
					continue
				var across := other.edge_ends(link.edge)
				link.gap = _segment_gap(ends, across)
				link.rise = (across[0].y + across[1].y) * 0.5 - (ends[0].y + ends[1].y) * 0.5


func _index() -> void:
	for area: Area in areas.values():
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for corner in area.corners:
			low = low.min(Vector2(corner.x, corner.z))
			high = high.max(Vector2(corner.x, corner.z))
		for x in range(floori(low.x / CELL), floori(high.x / CELL) + 1):
			for z in range(floori(low.y / CELL), floori(high.y / CELL) + 1):
				# Packed arrays are values: taken out, added to and put back.
				var key := Vector2i(x, z)
				var ids: PackedInt32Array = _grid.get(key, PackedInt32Array())
				ids.append(area.id)
				_grid[key] = ids


## One hull's areas and the links between them, the ones that lead to an
## edge there is.
func _graph(hull: int) -> AStar3D:
	if _graphs.has(hull):
		return _graphs[hull]
	var astar := AStar3D.new()
	for area: Area in areas.values():
		if area.hull == hull:
			astar.add_point(area.id, area.centre)
	for area: Area in areas.values():
		if area.hull != hull:
			continue
		for link in area.links():
			if link.gap < INF and astar.has_point(link.area) and not astar.are_points_connected(area.id, link.area, false):
				astar.connect_points(area.id, link.area, false)
	_graphs[hull] = astar
	return astar


static func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.z / CELL))


## Where a walk from one edge to the other crosses the first: the middle of
## the stretch the two share, seen along the first; where they share none,
## the first's point nearest the second.
static func _portal(near: PackedVector3Array, far: PackedVector3Array) -> Vector3:
	var along := Vector2(near[1].x - near[0].x, near[1].z - near[0].z)
	var length_squared := along.length_squared()
	if length_squared < 1e-6:
		return near[0]
	var t0 := Vector2(far[0].x - near[0].x, far[0].z - near[0].z).dot(along) / length_squared
	var t1 := Vector2(far[1].x - near[0].x, far[1].z - near[0].z).dot(along) / length_squared
	var low := clampf(minf(t0, t1), 0.0, 1.0)
	var high := clampf(maxf(t0, t1), 0.0, 1.0)
	return near[0].lerp(near[1], (low + high) * 0.5)


## How far apart two edges are, in plan.
static func _segment_gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var a0 := Vector2(a[0].x, a[0].z)
	var a1 := Vector2(a[1].x, a[1].z)
	var b0 := Vector2(b[0].x, b[0].z)
	var b1 := Vector2(b[1].x, b[1].z)
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	return minf(
		minf(Geometry2D.get_closest_point_to_segment(a0, b0, b1).distance_to(a0), Geometry2D.get_closest_point_to_segment(a1, b0, b1).distance_to(a1)),
		minf(Geometry2D.get_closest_point_to_segment(b0, a0, a1).distance_to(b0), Geometry2D.get_closest_point_to_segment(b1, a0, a1).distance_to(b1))
	)


## Little-endian reads that stop at the end of the data instead of running
## past it, setting `overran`.
class _Reader:
	var bytes: PackedByteArray
	var at: int = 0
	var overran: bool = false

	func _init(data: PackedByteArray) -> void:
		bytes = data

	func _take(length: int) -> int:
		# A negative size is a damaged one: it must not step back.
		if length < 0 or at + length > bytes.size():
			overran = true
			at = bytes.size()
			return -1
		var offset := at
		at += length
		return offset

	func skip(length: int) -> void:
		_take(length)

	## A count of things at least `each` bytes apiece, or 0 with `overran`
	## set when the rest of the data could not hold that many: a damaged
	## count must not ask for a billion of anything.
	func count(each: int) -> int:
		var value := u32()
		if value * each > bytes.size() - at:
			overran = true
			at = bytes.size()
			return 0
		return value

	func align(to: int) -> void:
		var aligned := (at + to - 1) & ~(to - 1)
		_take(aligned - at)

	func u8() -> int:
		var offset := _take(1)
		return 0 if offset < 0 else bytes[offset]

	func u32() -> int:
		var offset := _take(4)
		return 0 if offset < 0 else bytes.decode_u32(offset)

	func s32() -> int:
		var offset := _take(4)
		return 0 if offset < 0 else bytes.decode_s32(offset)

	func s64() -> int:
		var offset := _take(8)
		return 0 if offset < 0 else bytes.decode_s64(offset)

	func f32() -> float:
		var offset := _take(4)
		return 0.0 if offset < 0 else bytes.decode_float(offset)

	## A position in the file (Source's axes) as one in game space.
	func vector() -> Vector3:
		var x := f32()
		var y := f32()
		var z := f32()
		return SourceEntities.to_game(Vector3(x, y, z))

	func string() -> String:
		var end := bytes.find(0, at)
		if end < 0:
			overran = true
			at = bytes.size()
			return ""
		var text := bytes.slice(at, end).get_string_from_utf8()
		at = end + 1
		return text
