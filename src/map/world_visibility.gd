class_name WorldVisibility
extends Node

## CS2's precomputed visibility (the map's world_visibility.vvis_c): which
## parts of the map can be seen from which, so that what cannot be seen from
## where the camera is, is not drawn. It is also what keeps dust2's kasbah
## towers at B out of sight from T spawn. CS2 draws the 3D skybox first and
## the world over it, so a far tower it drew would stand in front of the
## skybox's dome. It does not draw it, because nothing at T spawn can see it
## (Sid's screenshot from T spawn, 2026-09-24). The world is drawn over the
## skybox here the same way (FarMaterials), so it needs the same culling.
##
## The map is cut into up to 4096 clusters, and each cluster has a row of
## bits saying which clusters can be seen from it. Where the clusters are is
## an octree over the map whose leaves are diced into a 4 by 4 by 4 grid of
## cells; each cluster reaching a leaf has a 64-bit mask of the cells it
## covers. A world mesh belongs to every cluster its bounds touch, and is
## drawn while any of them is in the row of the camera's cluster. This
## follows Source 2 Viewer's reading of the file's "VXVS" block
## (VoxelVisibility.cs; Scene.IsNodeInPvs).
##
## A mesh that is not drawn still casts its shadow (it goes to shadows-only):
## a building behind you still shades the street in front of you. Only the
## map's own meshes are culled; the 3D skybox, the players and everything
## that moves are drawn wherever they are. The culling runs per frame, from
## whichever camera is drawing, and does its work only when the camera
## moves into another cluster.

## Where the extraction puts it (scripts/extract_assets.sh visibility),
## beside the world glTF: the compiled file, and its data block decompiled
## to text, which holds the counts and offsets.
const COMPILED_FILE := "world_visibility.vvis_c"
const DATA_FILE := "world_visibility.vvis"

## Cluster 0 stands in wherever the octree cannot answer, and is in every row.
const CATCH_ALL := 0
## A box is grown by this, so one flush against a cell's edge still reaches
## into the cell on its far side.
const QUERY_EPSILON := 1.0 / 32.0
## A box this big on two axes or more takes the clusters of whole octree
## nodes (clusters_in).
const LARGE_BOX := 1024.0

var cluster_count := 0
var row_bytes := 0
## The octree's box, in Source's axes and units.
var min_bounds := Vector3.ZERO
var max_bounds := Vector3.ZERO

# The file's VXVS block, which the rows and the enclosed clusters are read
# from in place; the rest is decoded once, into arrays that index quickly.
var _block := PackedByteArray()
var _nodes := PackedInt32Array()  # Two words a node.
var _regions := PackedInt64Array()
var _enclosed_lists := PackedInt32Array()  # Offset and count a list.
var _enclosed := 0
var _masks := PackedInt64Array()
var _rows := 0

# The masks of the cells a range along one axis covers, by which of its
# four cells it reaches (a four-bit set); the grid's cell (x, y, z) is bit
# x + 4y + 16z.
static var _axis_masks: Array[PackedInt64Array] = [_axis_table(1), _axis_table(4), _axis_table(16)]

# Culling: the meshes, how each casts its shadow when drawn, the meshes in
# each cluster, which are drawn now, and the clusters they are drawn for.
var _meshes: Array[MeshInstance3D] = []
var _casts := PackedInt32Array()
var _cluster_meshes: Array[PackedInt32Array] = []
var _drawn := PackedByteArray()
var _shown_from := PackedInt32Array([-1])
var _task := -1


## The map's visibility beside a world glTF in map_dir, or null where it
## was not extracted or holds none.
static func load_for(map_dir: String) -> WorldVisibility:
	var compiled := FileAccess.get_file_as_bytes(map_dir.path_join(COMPILED_FILE))
	var data := FileAccess.get_file_as_string(map_dir.path_join(DATA_FILE))
	if compiled.is_empty() or data.is_empty():
		return null
	var visibility := WorldVisibility.new()
	if not visibility.read(compiled, data):
		visibility.free()
		return null
	return visibility


