class_name GroundEyes
extends RefCounted

## Shared simulation root/eye adjustment, finished before jump snapshots.
## The topology rules are from the installed CS2 movement audit; queries
## run only in movement, never from a view or a bot's threaded eye getter.
##
## A moving body's terrain sample is the native code's wherever its
## movement step is (HullMover.sample_ground, native/src/hull_mover.cpp):
## the same grid, cache and casts, held to _script_sample to the last bit.
## A change to the sample here is made there too, in the same pull request.
const GRID := 8
const SIDE := 5
const SAMPLE_WIDTH := 7.98
const MAX_DROP := 24.0
const GROUND_BLEND_SPEED := 150.0
const MIN_NORMAL := 0.7
const CACHE_LIMIT := 512

var offset := 0.0
var residual := 0.0
var using_topology := false
## Lifetime count, like PlayerBody.traces. State resets must not make a
## profiler's before/after query delta negative.
var queries := 0
var drop := 0.0
var _last_q := Vector3.INF
var _last_step := -1.0
var _last_half := -1.0
var _last_mask := 0
var _cache: Dictionary[Vector2i, float] = {}
var _query := PhysicsShapeQueryParameters3D.new()

## Whether the native code samples where it steps the body. Off, the script
## samples alone: --script-eyes after --, a profile's control for the A/B.
static var native_samples := not "--script-eyes" in OS.get_cmdline_user_args()
## With PlayerBody.check_steps on (every check), each native sample is
## worked out by the script first, from the same start, and the two held to
## the same drop, casts and cache; a difference is a fault.
static var samples_checked: int = 0
static var sample_faults: PackedStringArray = PackedStringArray()


func _init() -> void:
	var thin := BoxShape3D.new()
	thin.size = Vector3(SAMPLE_WIDTH, 0.002, SAMPLE_WIDTH)
	_query.shape = thin
	_query.margin = 0.0


func reset() -> void:
	offset = 0.0
	residual = 0.0
	using_topology = false
	drop = 0.0
	_last_q = Vector3.INF
	_cache.clear()


func cache_size() -> int:
	return _cache.size()


func height(base: float) -> float:
	# The server explicitly rounds through a float32 addition/subtraction
	# at 196608, giving 1/64-unit view-offset precision (ties to even).
	return float(Vector3(0.0, base + offset + 196608.0, 0.0).y) - 196608.0


## CS2's eye update (180ae23e0), at each movement segment's end: the duck
## root offset eased to 0 at half the hulls' difference over 0.1 s; the
## ground adjustment; their sum clamped to 32 either way; then the duck
## view offset eased toward the hulls' difference times the duck amount
## below the standing eyes, less the root, at the difference over 0.2 s.
## mover is the body's native step (HullMover) and bridge its Box3DQueries,
## in its own tick's scope, where the native code steps it; else null.
func update(body: PlayerBody, dt: float, mover: Object = null, bridge: Box3DQueries = null) -> void:
	if body.noclip:
		reset()
		body.duck_root_offset = 0.0
		return
	var difference := body.config.stand_height - body.config.duck_height
	body.duck_root_offset = move_toward(body.duck_root_offset, 0.0, difference * 0.5 / 0.1 * dt)
	var root := body.duck_root_offset
	var enabled := body.on_ground and body.ground_is_world
	var target := 0.0
	if enabled:
		target = -_sample(body, mover, bridge)
	if enabled != using_topology:
		residual = offset - (root + target)
	using_topology = enabled
	var rate := GROUND_BLEND_SPEED if enabled else maxf(absf(body.velocity.y) * 0.5, body.config.gravity * 0.05)
	residual = move_toward(residual, 0.0, rate * dt)
	offset = clampf(root + target + residual, -32.0, 32.0)
	body.duck_view_offset = move_toward(body.duck_view_offset, -difference * body.duck_progress - root,
		difference / 0.2 * dt)


static func quantized_position(position: Vector3) -> Vector3:
	var scaled := position * 100.0
	return Vector3(floorf(scaled.x), floorf(scaled.y), floorf(scaled.z)) / 100.0


static func first_cell(q: Vector3, half: float = 16.0) -> Vector2i:
	# fmod/truncation and the positive branch are intentional. A ceil-based
	# rewrite differs exactly at grid lines and zero/negative coordinates.
	return Vector2i(int(q.x - fmod(q.x, GRID) - half - 4.0) + (GRID if q.x > 0.0 else 0),
		int(q.z - fmod(q.z, GRID) - half - 4.0) + (GRID if q.z > 0.0 else 0))


