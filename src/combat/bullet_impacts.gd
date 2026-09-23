class_name BulletImpacts
extends Node3D

## Where the rounds land: a bullet hole on the surface and the sound of
## it, both by what the surface is. One of these in a scene, in the
## "bullet_impacts" group, and every shooter reports its hits to it
## (mark); a scene without one has silent, markless walls, as before.
##
## The holes are the game's own bullet-hole materials (scripts/extract_assets.sh
## sounds fetches them with the impact sounds): concrete, plaster, metal and
## wood. Each .vmat names a colour, an occlusion and a normal texture and the
## hole's size in the world, and is read rather than copied into here. A hole
## is a Decal with the colour darkened by the occlusion, which is where the
## depth of the crater is, and the normal map, which is how the sun finds its
## rim; projected through a box deep enough to reach the drawn surface from
## the hull the round hit, which on a prop can be a few units out. There are
## only so many at once; the oldest goes when a new one is needed. The sounds
## are the game's impact sets by surface, from the hit.

const DECALS_ROOT := "res://assets/decals/materials/decals"
## The bullet-hole materials by the surface they are for, under DECALS_ROOT.
const HOLE_MATERIALS := {
	"concrete": ["concrete/concrete1", "concrete/concrete2", "concrete/concrete3", "concrete/concrete4", "concrete/concrete5"],
	"plaster": ["plaster/plaster1", "plaster/plaster2", "plaster/plaster3", "plaster/plaster4"],
	"metal": ["metal/metal1", "metal/metal2", "metal/metal3"],
	"wood": ["wood/wood1", "wood/wood2", "wood/wood3", "wood/wood4"],
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
## Which holes a surface gets: sand and dirt take plaster's, the map's
## mud-brick walls being the nearest thing to it; anything else concrete's.
const HOLE_FOR := {"concrete": "concrete", "sand": "plaster", "dirt": "plaster", "tile": "concrete", "metal": "metal", "wood": "wood"}

## How deep a hole's projection reaches, and where it starts relative to the
## surface (negative is in front of it), when the material does not say: the
## game's DecalDepth and DecalDepthOffset for its concrete and metal holes.
const DEFAULT_DEPTH := 12.0
const DEFAULT_DEPTH_OFFSET := -4.0
## A surface turned away from the hole by more than about 60 degrees takes
## none of it (the materials' g_flCutoffAngle), so the deep projection does
## not run down the side of a corner.
const NORMAL_FADE := 0.7
## The most texels a hole's textures keep across: a few inches wide needs no
## more, and the occlusion is folded into the colour texel by texel.
const MAX_TEXELS := 256

## Holes at once.
@export var max_holes: int = 96
## Godot's 3D audio is set out in metres; the map is in inches.
const METRE := 39.37
## Quiet, and quick to fade with distance: the hit is a tick under the
## shot, not a rock wall with every round.
const SOUND_DB := -20.0

var holes: int = 0
var _hole_nodes: Array[Decal] = []
var _next_hole: int = 0
var _variants := {}  # hole set -> Array of read_hole() results, with textures
var _players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"bullet_impacts")
	for i in 8:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 4.0 * METRE
		player.max_distance = 80.0 * METRE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_players.append(player)
	# The textures are made here, once, rather than on the first round into
	# each surface, which would hitch; and the sounds are loaded, for the
	# same reason.
	for hole_set in HOLE_MATERIALS:
		_variants_for(hole_set)
	SoundBank.load_sets(PackedStringArray(SOUND_SETS.values()))


## Reports a shot's result to the scene's impacts, if it has any.
static func mark_in(tree: SceneTree, result: Hitscan.Result) -> void:
	var impacts := tree.get_first_node_in_group(&"bullet_impacts") as BulletImpacts
	if impacts != null:
		impacts.mark(result)


## A hole and a sound where a round met the world, and a hole in and out
## of every wall it went through on the way. A round that met a person
## leaves nothing where it met them, and nor does one into the sky.
func mark(result: Hitscan.Result) -> void:
	for wall in result.walls:
		var went_in := surface_for(wall.surface)
		_sound(went_in, wall.entry)
		_hole(went_in, wall.entry, wall.entry_normal)
		_hole(surface_for(wall.exit_surface), wall.exit, wall.exit_normal)
	if not result.hit or result.hitbox != null or result.surface.contains("sky"):
		return
	var surface := surface_for(result.surface)
	_sound(surface, result.position)
	_hole(surface, result.position, result.normal)


## The impact surface for a hull part's name.
static func surface_for(hull_name: String) -> String:
	return BY_FOOTSTEP_SET.get(Footsteps.set_for(hull_name), "default")


