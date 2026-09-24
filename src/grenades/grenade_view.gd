class_name GrenadeView
extends Node3D

## What is seen of the grenades: each one in flight or lying still, a
## smoke's cloud, a fire's flames, and a flash of light where one goes off.
## It only reads: the grenade entities as the game's entity list hands them
## out, and the game's events for what happens once. Drawn per frame,
## between the tick before and the last, as the players are.
##
## The grenades wear the game's world models where they have been extracted
## (scripts/extract_assets.sh equipment) and a coloured stand-in where not.
## The cloud is a grey sphere per cube of smoke and the fire an orange cone
## per flame: stand-ins until CS2's smoke and fire textures are rebuilt as
## Godot's (G6), but the shapes are the simulation's own, so what hides a
## player from you here hides them from the server.

const MODELS := {
	GrenadeRules.HE: "res://assets/weapons/weapons/models/grenade/hegrenade/weapon_hegrenade.gltf",
	GrenadeRules.FLASHBANG: "res://assets/weapons/weapons/models/grenade/flashbang/weapon_flashbang.gltf",
	GrenadeRules.SMOKE: "res://assets/weapons/weapons/models/grenade/smokegrenade/weapon_smokegrenade.gltf",
	GrenadeRules.MOLOTOV: "res://assets/weapons/weapons/models/grenade/molotov/weapon_molotov.gltf",
	GrenadeRules.INCENDIARY: "res://assets/weapons/weapons/models/grenade/incendiary/weapon_incendiarygrenade.gltf",
	GrenadeRules.DECOY: "res://assets/weapons/weapons/models/grenade/decoy/weapon_decoy.gltf",
}
## The stand-ins' colours, one per grenade.
const COLOURS := {
	GrenadeRules.HE: Color(0.25, 0.4, 0.2),
	GrenadeRules.FLASHBANG: Color(0.75, 0.75, 0.8),
	GrenadeRules.SMOKE: Color(0.35, 0.45, 0.6),
	GrenadeRules.MOLOTOV: Color(0.55, 0.35, 0.15),
	GrenadeRules.INCENDIARY: Color(0.6, 0.25, 0.2),
	GrenadeRules.DECOY: Color(0.3, 0.3, 0.3),
}
## The smoke thins away over its last this-many seconds.
const SMOKE_FADE_SECONDS := 2.0
## How long a blast's light and ball last.
const BLAST_SECONDS := 0.3

var game: GameSystems

## By entity id: the grenade drawn, and the entities themselves.
var _grenades := {}
var _clouds := {}
var _fires := {}
var _entities := {}
var _smoke_mesh: SphereMesh
var _smoke_material: StandardMaterial3D
var _flame_mesh: CylinderMesh
var _flame_material: StandardMaterial3D
var _models := {}


func _ready() -> void:
	_smoke_mesh = SphereMesh.new()
	_smoke_mesh.radius = GrenadeRules.SMOKE_VOXEL * 0.85
	_smoke_mesh.height = GrenadeRules.SMOKE_VOXEL * 1.7
	_smoke_mesh.radial_segments = 8
	_smoke_mesh.rings = 4
	_smoke_material = StandardMaterial3D.new()
	_smoke_material.albedo_color = Color(0.72, 0.73, 0.74)
	_smoke_material.roughness = 1.0
	_smoke_mesh.material = _smoke_material
	_flame_mesh = CylinderMesh.new()
	_flame_mesh.top_radius = 0.0
	_flame_mesh.bottom_radius = 12.0
	_flame_mesh.height = 40.0
	_flame_mesh.radial_segments = 6
	_flame_material = StandardMaterial3D.new()
	_flame_material.albedo_color = Color(1.0, 0.45, 0.1)
	_flame_material.emission_enabled = true
	_flame_material.emission = Color(1.0, 0.4, 0.05)
	_flame_material.emission_energy_multiplier = 2.0
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mesh.material = _flame_material
	# The world models, where there are any, loaded once now rather than as
	# grenades are thrown.
	for weapon_class: String in MODELS:
		var path: String = MODELS[weapon_class]
		if ResourceLoader.exists(path):
			_models[weapon_class] = load(path)


## Starts drawing a game's grenades.
func watch(p_game: GameSystems) -> void:
	game = p_game
	game.entities.spawned.connect(_on_spawned)
	game.entities.removed.connect(_on_removed)
	game.events.listen(&"hegrenade_detonate", _on_blast)
	game.events.listen(&"flashbang_detonate", _on_flash)
	game.events.listen(&"decoy_firing", _on_decoy_shot)
	game.events.listen(&"decoy_detonate", _on_blast)


func _on_spawned(entity: SimEntity) -> void:
	if entity is GrenadeEntity:
		var grenade := entity as GrenadeEntity
		_entities[entity.id] = entity
		_grenades[entity.id] = _grenade_model(grenade.weapon_class)
	elif entity is InfernoEntity:
		_entities[entity.id] = entity
		_fires[entity.id] = _multimesh(_flame_mesh, GrenadeRules.FIRE_MOST_FLAMES)


func _on_removed(entity: SimEntity) -> void:
	_entities.erase(entity.id)
	for drawn: Dictionary in [_grenades, _clouds, _fires]:
		if drawn.has(entity.id):
			(drawn[entity.id] as Node).queue_free()
			drawn.erase(entity.id)