func _sample(body: PlayerBody, mover: Object = null, bridge: Box3DQueries = null) -> float:
	var q := quantized_position(body.global_position)
	var step := body.config.step_height
	var half := body.config.hull_width * 0.5
	# Only fixed world/support geometry belongs in a terrain-height cache.
	# A neighbor's hull must not hide cells or become a permanent height.
	# Source's raw filter bits are not Godot layer numbers; this is the
	# project's explicit support mapping, with the body's mask respected.
	var mask := body.collision_mask & (Hitscan.WORLD_LAYER | MapImporter.PLAYER_CLIP_LAYER)
	if step != _last_step or half != _last_half or mask != _last_mask:
		_cache.clear()
		_last_q = Vector3.INF
		_last_step = step
		_last_half = half
		_last_mask = mask
	if q == _last_q:
		return drop
	_last_q = q
	# Source clears once before a changed-position grid, not mid-grid.
	# At most one grid can temporarily extend the 512-entry threshold.
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	var first := first_cell(q, half)
	if mover != null and bridge != null and native_samples:
		var by_native := _sample_both_ways(body, mover, bridge, q, first, step, half, mask) if PlayerBody.check_steps \
			else _native_sample(body, mover, bridge, q, first, step, half, mask)
		if not is_nan(by_native):
			drop = by_native
			return drop
	drop = _script_sample(body, q, first, step, half, mask)
	return drop


## The grid's heights, from the cache where it has them and cast for where
## not, and the drop they weigh to: the reference the native code is held to.
func _script_sample(body: PlayerBody, q: Vector3, first: Vector2i, step: float, half: float, mask: int) -> float:
	var heights := PackedFloat32Array()
	heights.resize(SIDE * SIDE)
	heights.fill(INF)
	_query.collision_mask = mask
	_query.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	# Source X is Godot Z, and Source Y is Godot X. Storage order matters
	# for tied seeds and first-path discontinuity selection.
	for iz in SIDE:
		for ix in SIDE:
			var cell := first + Vector2i(ix, iz) * GRID
			var h: float = _cache.get(cell, INF)
			if not (h >= q.y - 2.0 * step and h <= q.y + step + 1.0):
				_query.transform.origin = Vector3(cell.x, floorf(q.y + 2.0 * step), cell.y)
				_query.motion = Vector3(0.0, floorf(q.y - 2.0 * step) - _query.transform.origin.y, 0.0)
				queries += 1
				body.traces += 1
				var hit := PhysicsQueries.terrain_square(space, _query, SAMPLE_WIDTH)
				if hit.is_empty() or hit.get("blocked_start", false) or not PlayerBody._is_world_ground(hit.get("collider")) or (hit.get("normal", Vector3.ZERO) as Vector3).y <= MIN_NORMAL:
					continue
				var scaled_contact := (hit["end"] as Vector3) * 10.0
				h = float(Vector3(0.0, floorf(scaled_contact.y) / 10.0, 0.0).y)
				_cache[cell] = h
			heights[iz * SIDE + ix] = h
	return compute_drop(q, first, heights, step, half)


## The same by the native code, the cache written in place; NaN where it
## could not run, and then it cast nothing.
func _native_sample(body: PlayerBody, mover: Object, bridge: Box3DQueries, q: Vector3, first: Vector2i, step: float, half: float, mask: int) -> float:
	var by_native: float = mover.call(&"sample_ground", bridge, bridge.native_world, _cache, q, first, step, half, mask, body.get_rid())
	var casts := int(mover.call(&"get_ground_casts"))
	queries += casts
	body.traces += casts
	PhysicsQueries.native_queries += casts
	return by_native


