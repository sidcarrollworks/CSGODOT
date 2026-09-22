class_name BulletImpacts
extends Node3D

## Where the rounds land: a bullet hole on the surface and the sound of
## it, both by what the surface is. One of these in a scene, in the
## "bullet_impacts" group, and every shooter reports its hits to it
## (mark); a scene without one has silent, markless walls, as before.
##
## The holes are the game's decal textures (scripts/extract_assets.sh
## sounds fetches them with the impact sounds): concrete, plaster and metal,
## which is what dust2 is made of. Each is a Decal projected a little way
## into the surface along the round's path, turned at random, and there are
## only so many at once; the oldest goes when a new one is needed. The
## sounds are the game's impact sets by surface, from the hit.

const DECALS_ROOT := "res://assets/decals/materials/decals"
## Decal sets by surface, as directory and file stem under DECALS_ROOT.
const DECAL_SETS := {
	"concrete": "concrete/bullethole_concrete_",
	"plaster": "plaster/plaster",
	"metal": "metal/bullethole_metal_",
}
## Impact sound sets by surface, as stems under the sound bank.
const SOUND_SETS := {
	"concrete": "physics/concrete/concrete_impact_bullet",
	"sand": "physics/surfaces/sand_impact_bullet",
	"dirt": "physics/surfaces/dirt_impact_bullet",
	"tile": "physics/surfaces/tile_impact_bullet",
	"carpet": "physics/surfaces/carpet_impact_bullet",
	"grass": "physics/surfaces/grass_impact_bullet",
	"metal": "physics/metal/metal_solid_impact_bullet",
	"wood": "physics/wood/wood_solid_impact_bullet",
	"default": "physics/surfaces/default_impact_bullet",
}
## The footstep sets (Footsteps.set_for) to an impact surface.
const BY_FOOTSTEP_SET := {
	"concrete_ct": "concrete", "sand": "sand", "dirt": "dirt", "tile": "tile", "carpet": "carpet",
	"grass": "grass", "gravel": "dirt", "wood": "wood", "metal_solid": "metal", "metal_vent": "metal",
	"metal_chainlink": "metal", "metal_grate": "metal", "glass": "default", "rubber": "default",
	"plastic_barrel": "default", "mud": "dirt",
}
## Which hole a surface gets: sand and dirt take concrete's, the map's
## walls being plaster over it.
const HOLE_FOR := {"concrete": "concrete", "sand": "plaster", "dirt": "plaster", "tile": "concrete", "metal": "metal", "wood": "concrete"}

## Holes at once, and their size in units.
@export var max_holes: int = 96
@export var hole_size: float = 5.0
## Godot's 3D audio is set out in metres; the map is in inches.
const METRE := 39.37
const SOUND_DB := -8.0

var holes: int = 0
var _hole_nodes: Array[Decal] = []
var _next_hole: int = 0
var _textures := {}  # set -> Array[Texture2D]
var _players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"bullet_impacts")
	for i in 8:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 8.0 * METRE
		player.max_distance = 120.0 * METRE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_players.append(player)


## Reports a shot's result to the scene's impacts, if it has any.
static func mark_in(tree: SceneTree, result: Hitscan.Result) -> void:
	var impacts := tree.get_first_node_in_group(&"bullet_impacts") as BulletImpacts
	if impacts != null:
		impacts.mark(result)


## A hole and a sound where a round met the world. A round that met a
## person leaves nothing here.
func mark(result: Hitscan.Result) -> void:
	if not result.hit or result.hitbox != null:
		return
	var surface := surface_for(result.surface)
	_sound(surface, result.position)
	_hole(surface, result.position, result.normal)


## The impact surface for a hull part's name.
static func surface_for(hull_name: String) -> String:
	return BY_FOOTSTEP_SET.get(Footsteps.set_for(hull_name), "default")


func _sound(surface: String, at: Vector3) -> void:
	if not SoundBank.available():
		return
	var stream := SoundBank.randomizer(SOUND_SETS.get(surface, SOUND_SETS["default"]))
	if stream == null:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.global_position = at
	if player.stream != stream:
		player.stream = stream
	player.volume_db = SOUND_DB
	player.play()


func _hole(surface: String, at: Vector3, normal: Vector3) -> void:
	var textures := _textures_for(HOLE_FOR.get(surface, "concrete"))
	if textures.is_empty():
		return
	var decal: Decal
	if _hole_nodes.size() < max_holes:
		decal = Decal.new()
		decal.size = Vector3(hole_size, hole_size, hole_size)
		decal.cull_mask = 1
		decal.albedo_mix = 1.0
		add_child(decal)
		_hole_nodes.append(decal)
	else:
		decal = _hole_nodes[_next_hole]
		_next_hole = (_next_hole + 1) % _hole_nodes.size()
	decal.texture_albedo = textures[_rng.randi_range(0, textures.size() - 1)]
	# A decal projects down its own -Y; that is turned into the surface,
	# and the hole spun about it so no two look alike.
	var into := -normal.normalized()
	var spin := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
	decal.global_transform = Transform3D(_basis_facing(into) * spin, at + normal.normalized() * hole_size * 0.3)
	holes += 1


## The textures of a hole set, found once.
func _textures_for(set_name: String) -> Array:
	if _textures.has(set_name):
		return _textures[set_name]
	var found := []
	var stem: String = DECAL_SETS.get(set_name, "")
	var dir := DirAccess.open(DECALS_ROOT.path_join(stem.get_base_dir()))
	if dir != null and not stem.is_empty():
		var files := dir.get_files()
		files.sort()
		for file in files:
			if file.begins_with(stem.get_file()) and file.get_extension().to_lower() == "png":
				var texture := load(DECALS_ROOT.path_join(stem.get_base_dir()).path_join(file)) as Texture2D
				if texture != null:
					found.append(texture)
	_textures[set_name] = found
	return found


## A basis whose -Y points along a direction.
static func _basis_facing(direction: Vector3) -> Basis:
	var down := direction.normalized()
	var up := -down
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 1e-6:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	return Basis(side, up, side.cross(up))
