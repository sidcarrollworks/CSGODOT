class_name DroppedItemView
extends Node3D

## What is seen of the items on the ground (DroppedItem): each one's world
## model falling and then lying where it came to rest, a gun on its side. It
## only reads the game's entities, and draws them per frame between the tick
## before and the last, as the players are drawn.
##
## A model is the game's own (scripts/extract_assets.sh weapons and
## equipment) and a grey box where it has not been extracted. Each class's
## model is read once and its size measured then; a model lies on its
## thinnest side, turned the way it was thrown.

## The stand-in's size, in units, where there is no model.
const STAND_IN := Vector3(4.0, 3.0, 24.0)

var game: GameSystems

## By entity id: the item and its drawn model, and those still moving, which
## are placed every frame; one at rest is placed once more, where it lies.
var _items := {}
var _models := {}
var _moving := {}
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


func _on_spawned(entity: SimEntity) -> void:
	var item := entity as DroppedItem
	if item == null or item.entry == null:
		return
	_items[item.id] = item
	var model := _model_for(item.entry)
	# Turned the way it was thrown, or any way if it was only let fall.
	var yaw := atan2(item.velocity.x, item.velocity.z) if Vector2(item.velocity.x, item.velocity.z).length() > 1.0 \
		else float(hash(item.id) % 360) * PI / 180.0
	model.basis = Basis(Vector3.UP, yaw) * (_lying[item.entry.item.item_class] as Transform3D).basis
	model.set_meta(&"lift", (_lying[item.entry.item.item_class] as Transform3D).origin)
	add_child(model)
	_models[item.id] = model
	_moving[item.id] = true
	_place(item, model, 0.0)


func _on_removed(entity: SimEntity) -> void:
	_items.erase(entity.id)
	_moving.erase(entity.id)
	if _models.has(entity.id):
		(_models[entity.id] as Node).queue_free()
		_models.erase(entity.id)


func _process(_delta: float) -> void:
	var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	for id: int in _moving.keys():
		var item: DroppedItem = _items[id]
		if item.resting and item.previous_position == item.position:
			_place(item, _models[id], 1.0)
			_moving.erase(id)
		else:
			_place(item, _models[id], fraction)


func _place(item: DroppedItem, model: Node3D, fraction: float) -> void:
	model.position = item.previous_position.lerp(item.position, fraction) + (model.get_meta(&"lift") as Vector3)


## A new model of an item, and how its class lies, measured the first time.
func _model_for(entry: Inventory.Entry) -> Node3D:
	var item_class := entry.item.item_class
	if not _scenes.has(item_class):
		var path := entry.weapon.data.model_path if entry.weapon != null else ""
		if path.is_empty():
			path = String(WeaponLibrary.look(item_class).get("model_path", ""))
		_scenes[item_class] = load(path) as PackedScene if not path.is_empty() and ResourceLoader.exists(path) else null
	var model: Node3D
	var packed := _scenes[item_class] as PackedScene
	if packed != null:
		model = Node3D.new()
		var scene := packed.instantiate() as Node3D
		scene.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
		model.add_child(scene)
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		for mesh: MeshInstance3D in meshes:
			# The body for old hardware, where there is another, and a
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
