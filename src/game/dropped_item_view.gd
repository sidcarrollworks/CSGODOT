class_name DroppedItemView
extends Node3D

## What is seen of the items on the ground (DroppedItem): each one's world
## model leaving the hand, turning as it flies, and lying as it came to
## rest, drawn where the simulation's body is (ItemPhysics.Hull.model_of:
## the body is the centre of mass, the model is drawn about it). It only
## reads the game's entities, and draws them per frame between the tick
## before and the last, as the players are drawn; it makes up nothing of
## how an item lies.
##
## A model is the game's own (scripts/extract_assets.sh weapons and
## equipment) and a grey box where it has not been extracted. A model is
## posed in its 'dropped' clip, or 'dropped_empty' for an empty gun, where
## it has one (the Dual Berettas' lays the two pistols side by side), and
## drawn by the bone its hull is bound to, so a clip that moves the root
## bone does not move the gun off its body.

## The stand-in's size, in units, where there is no model: longest along
## its +Z, as a gun is. The stand-in's body is the same box
## (ItemPhysics.STAND_IN).
const STAND_IN := ItemPhysics.STAND_IN
## The clips a world model lies in, loaded or empty.
const DROPPED_CLIP := "dropped"
const DROPPED_EMPTY_CLIP := "dropped_empty"

var game: GameSystems

## By entity id: the item and its drawn model, and those still moving,
## which are placed every frame; one lying still is placed once more, where
## it lies, and left.
var _items := {}
var _models := {}
var _moving := {}
## Dropped since the last frame, their models to be built in the next: the
## tick they fell on is the simulation's, and a model built there read the
## disk and built its nodes in it (41 ms for a class's first, dust2).
var _arriving: Array[int] = []
## By class: the scene.
var _scenes := {}
## By entity id: how far the pose moved the hull's bone off its rest, taken
## out again where the model is drawn.
var _pose_fix := {}


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
		_pose_fix[id] = pose(model, item)
		_place(item, model, 0.0)
		ProbeMaterials.light_model(model, item.position)
	_arriving = waiting


func _on_removed(entity: SimEntity) -> void:
	_items.erase(entity.id)
	_moving.erase(entity.id)
	_pose_fix.erase(entity.id)
	if _models.has(entity.id):
		(_models[entity.id] as Node).queue_free()
		_models.erase(entity.id)


func _process(_delta: float) -> void:
	if not _arriving.is_empty():
		_build_arrived()
	if _moving.is_empty():
		return
	var fraction := DrawClock.fraction()
	for id: int in _moving.keys():
		var item: DroppedItem = _items[id]
		var model: Node3D = _models[id]
		if _place(item, model, fraction):
			_moving.erase(id)
		# Lit from the map's light probes where it is, which hold the map's
		# shadow from the sun; the live shadow map no longer does. Sampled
		# at the centre of mass, the middle of what is drawn.
		ProbeMaterials.light_model(model, item.previous_position.lerp(item.position, fraction))


## Draws the item as the frame falls between its last two ticks. True once
## it lies still, drawn where it lies.
func _place(item: DroppedItem, model: Node3D, fraction: float) -> bool:
	var body := Transform3D(
		item.previous_basis.slerp(item.basis, fraction).orthonormalized(),
		item.previous_position.lerp(item.position, fraction)
	)
	if item.resting:
		body = Transform3D(item.basis, item.position)
	model.transform = item.physics().model_of(body) * (_pose_fix.get(item.id, Transform3D.IDENTITY) as Transform3D)
	return item.resting


## Poses a model in its dropped clip, where it has one, and says how to
## draw it so the bone its hull is bound to stays where it rests: the
## transform, in the model's space, from the posed bone back to its rest.
static func pose(model: Node3D, item: DroppedItem) -> Transform3D:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return Transform3D.IDENTITY
	var player := players[0] as AnimationPlayer
	var empty := item.entry != null and item.entry.weapon != null and item.entry.weapon.ammo <= 0
	var clip := _clip_named(player, DROPPED_EMPTY_CLIP if empty else DROPPED_CLIP)
	if clip.is_empty() and empty:
		clip = _clip_named(player, DROPPED_CLIP)
	if clip.is_empty():
		return Transform3D.IDENTITY
	player.play(clip)
	player.seek(0.0, true)
	player.pause()
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var bone_name := item.physics().bone
	if skeletons.is_empty() or bone_name.is_empty():
		return Transform3D.IDENTITY
	var skeleton := skeletons[0] as Skeleton3D
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return Transform3D.IDENTITY
	var to_model := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != model and node is Node3D:
		to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	var rest := to_model * skeleton.get_bone_global_rest(bone)
	var posed := to_model * skeleton.get_bone_global_pose(bone)
	return rest * posed.affine_inverse()


## Where a drawn model puts its hull: the model's frame as its bone is
## drawn, which is the model's transform less whatever the pose moved the
## bone off its rest (pose()). What the checks measure a drawn gun by; a
## model without the bone, the stand-in among them, is its own transform.
static func drawn_frame(model: Node3D, bone_name: String) -> Transform3D:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or bone_name.is_empty():
		return model.transform
	var skeleton := skeletons[0] as Skeleton3D
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return model.transform
	var to_model := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != model and node is Node3D:
		to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	var rest := to_model * skeleton.get_bone_global_rest(bone)
	var posed := to_model * skeleton.get_bone_global_pose(bone)
	return model.transform * posed * rest.affine_inverse()


## The animation of a player called name, or ending in it after a library's
## prefix; empty if none.
static func _clip_named(player: AnimationPlayer, name: String) -> String:
	for clip in player.get_animation_list():
		if clip == name or String(clip).ends_with("/" + name):
			return clip
	return ""


## Where an item's world model is: its gun's, or its row's in the tables.
static func _model_path(entry: Inventory.Entry) -> String:
	var path := entry.weapon.data.model_path if entry.weapon != null else ""
	if path.is_empty():
		path = String(WeaponLibrary.look(entry.item.item_class).get("model_path", ""))
	return path


## A new model of an item.
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
	return model


## How a model lies on the ground: turned so its thinnest side is down, and
## lifted so its lowest point is at the ground, as a transform whose basis is
## the turn and whose origin is the lift. The dropped bomb's (C4View); a
## dropped item lies as its body came to rest.
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