## Both ways from the same start: the script's first, then the native
## code's, which is kept, the two held to the same drop, casts and cache.
func _sample_both_ways(body: PlayerBody, mover: Object, bridge: Box3DQueries, q: Vector3, first: Vector2i, step: float, half: float, mask: int) -> float:
	var cache_before := _cache.duplicate()
	var queries_before := queries
	var traces_before := body.traces
	var native_queries_before := PhysicsQueries.native_queries
	var by_script := _script_sample(body, q, first, step, half, mask)
	var script_cache := _cache.duplicate()
	var script_casts := queries - queries_before
	_cache.assign(cache_before)
	queries = queries_before
	body.traces = traces_before
	PhysicsQueries.native_queries = native_queries_before
	var by_native := _native_sample(body, mover, bridge, q, first, step, half, mask)
	if is_nan(by_native):
		return by_native
	samples_checked += 1
	var differs := PackedStringArray()
	if by_script != by_native:
		differs.append("drop: the script %s, the native code %s" % [var_to_str(by_script), var_to_str(by_native)])
	if queries - queries_before != script_casts:
		differs.append("casts: the script %d, the native code %d" % [script_casts, queries - queries_before])
	var cache_differs := _cache_difference(script_cache, _cache)
	if not cache_differs.is_empty():
		differs.append("cache: " + cache_differs)
	if not differs.is_empty() and sample_faults.size() < 40:
		sample_faults.append("%s sampled at %s (first cell %s, step %s, half %s, mask %d): %s" % [
			body.name, var_to_str(q), var_to_str(first), var_to_str(step), var_to_str(half), mask, "; ".join(differs)])
	return by_native


## Where the script's cache and the native code's first differ, or "" where
## they hold the same cells at the same heights, to the bit.
static func _cache_difference(by_script: Dictionary, by_native: Dictionary) -> String:
	if by_script.size() != by_native.size():
		return "the script %d cells, the native code %d" % [by_script.size(), by_native.size()]
	for cell: Variant in by_script:
		if not by_native.has(cell):
			return "%s the script's alone" % var_to_str(cell)
		if typeof(by_script[cell]) != typeof(by_native[cell]) or by_script[cell] != by_native[cell]:
			return "%s the script %s, the native code %s" % [var_to_str(cell), var_to_str(by_script[cell]), var_to_str(by_native[cell])]
	return ""


static func compute_drop(q: Vector3, first: Vector2i, heights: PackedFloat32Array, step: float = 18.0, half: float = 16.0) -> float:
	var areas := PackedFloat32Array()
	areas.resize(SIDE * SIDE)
	var low := INF
	var high := -INF
	var nearest := -1
	var distance := INF
	for iz in SIDE:
		for ix in SIDE:
			var i := iz * SIDE + ix
			if not is_finite(heights[i]):
				continue
			var cell := first + Vector2i(ix, iz) * GRID
			var area := maxf(0.0, minf(cell.x + 4.0, q.x + half) - maxf(cell.x - 4.0, q.x - half)) * maxf(0.0, minf(cell.y + 4.0, q.z + half) - maxf(cell.y - 4.0, q.z - half))
			areas[i] = area
			if area <= 0.0:
				continue
			low = minf(low, heights[i])
			high = maxf(high, heights[i])
			var d := Vector3(cell.x - q.x, heights[i] - q.y, cell.y - q.z).length_squared()
			if d < distance:
				distance = d
				nearest = i
	if nearest < 0 or q.y - high >= step:
		return 0.0
	var connected := PackedFloat32Array()
	connected.resize(SIDE * SIDE)
	connected.fill(-1.0)
	var connected_any := false
	if high - low >= step:
		connected[nearest] = maxf(areas[nearest] / 64.0, 0.01)
		# Preserve the grid's stored order and first accepted path. Later
		# samples can spread in this same pass; earlier ones wait a pass.
		var changed := true
		while changed:
			changed = false
			for i in SIDE * SIDE:
				if connected[i] < 0.0:
					continue
				for delta in [-1, -SIDE, 1, SIDE]:
					var other: int = i + delta
					if other < 0 or other >= SIDE * SIDE or (delta == -1 and i % SIDE == 0) or (delta == 1 and other % SIDE == 0):
						continue
					if areas[other] <= 0.0 or connected[other] >= 0.0 or absf(heights[i] - heights[other]) >= step:
						continue
					connected[other] = minf(connected[i], maxf(minf(areas[i], areas[other]) / 64.0, 0.01))
					connected_any = true
					changed = true
	var weighted := 0.0
	var total := 0.0
	for i in SIDE * SIDE:
		if areas[i] <= 0.0 or (high - low >= step and connected[i] < 0.0):
			continue
		var h := float(heights[i])
		var hi := clampf((q.y + 2.0 * step - h) / step, 0.0, 1.0)
		var lo := clampf((h - (q.y - 2.0 * step)) / step, 0.0, 1.0)
		var weight := hi * lo
		weight = weight * weight * areas[i]
		if connected_any:
			weight *= connected[i]
		weighted += h * weight
		total += weight
	return clampf(q.y - weighted / total, 0.0, MAX_DROP) if total > 0.0 else 0.0