## A bullet-hole material's description: its texture paths (res://, as the
## decompiled .png), its size in units, how widely that varies, and its
## projection's depth and offset. Empty when the file is not there.
static func read_hole(vmat_path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(vmat_path)
	if text.is_empty():
		return {}
	var hole := {
		"color": "", "occlusion": "", "normal": "", "width": 5.0, "height": 5.0,
		"variance": 0.5, "depth": DEFAULT_DEPTH, "offset": DEFAULT_DEPTH_OFFSET,
	}
	var textures := {"g_tColor": "color", "g_tAmbientOcclusion": "occlusion", "g_tNormal": "normal"}
	var numbers := {
		"DecalWorldWidth": "width", "DecalWorldHeight": "height", "DecalSizeVariance": "variance",
		"DecalDepth": "depth", "DecalDepthOffset": "offset",
	}
	var pair := RegEx.create_from_string("\"([A-Za-z_]+)\"\\s+\"([^\"]*)\"")
	for found in pair.search_all(text):
		var key := found.get_string(1)
		var value := found.get_string(2)
		if textures.has(key):
			# "materials/decals/concrete/x.vtex": the decompiled png beside it.
			hole[textures[key]] = DECALS_ROOT.get_base_dir().get_base_dir().path_join(value.get_basename() + ".png")
		elif numbers.has(key) and value.is_valid_float():
			hole[numbers[key]] = float(value)
	return hole


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
	var variants := _variants_for(HOLE_FOR.get(surface, "concrete"))
	if variants.is_empty():
		return
	var hole: Dictionary = variants[_rng.randi_range(0, variants.size() - 1)]
	var decal: Decal
	if _hole_nodes.size() < max_holes:
		decal = Decal.new()
		# Everything but the people (RigModel.LAYER).
		decal.cull_mask = 0xFFFFF & ~RigModel.LAYER
		decal.albedo_mix = 1.0
		# Full strength through the whole depth: the surface can be anywhere
		# in it.
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		decal.normal_fade = NORMAL_FADE
		add_child(decal)
		_hole_nodes.append(decal)
	else:
		decal = _hole_nodes[_next_hole]
		_next_hole = (_next_hole + 1) % _hole_nodes.size()
	decal.texture_albedo = hole["albedo_texture"]
	decal.texture_normal = hole["normal_texture"]
	# How the game spreads a hole's size by its variance is not in the file;
	# a quarter of it either way looks right.
	var scale_by := 1.0 + _rng.randf_range(-0.25, 0.25) * float(hole["variance"])
	var depth: float = hole["depth"]
	decal.size = Vector3(float(hole["width"]) * scale_by, depth, float(hole["height"]) * scale_by)
	# A decal projects down its own -Y; that is turned into the surface, the
	# box starting the material's offset in front of it, and the hole spun
	# about it so no two look alike.
	var up := normal.normalized()
	var centre := at - up * (float(hole["offset"]) + depth * 0.5)
	var spin := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
	decal.global_transform = Transform3D(_basis_facing(-up) * spin, centre)
	holes += 1


## The holes of a set, read and made once: the ones whose colour texture
## is there.
func _variants_for(hole_set: String) -> Array:
	if _variants.has(hole_set):
		return _variants[hole_set]
	var found := []
	for material in HOLE_MATERIALS.get(hole_set, []):
		var hole := read_hole(DECALS_ROOT.path_join(material + ".vmat"))
		if hole.is_empty() or not ResourceLoader.exists(hole["color"]):
			continue
		var color := (load(hole["color"]) as Texture2D).get_image()
		var occlusion: Image = null
		if ResourceLoader.exists(hole["occlusion"]):
			occlusion = (load(hole["occlusion"]) as Texture2D).get_image()
		hole["albedo_texture"] = ImageTexture.create_from_image(occluded(color, occlusion))
		hole["normal_texture"] = load(hole["normal"]) as Texture2D if ResourceLoader.exists(hole["normal"]) else null
		found.append(hole)
	_variants[hole_set] = found
	return found


## A hole's colour with its occlusion (the red channel) folded in, which is
## where the depth of the crater is: the decal has no occlusion of its own
## that reaches the map's baked light. At most MAX_TEXELS across, with mipmaps.
static func occluded(color: Image, occlusion: Image) -> Image:
	var out := _plain(color)
	if occlusion != null:
		var shade := _plain(occlusion)
		shade.resize(out.get_width(), out.get_height(), Image.INTERPOLATE_BILINEAR)
		var data := out.get_data()
		var ao := shade.get_data()
		for i in range(0, data.size(), 4):
			var a := ao[i] / 255.0
			data[i] = int(data[i] * a)
			data[i + 1] = int(data[i + 1] * a)
			data[i + 2] = int(data[i + 2] * a)
		out = Image.create_from_data(out.get_width(), out.get_height(), false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	return out


## An image as plain RGBA bytes without mipmaps, no more than MAX_TEXELS
## across.
static func _plain(image: Image) -> Image:
	var copy := image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGBA8)
	if copy.get_width() > MAX_TEXELS:
		copy.resize(MAX_TEXELS, maxi(1, roundi(float(copy.get_height()) * MAX_TEXELS / copy.get_width())), Image.INTERPOLATE_LANCZOS)
	return copy


## A basis whose -Y points along a direction.
static func _basis_facing(direction: Vector3) -> Basis:
	var down := direction.normalized()
	var up := -down
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 1e-6:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	return Basis(side, up, side.cross(up))