func _process(_delta: float) -> void:
	if game == null:
		return
	var fraction := Engine.get_physics_interpolation_fraction()
	var now := draw_usec()
	for id: int in _entities:
		var entity: SimEntity = _entities[id]
		if entity is GrenadeEntity:
			_draw_grenade(entity as GrenadeEntity, fraction, now)
		elif entity is InfernoEntity:
			_draw_fire(id, entity as InfernoEntity, now)


## The simulation time a frame falls at: between the last two ticks.
static func draw_usec() -> int:
	var tick := SimClock.tick_usec()
	return SimClock.now_usec() - tick + int(Engine.get_physics_interpolation_fraction() * tick)


func _draw_grenade(grenade: GrenadeEntity, fraction: float, now: int) -> void:
	var model: Node3D = _grenades[grenade.id]
	model.position = grenade.previous_position.lerp(grenade.position, fraction)
	model.visible = grenade.phase != GrenadeEntity.Phase.GONE
	if grenade.phase == GrenadeEntity.Phase.FLYING and not grenade.flight.at_rest:
		# A tumble to show it flying; nothing reads it.
		model.rotation = Vector3(grenade.age(now) * 9.0, grenade.age(now) * 4.0, 0.0)
	if grenade.cloud != null:
		if not _clouds.has(grenade.id):
			_clouds[grenade.id] = _multimesh(_smoke_mesh, GrenadeRules.SMOKE_VOXELS)
		_draw_cloud(_clouds[grenade.id], grenade, now)


func _draw_cloud(drawn: MultiMeshInstance3D, grenade: GrenadeEntity, now: int) -> void:
	var centres := grenade.cloud.thick_centres(now)
	var left := float(grenade.popped_usec + int(GrenadeRules.SMOKE_SECONDS * 1_000_000.0) - now) / 1_000_000.0
	var thin := clampf(left / SMOKE_FADE_SECONDS, 0.05, 1.0)
	var multimesh := drawn.multimesh
	var count := mini(centres.size(), multimesh.instance_count)
	var buffer := PackedFloat32Array()
	buffer.resize(multimesh.instance_count * 12)
	for i in count:
		var centre := centres[i]
		# Lumpy rather than a grid of equal balls, the same lumps every frame.
		var size := (0.8 + 0.35 * float(hash(Vector3i(centre)) % 100) / 100.0) * thin
		var at := i * 12
		buffer[at] = size
		buffer[at + 3] = centre.x
		buffer[at + 5] = size
		buffer[at + 7] = centre.y
		buffer[at + 10] = size
		buffer[at + 11] = centre.z
	multimesh.buffer = buffer
	multimesh.visible_instance_count = count


func _draw_fire(id: int, inferno: InfernoEntity, now: int) -> void:
	var drawn: MultiMeshInstance3D = _fires[id]
	var multimesh := drawn.multimesh
	var flames := inferno.fire.flames
	var count := mini(flames.size(), multimesh.instance_count)
	var t := float(now) / 1_000_000.0
	for i in count:
		var flicker := 0.8 + 0.3 * sin(t * 13.0 + i * 1.7)
		var stretch := Basis.from_scale(Vector3(1.0, flicker, 1.0))
		multimesh.set_instance_transform(i, Transform3D(stretch, flames[i] + Vector3.UP * 20.0 * flicker))
	multimesh.visible_instance_count = count


func _on_blast(event: GameEvent) -> void:
	var at := GrenadeSystem.position_of(event.fields)
	var big := event.name == &"hegrenade_detonate"
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.7, 0.3, 0.8)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = material
	ball.position = at
	add_child(ball)
	var tween := ball.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE * (90.0 if big else 20.0), BLAST_SECONDS)
	tween.tween_property(material, "albedo_color:a", 0.0, BLAST_SECONDS)
	tween.chain().tween_callback(ball.queue_free)
	_light(at, Color(1.0, 0.6, 0.3), 8.0 if big else 2.0, 600.0 if big else 200.0)


func _on_flash(event: GameEvent) -> void:
	_light(GrenadeSystem.position_of(event.fields), Color.WHITE, 16.0, 1200.0)


func _on_decoy_shot(event: GameEvent) -> void:
	_light(GrenadeSystem.position_of(event.fields), Color(1.0, 0.8, 0.5), 2.0, 150.0)


## A burst of light that goes out almost at once.
func _light(at: Vector3, colour: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at + Vector3.UP * 8.0
	light.light_color = colour
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, BLAST_SECONDS)
	tween.tween_callback(light.queue_free)


func _grenade_model(weapon_class: String) -> Node3D:
	var model: Node3D
	var packed := _models.get(weapon_class) as PackedScene
	if packed != null:
		model = packed.instantiate() as Node3D
		# The export is in metres; the world is in units.
		model.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	else:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 1.6
		capsule.height = 5.0
		mesh.mesh = capsule
		var material := StandardMaterial3D.new()
		material.albedo_color = COLOURS.get(weapon_class, Color.GRAY)
		mesh.material_override = material
		model = mesh
	add_child(model)
	return model


func _multimesh(mesh: Mesh, most: int) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = most
	multimesh.visible_instance_count = 0
	var drawn := MultiMeshInstance3D.new()
	drawn.multimesh = multimesh
	# The cloud is its cubes: its box is wherever they reach, not the mesh's.
	drawn.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
	add_child(drawn)
	return drawn
