class_name DroppedItemView
extends Node3D

## What is seen of the items on the ground (DroppedItem): each one's world
## model leaving the hand, turning as it flies, and, once it has come to
## rest, tipping over onto its thinnest side, the way it was heading. It
## only reads the game's entities, and draws them per frame between the
## tick before and the last, as the players are drawn.
##
## A model is the game's own (scripts/extract_assets.sh weapons and
## equipment) and a grey box where it has not been extracted. Each class's
## model is read once and its size measured then (lying()).

## The stand-in's size, in units, where there is no model: longest along
## its +Z, as a gun is.
const STAND_IN := Vector3(4.0, 3.0, 24.0)
## How long an item takes to tip over onto its side once it has come to
## rest, in seconds of simulation time. By eye.
const SETTLE_SECONDS := 0.2

var game: GameSystems

## By entity id: the item and its drawn model, and those still moving or
## settling, which are placed every frame; one lying still is placed once
## more, where it lies, and left.
var _items := {}
var _models := {}
var _moving := {}
## Dropped since the last frame, their models to be built in the next: the
## tick they fell on is the simulation's, and a model built there read the
## disk and built its nodes in it (41 ms for a class's first, dust2).
var _arriving: Array[int] = []
## By class: the scene, and how it lies (the turn that puts its thinnest
## side down and the lift that puts its lowest point on the ground).
var _scenes := {}
var _lying := {}


## Starts drawing a game's items on the ground, those there already too.
func watch(p_game: GameSystems) -> void:
	game = p_game
	game.entities.spawned.connect(_on_spawned)
	game.entities.removed.connect(_on_removed)
	for entity in game.entities.all():
		_on_spawned(entity)


## How many items are drawn.
func drawn() -> int:
	return _models.size()


## The model drawn for an entity, or null.
func model_of(entity_id: int) -> Node3D:
	return _models.get(entity_id)


func _on_spawned(entity: SimEntity) -> void:
	var item := entity as DroppedItem
	if item == null or item.entry == null:
		return
	_items[item.id] = item
	_arriving.append(item.id)


## The models of the items dropped since the last frame. One whose class's
## model has not been read yet waits for a worker thread to read it
## (RigModel.read_ahead), a frame or a few, rather than hold the frame up
## reading it; headless, nothing is drawn, and it is read at once.
func _build_arrived() -> void:
	var waiting: Array[int] = []
	for id in _arriving:
		var item: DroppedItem = _items.get(id)
		if item == null:
			continue
		if not _scenes.has(item.entry.item.item_class) and DisplayServer.get_name() != "headless":
			var path := _model_path(item.entry)
			RigModel.read_ahead(PackedStringArray([path]))
			if RigModel.reading(path):
				waiting.append(id)
				continue
		var model := _model_for(item.entry)
		add_child(model)
		_models[id] = model
		_moving[id] = true
		_place(item, model, 0.0, DrawClock.usec())
		ProbeMaterials.light_model(model, model.global_position)
	_arriving = waiting


func _on_removed(entity: SimEntity) -> void:
	_items.erase(entity.id)
	_moving.erase(entity.id)
	if _models.has(entity.id):
		(_models[entity.id] as Node).queue_free()
		_models.erase(entity.id)


func _process(_delta: float) -> void:
	if not _arriving.is_empty():
		_build_arrived()
	if _moving.is_empty():
		return
	var fraction := DrawClock.fraction()
	var now := DrawClock.usec()
	for id: int in _moving.keys():
		var item: DroppedItem = _items[id]
		var model: Node3D = _models[id]
		if _place(item, model, fraction, now):
			_moving.erase(id)
		# Lit from the map's light probes where it is, which hold the map's
		# shadow from the sun; the live shadow map no longer does.
		ProbeMaterials.light_model(model, model.global_position)


## Draws the item as the frame falls between its last two ticks: in
## flight, where and how it was turning; at rest, tipping over onto its
## side. True once it lies as it will stay.
func _place(item: DroppedItem, model: Node3D, fraction: float, now_usec: int) -> bool:
	if not item.resting:
		model.transform = Transform3D(
			item.previous_basis.slerp(item.basis, fraction),
			item.previous_position.lerp(item.position, fraction)
		)
		return false
	var lying: Transform3D = _lying[item.entry.item.item_class]
	var down := Transform3D(Basis(Vector3.UP, heading(item.basis)) * lying.basis, item.position + lying.origin)
	var settled := clampf(float(now_usec - item.rested_usec) / (SETTLE_SECONDS * 1_000_000.0), 0.0, 1.0)
	var t := smoothstep(0.0, 1.0, settled)
	model.transform = Transform3D(
		item.basis.slerp(down.basis, t),
		item.position.lerp(down.origin, t)
	)
	return settled >= 1.0


## The way an item points along the ground, as a turn about the up axis
## from +Z: where its muzzle points, or its top when the muzzle points
## straight up or down.
static func heading(basis: Basis) -> float:
	var along := Vector3(basis.z.x, 0.0, basis.z.z)
	if along.length() < 0.2:
		along = Vector3(basis.y.x, 0.0, basis.y.z)
	if along.length() < 0.001:
		return 0.0
	return atan2(along.x, along.z)


## Where an item's world model is: its gun's, or its row's in the tables.
static func _model_path(entry: Inventory.Entry) -> String:
	var path := entry.weapon.data.model_path if entry.weapon != null else ""
	if path.is_empty():
		path = String(WeaponLibrary.look(entry.item.item_class).get("model_path", ""))
	return path


## A new model of an item, and how its class lies, measured the first time.
func _model_for(entry: Inventory.Entry) -> Node3D:
	var item_class := entry.item.item_class
	if not _scenes.has(item_class):
		_scenes[item_class] = RigModel.preload_scene(_model_path(entry))
	var model: Node3D
	var packed := _scenes[item_class] as PackedScene
	if packed != null:
		model = Node3D.new()
		var scene := packed.instantiate() as Node3D
		scene.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
		model.add_child(scene)
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		for mesh: MeshInstance3D in meshes:
			# The body for legacy skins, where there is another, and a
			# holster only a body wears.
			if RigModel.is_spare_body(mesh, meshes) or mesh.name.ends_with("_eholster"):
				mesh.visible = false
	else:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = STAND_IN
		box.mesh = mesh
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.35, 0.35, 0.37)
		box.material_override = paint
		model = Node3D.new()
		model.add_child(box)
	if not _lying.has(item_class):
		_lying[item_class] = lying(model)
	return model


## How a model lies on the ground: turned so its thinnest side is down, and
## lifted so its lowest point is at the ground, as a transform whose basis is
## the turn and whose origin is the lift.
static func lying(model: Node3D) -> Transform3D:
	var box := bounds(model)
	var turn := Basis.IDENTITY
	var size := box.size
	if size.x <= size.y and size.x <= size.z:
		# On its side: its width upright.
		turn = Basis(Vector3.BACK, PI * 0.5)
	elif size.z < size.y:
		turn = Basis(Vector3.RIGHT, PI * 0.5)
	var lowest := INF
	for corner in 8:
		lowest = minf(lowest, (turn * box.get_endpoint(corner)).y)
	return Transform3D(turn, Vector3.UP * -lowest)


## The box round every mesh shown in a model, in the model's own space.
static func bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.visible:
			continue
		var to_model := Transform3D.IDENTITY
		var node: Node = mesh
		while node != model and node is Node3D:
			to_model = (node as Node3D).transform * to_model
			node = node.get_parent()
		var own := to_model * mesh.get_aabb()
		box = own if first else box.merge(own)
		first = false
	return box