## Reads a compiled .vvis_c and its data block as text. Whether it holds
## visibility this can use: the octree layout, with more than two clusters
## (the game culls nothing with fewer).
func read(compiled: PackedByteArray, data: String) -> bool:
	var block := _block_of(compiled, "VXVS")
	var nodes := _sub_block(data, "m_NodeBlock")
	var regions := _sub_block(data, "m_RegionBlock")
	var enclosed_lists := _sub_block(data, "m_EnclosedClusterListBlock")
	var enclosed := _sub_block(data, "m_EnclosedClustersBlock")
	var masks := _sub_block(data, "m_MasksBlock")
	var rows := _sub_block(data, "m_nVisBlocks")
	var clusters := _number(data, "m_nBaseClusterCount")
	var per_row := _number(data, "m_nPVSBytesPerCluster")
	if clusters <= 2 or per_row <= 0 or nodes.y <= 0 or rows.x + rows.y > block.size() \
			or rows.y < clusters * per_row or masks.x + masks.y * 8 > block.size() \
			or regions.x + regions.y * 8 > block.size() or enclosed.x + enclosed.y * 2 > block.size():
		return false
	cluster_count = clusters
	row_bytes = per_row
	min_bounds = _vector(data, "m_vMinBounds")
	max_bounds = _vector(data, "m_vMaxBounds")
	_block = block
	_nodes = block.slice(nodes.x, nodes.x + nodes.y * 8).to_int32_array()
	_regions = block.slice(regions.x, regions.x + regions.y * 8).to_int64_array()
	_enclosed_lists = block.slice(enclosed_lists.x, enclosed_lists.x + enclosed_lists.y * 8).to_int32_array()
	_enclosed = enclosed.x
	_masks = block.slice(masks.x, masks.x + masks.y * 8).to_int64_array()
	_rows = rows.x
	return true


## The clusters at a point (Source's axes): one, as a rule, and none outside
## them all.
func clusters_at(point: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var leaf := _leaf_at(point)
	if leaf.is_empty():
		return out
	var mask := _point_mask(point, leaf[1], leaf[2])
	var node: int = leaf[0]
	var start := _offset(node)
	for r in mini(_nodes[node * 2 + 1] & 0xFF, _regions.size() - start):
		var region := _regions[start + r]
		if region & 0x7FFF < cluster_count and mask & _mask(region) != 0:
			out.append(region & 0x7FFF)
	return out


## What can be seen from any of these clusters: their rows together, a bit
## a cluster. Empty for none, which is taken as everything.
func row_of(clusters: PackedInt32Array) -> PackedByteArray:
	var row := PackedByteArray()
	for cluster in clusters:
		var own := _block.slice(_rows + cluster * row_bytes, _rows + (cluster + 1) * row_bytes)
		if row.is_empty():
			row = own
		else:
			for i in row.size():
				row[i] |= own[i]
	return row


## Every cluster a box (Source's axes) touches. Where the box covers a whole
## octree node that lists the clusters in it, the list is the answer for
## that node: the same clusters as walking its leaves (all 17270 of dust2's
## lists are), without the walk. A box over LARGE_BOX on two axes takes
## the list of any node it reaches, as the game does: a few more clusters
## than it touches, for a walk that would otherwise go down every leaf
## along its sides.
func clusters_in(box_min: Vector3, box_max: Vector3) -> PackedInt32Array:
	var low := box_min.min(box_max) - Vector3.ONE * QUERY_EPSILON
	var high := box_min.max(box_max) + Vector3.ONE * QUERY_EPSILON
	if AABB(low, high - low).encloses(AABB(min_bounds, max_bounds - min_bounds)):
		return PackedInt32Array([CATCH_ALL])
	var size := high - low
	var large := int(size.x >= LARGE_BOX) + int(size.y >= LARGE_BOX) + int(size.z >= LARGE_BOX)
	var found := PackedByteArray()
	found.resize(cluster_count)
	_box_query(0, min_bounds, max_bounds, low, high, found, large > 1)
	var out := PackedInt32Array()
	for cluster in found.size():
		if found[cluster] != 0:
			out.append(cluster)
	return out


## Whether a row lets a cluster be seen.
static func sees(row: PackedByteArray, cluster: int) -> bool:
	return cluster >> 3 < row.size() and row[cluster >> 3] & (1 << (cluster & 7)) != 0


## A game-space point in Source's axes, which the visibility is in.
static func to_source(game: Vector3) -> Vector3:
	return Vector3(game.z, game.x, game.y)


## Culls these meshes by the camera's cluster from now on. They must be in
## the tree, where they are to stay.
## Which clusters each mesh is in takes most of a second on dust2, so it is
## worked out on a worker thread while the rest of the map loads, and
## everything is drawn until it is known.
func cull(meshes: Array[MeshInstance3D]) -> void:
	_wait_for_clusters()
	_meshes = meshes.duplicate()
	_casts.resize(_meshes.size())
	var boxes := PackedVector3Array()
	for i in _meshes.size():
		_casts[i] = _meshes[i].cast_shadow
		var box := _meshes[i].global_transform * _meshes[i].get_aabb()
		var low := to_source(box.position)
		var high := to_source(box.end)
		boxes.append(low.min(high))
		boxes.append(low.max(high))
	_drawn.resize(_meshes.size())
	_drawn.fill(1)
	_shown_from = PackedInt32Array([-1])
	_cluster_meshes.clear()
	_task = WorkerThreadPool.add_task(_sort_into_clusters.bind(boxes), false, "Visibility clusters")


func _process(_delta: float) -> void:
	if _meshes.is_empty() or (_task >= 0 and not WorkerThreadPool.is_task_completed(_task)):
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		show_from(camera.global_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_wait_for_clusters()


## On the worker thread: the meshes in each cluster, from each mesh's box
## (two corners a mesh). Reads nothing the main thread changes.
func _sort_into_clusters(boxes: PackedVector3Array) -> void:
	var lists := []
	lists.resize(cluster_count)
	for mesh in boxes.size() >> 1:
		for cluster in clusters_in(boxes[mesh * 2], boxes[mesh * 2 + 1]):
			if lists[cluster] == null:
				lists[cluster] = []
			(lists[cluster] as Array).append(mesh)
	var sorted: Array[PackedInt32Array] = []
	for list: Variant in lists:
		sorted.append(PackedInt32Array(list) if list != null else PackedInt32Array())
	_cluster_meshes = sorted


func _wait_for_clusters() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Draws what can be seen from a game-space point, and only that. From a
## point no cluster holds, everything is drawn.
func show_from(point: Vector3) -> void:
	_wait_for_clusters()
	var clusters := clusters_at(to_source(point))
	if clusters == _shown_from:
		return
	_shown_from = clusters
	var seen := PackedByteArray()
	seen.resize(_meshes.size())
	if clusters.is_empty():
		seen.fill(1)
	var row := row_of(clusters)
	for byte in row.size():
		var bits := row[byte]
		if bits == 0:
			continue
		for bit in 8:
			if bits & (1 << bit) != 0 and byte * 8 + bit < _cluster_meshes.size():
				for mesh in _cluster_meshes[byte * 8 + bit]:
					seen[mesh] = 1
	for i in _meshes.size():
		if seen[i] == _drawn[i]:
			continue
		_drawn[i] = seen[i]
		# One that casts no shadow when drawn (a lamp's fixture) is hidden.
		if _casts[i] == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_meshes[i].visible = seen[i] != 0
		else:
			_meshes[i].cast_shadow = _casts[i] if seen[i] != 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## How many of the culled meshes are not drawn now.
func hidden_count() -> int:
	return _drawn.count(0)


func _box_query(node: int, node_min: Vector3, node_max: Vector3, low: Vector3, high: Vector3, found: PackedByteArray, loose: bool) -> void:
	if node * 2 + 1 >= _nodes.size():
		return
	var first := _nodes[node * 2]
	var second := _nodes[node * 2 + 1]
	var enclosed_list := (second >> 8) & 0xFFFFFF
	var covered := low.x <= node_min.x and low.y <= node_min.y and low.z <= node_min.z \
		and node_max.x <= high.x and node_max.y <= high.y and node_max.z <= high.z
	if enclosed_list != 0xFFFFFF and enclosed_list * 2 + 1 < _enclosed_lists.size() and (covered or loose):
		var start := _enclosed_lists[enclosed_list * 2]
		for i in _enclosed_lists[enclosed_list * 2 + 1]:
			var at := _enclosed + (start + i) * 2
			if at + 2 <= _block.size() and _block.decode_u16(at) < found.size():
				found[_block.decode_u16(at)] = 1
		return
	var offset := (first >> 1) & 0x7FFFFFFF
	if first & 1:
		var regions := mini(second & 0xFF, _regions.size() - offset)
		# Along a big box's sides most leaves hold nothing it has not found.
		var new := false
		for r in regions:
			var cluster := _regions[offset + r] & 0x7FFF
			new = new or (cluster < found.size() and found[cluster] == 0)
		if not new:
			return
		var mask := -1 if covered else _box_mask(low, high, node_min, node_max)
		if mask == 0:
			return
		for r in regions:
			var region := _regions[offset + r]
			if mask & _mask(region) != 0 and region & 0x7FFF < found.size():
				found[region & 0x7FFF] = 1
		return
	var mid := (node_min + node_max) * 0.5
	var x_low := node_min.x <= high.x and low.x <= mid.x
	var x_high := low.x <= node_max.x and mid.x <= high.x
	var y_low := node_min.y <= high.y and low.y <= mid.y
	var y_high := low.y <= node_max.y and mid.y <= high.y
	var z_low := node_min.z <= high.z and low.z <= mid.z
	var z_high := low.z <= node_max.z and mid.z <= high.z
	for octant in 8:
		var x := octant & 1 != 0
		var y := octant & 2 != 0
		var z := octant & 4 != 0
		if not ((x_high if x else x_low) and (y_high if y else y_low) and (z_high if z else z_low)):
			continue
		_box_query(
			offset + octant,
			Vector3(mid.x if x else node_min.x, mid.y if y else node_min.y, mid.z if z else node_min.z),
			Vector3(node_max.x if x else mid.x, node_max.y if y else mid.y, node_max.z if z else mid.z),
			low, high, found, loose
		)


## [leaf node, its min, its max] holding a point, or empty outside the octree.
func _leaf_at(point: Vector3) -> Array:
	if _nodes.is_empty() or point.x < min_bounds.x or point.y < min_bounds.y or point.z < min_bounds.z \
			or point.x > max_bounds.x or point.y > max_bounds.y or point.z > max_bounds.z:
		return []
	var node := 0
	var low := min_bounds
	var high := max_bounds
	while _nodes[node * 2] & 1 == 0:
		var mid := (low + high) * 0.5
		var octant := 0
		for axis in 3:
			if mid[axis] < point[axis]:
				octant |= 1 << axis
				low[axis] = mid[axis]
			else:
				high[axis] = mid[axis]
		node = _offset(node) + octant
		if node * 2 + 1 >= _nodes.size():
			return []
	return [node, low, high]


func _offset(node: int) -> int:
	return (_nodes[node * 2] >> 1) & 0x7FFFFFFF


## The mask of the cells a region covers.
func _mask(region: int) -> int:
	var index := (region >> 40) & 0xFFFFFF
	return _masks[index] if index < _masks.size() else 0


## The one cell of a leaf's grid a point is in, as a bit: the leaf halved
## twice, the first halving worth two cells along each axis.
static func _point_mask(point: Vector3, low: Vector3, high: Vector3) -> int:
	var cell := 0
	for scale: int in [2, 1]:
		var mid := (low + high) * 0.5
		for axis in 3:
			if mid[axis] < point[axis]:
				cell += scale << (2 * axis)
				low[axis] = mid[axis]
			else:
				high[axis] = mid[axis]
	return 1 << cell


## The cells of a leaf's grid a box reaches into, as bits.
static func _box_mask(low: Vector3, high: Vector3, leaf_min: Vector3, leaf_max: Vector3) -> int:
	var cell_size := (leaf_max.x - leaf_min.x) * 0.25
	if cell_size <= 0.0:
		return 0
	return _axis_masks[0][_cells(low.x, high.x, leaf_min.x, cell_size)] \
		& _axis_masks[1][_cells(low.y, high.y, leaf_min.y, cell_size)] \
		& _axis_masks[2][_cells(low.z, high.z, leaf_min.z, cell_size)]


## Which of a leaf's four cells along one axis a range reaches into, as a
## four-bit set. Cells are half open: a range that only touches one's edge
## does not enter it.
static func _cells(low: float, high: float, leaf_min: float, cell_size: float) -> int:
	var first := maxi(floori((low - leaf_min) / cell_size), 0)
	var last := mini(ceili((high - leaf_min) / cell_size) - 1, 3)
	return ((1 << (last + 1)) - (1 << first)) if first <= last else 0


## The grid bits of each set of cells along the axis whose cell index goes
## up by stride, repeated along the other two axes.
static func _axis_table(stride: int) -> PackedInt64Array:
	var table := PackedInt64Array()
	table.resize(16)
	var unit := (1 << stride) - 1
	for cells in 16:
		var mask := 0
		for cell in 4:
			if cells & (1 << cell):
				mask |= unit << (cell * stride)
		var shift := stride * 4
		while shift < 64:
			mask |= mask << shift
			shift *= 2
		table[cells] = mask
	return table


## The bytes of one block of a compiled resource, by its four-letter type.
## The header gives where its table of blocks is; each entry, its type, its
## offset from where that offset is written, and its size.
static func _block_of(compiled: PackedByteArray, type: String) -> PackedByteArray:
	if compiled.size() < 16:
		return PackedByteArray()
	var at := 8 + compiled.decode_u32(8)
	for i in compiled.decode_u32(12):
		if at + 12 > compiled.size():
			break
		if compiled.slice(at, at + 4).get_string_from_ascii() == type:
			var offset := at + 4 + compiled.decode_u32(at + 4)
			return compiled.slice(offset, offset + compiled.decode_u32(at + 8))
		at += 12
	return PackedByteArray()


static func _number(data: String, key: String) -> int:
	var found := RegEx.create_from_string(key + "\\s*=\\s*(-?\\d+)").search(data)
	return int(found.get_string(1)) if found != null else 0


static func _vector(data: String, key: String) -> Vector3:
	var found := RegEx.create_from_string(key + "\\s*=\\s*\\[([^\\]]*)\\]").search(data)
	if found == null:
		return Vector3.ZERO
	var parts := found.get_string(1).split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2])) if parts.size() == 3 else Vector3.ZERO


## (offset, count) of a block the data block lists.
static func _sub_block(data: String, key: String) -> Vector2i:
	var found := RegEx.create_from_string(
		key + "\\s*=\\s*\\{[^}]*m_nOffset\\s*=\\s*(\\d+)[^}]*m_nElementCount\\s*=\\s*(\\d+)"
	).search(data)
	return Vector2i(int(found.get_string(1)), int(found.get_string(2))) if found != null else Vector2i.ZERO
