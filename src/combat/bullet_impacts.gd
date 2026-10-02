class_name BulletImpacts
extends Node3D

## Where the rounds land: a bullet hole on the surface and the sound of
## it, both by what the surface is. One of these in a scene, in the
## "bullet_impacts" group, and every shooter reports its hits to it
## (mark); a scene without one has silent, markless walls, as before.
##
## The installed surface/decal/material tables select weighted materials,
## including separate grazing marks. Each names colour, occlusion and normal
## textures and the hole's size and projection in the world. A hole
## is a Decal with the colour darkened by the occlusion, which is where the
## depth of the crater is, and the normal map, which is how the sun finds its
## rim; projected through a box deep enough to reach the drawn surface from
## the hull the round hit, which on a prop can be a few units out. There are
## only so many at once; the oldest goes when a new one is needed. The sounds
## are the game's impact sets by surface, from the hit. A trace queues plain
## contact data; decals, sounds and HitEffects particles start on a drawn
## frame. Nothing here queries physics or reads files during a tick.

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
## Current shipped convars. The use of the incidence cosine, uniform
## cutoff jitter, size variance and linear distance ramp are approximations
## until measured in CS2; the weights and material dimensions are authored.
const GRAZING_CUTOFF := 0.55
const GRAZING_VARIANCE := 0.1
const DISTANCE_START := 256.0
const DISTANCE_END := 1536.0
const DISTANCE_SCALE := 1.35
const DEFAULT_FADE_START := 30.0
const DEFAULT_FADE_DURATION := 3.0
const MAX_PENDING := 512

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
var _pending: Array[Dictionary] = []
var _groups := {}  # decal group -> weighted prepared materials
var _materials := {}  # authored path -> prepared material, or {}
var _hole_states: Array[Dictionary] = []
var _now := 0.0


func _ready() -> void:
	add_to_group(&"bullet_impacts")
	SurfaceProperties.rows()
	for i in 8:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 4.0 * METRE
		player.max_distance = 80.0 * METRE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# Where a flash's muffle reaches it (FlashMuffle).
		player.bus = FlashMuffle.unmixed_bus()
		add_child(player)
		_players.append(player)
	# The textures are made here, once, rather than on the first round into
	# each surface, which would hitch; and the sounds are loaded, for the
	# same reason.
	for group: String in HitEffectTable.DECAL_GROUPS:
		if group.begins_with("Impact."):
			_group_variants(group)
	for hole_set in HOLE_MATERIALS:
		_variants_for(hole_set)
	SoundBank.load_sets(PackedStringArray(SOUND_SETS.values()))


## Reports a shot's result to the scene's impacts, if it has any.
static func mark_in(tree: SceneTree, result: Hitscan.Result, direction := Vector3.ZERO, at_usec: int = 0) -> void:
	var impacts := tree.get_first_node_in_group(&"bullet_impacts") as BulletImpacts
	if impacts != null:
		impacts.mark(result, direction, at_usec)


## A hole and a sound where a round met the world, and a hole in and out
## of every wall it went through on the way. A round that met a person
## leaves nothing where it met them, and nor does one into the sky.
func mark(result: Hitscan.Result, direction := Vector3.ZERO, at_usec: int = 0) -> void:
	for wall in result.walls:
		_queue_contact(wall.surface, wall.entry, wall.entry_normal, direction, at_usec, true)
		_queue_contact(wall.exit_surface, wall.exit, wall.exit_normal, direction, at_usec, false)
	if not result.hit or result.hitbox != null or result.surface.contains("sky"):
		return
	_queue_contact(result.surface, result.position, result.normal, direction, at_usec, true)


func _queue_contact(surface: String, at: Vector3, normal: Vector3, direction: Vector3, at_usec: int, sound: bool) -> void:
	if surface.to_lower().contains("sky"):
		return
	if _pending.size() >= MAX_PENDING:
		return
	_pending.append({"surface": surface, "at": at, "normal": normal, "direction": direction, "at_usec": at_usec, "sound": sound})


func _process(delta: float) -> void:
	_now += delta
	for i in _hole_states.size():
		var state: Dictionary = _hole_states[i]
		var decal := _hole_nodes[i]
		if not decal.visible:
			continue
		var alpha := fade_at(_now - float(state["born"]), float(state["fade_start"]), float(state["fade_duration"]))
		var tint: Color = state["tint"]
		tint.a *= alpha
		decal.modulate = tint
		if alpha <= 0.0:
			decal.hide()
	if _pending.is_empty():
		return
	var effects := get_tree().get_first_node_in_group(&"hit_effects")
	var camera := get_viewport().get_camera_3d()
	for contact: Dictionary in _pending:
		var sound_surface := surface_for(contact["surface"])
		if contact["sound"]:
			_sound(sound_surface, contact["at"])
		var distance := camera.global_position.distance_to(contact["at"]) if camera != null else 0.0
		_hole(contact["surface"], contact["at"], contact["normal"], contact["direction"], distance)
		if effects != null and effects.has_method(&"queue_world"):
			effects.call(&"queue_world", surface_name(contact["surface"]), contact["at"], contact["normal"], contact["direction"], contact["at_usec"])
	_pending.clear()


static func surface_name(hull_name: String) -> String:
	return hull_name.to_lower().trim_prefix("physics_group_").trim_prefix("physics_")


## Resolve each authored field separately; an explicit empty decal keeps
## a wet/no_decal surface unmarked rather than inheriting concrete.
static func impact_for(hull_name: String) -> Dictionary:
	var at := surface_name(hull_name)
	var result := {}
	for i in SurfaceProperties.MOST_PARENTS:
		var own: Dictionary = HitEffectTable.SURFACES.get(at, {})
		for field: String in own:
			if not result.has(field):
				result[field] = own[field]
		if at == SurfaceProperties.ROOT:
			break
		var parent := SurfaceProperties.parent(at)
		at = parent if not parent.is_empty() else SurfaceProperties.ROOT
	return result


static func is_grazing(direction: Vector3, normal: Vector3, cutoff: float = GRAZING_CUTOFF) -> bool:
	if direction.length_squared() < 1e-8 or normal.length_squared() < 1e-8:
		return false
	return absf(direction.normalized().dot(normal.normalized())) < cutoff


static func decal_group(fields: Dictionary, grazing: bool) -> String:
	return String(fields.get("grazing", fields.get("decal", ""))) if grazing else String(fields.get("decal", ""))


static func distance_scale(distance: float) -> float:
	return lerpf(1.0, DISTANCE_SCALE, clampf((distance - DISTANCE_START) / (DISTANCE_END - DISTANCE_START), 0.0, 1.0))


static func fade_at(age: float, start: float = DEFAULT_FADE_START, duration: float = DEFAULT_FADE_DURATION) -> float:
	if age <= start or start < 0.0:
		return 1.0
	return clampf(1.0 - (age - start) / duration, 0.0, 1.0) if duration > 0.0 else 0.0


## One authored weighted choice, useful without extracted assets too.
static func pick_material(group: String, share: float) -> String:
	var options: Array = HitEffectTable.DECAL_GROUPS.get(group, [])
	var total := 0.0
	for option: Dictionary in options:
		total += maxf(float(option["weight"]), 0.0)
	var remaining := clampf(share, 0.0, 0.999999) * total
	for option: Dictionary in options:
		remaining -= maxf(float(option["weight"]), 0.0)
		if remaining < 0.0:
			return option["material"]
	return ""


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


func _hole(surface: String, at: Vector3, normal: Vector3, direction := Vector3.ZERO, distance: float = 0.0) -> void:
	if max_holes <= 0 or normal.length_squared() < 1e-8:
		return
	var fields := impact_for(surface)
	var grazing := is_grazing(direction, normal, GRAZING_CUTOFF + _rng.randf_range(-GRAZING_VARIANCE, GRAZING_VARIANCE))
	var group := decal_group(fields, grazing)
	if group.is_empty():
		return
	var variants := _group_variants(group)
	var hole := {}
	if not variants.is_empty():
		var weights := PackedFloat32Array()
		for variant: Dictionary in variants:
			weights.append(variant["weight"])
		hole = variants[_rng.rand_weighted(weights)]
	else:
		# Existing extractions still supply the original four families.
		var fallback := _variants_for(HOLE_FOR.get(surface_for(surface), "concrete"))
		if fallback.is_empty():
			return
		hole = fallback[_rng.randi_range(0, fallback.size() - 1)]
	var decal: Decal
	var slot := -1
	for i in _hole_nodes.size():
		if not _hole_nodes[i].visible:
			slot = i
			break
	if slot >= 0:
		decal = _hole_nodes[slot]
	elif _hole_nodes.size() < max_holes:
		decal = Decal.new()
		# Everything but the people (RigModel.LAYER).
		decal.cull_mask = 0xFFFFF & ~RigModel.LAYER
		decal.albedo_mix = 1.0
		# Full strength through the whole depth: the surface can be anywhere
		# in it.
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		add_child(decal)
		slot = _hole_nodes.size()
		_hole_nodes.append(decal)
		_hole_states.append({})
	else:
		slot = _next_hole
		decal = _hole_nodes[slot]
		_next_hole = (_next_hole + 1) % _hole_nodes.size()
	decal.texture_albedo = hole["albedo_texture"]
	decal.texture_normal = hole["normal_texture"]
	decal.texture_orm = hole.get("orm_texture")
	decal.normal_fade = float(hole.get("normal_fade", NORMAL_FADE))
	var size := placement_size(hole, Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)), distance)
	decal.size = size
	# A decal projects down its own -Y; that is turned into the surface, the
	# box starting the material's offset in front of it, and the hole spun
	# about it so no two look alike.
	var up := normal.normalized()
	var centre := at - up * (float(hole["offset"]) + size.y * 0.5)
	var spin := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
	var tangent := direction - up * direction.dot(up)
	var basis := _basis_facing(-up) * spin
	if grazing and tangent.length_squared() >= 1e-8:
		# Grazing textures are scratches; their long axis follows the bullet.
		tangent = tangent.normalized()
		basis = Basis(up.cross(tangent), up, tangent)
	decal.global_transform = Transform3D(basis, centre)
	var tint: Color = hole.get("tint", Color.WHITE)
	decal.modulate = tint
	decal.set_meta(&"material", hole.get("material", ""))
	decal.show()
	_hole_states[slot] = {"born": _now, "fade_start": hole.get("fade_start", DEFAULT_FADE_START), "fade_duration": hole.get("fade_duration", DEFAULT_FADE_DURATION), "tint": tint}
	holes += 1


## Authored base dimensions; additive uniform variance is a documented
## approximation of Source 2's variance controls. Legacy fallback retains
## its former size spread. Distance enlargement is applied at placement.
static func placement_size(hole: Dictionary, variation: Vector3, distance: float) -> Vector3:
	var width := float(hole["width"])
	var height := float(hole["height"])
	var depth := float(hole["depth"])
	if bool(hole.get("authored", false)):
		var shared := variation.x * float(hole["variance"])
		width += shared
		height += shared + variation.z * float(hole.get("height_variance", 0.0))
		depth += variation.y * float(hole.get("depth_variance", 0.0))
	else:
		var scale_by := 1.0 + variation.x * 0.25 * float(hole["variance"])
		width *= scale_by
		height *= scale_by
	var boost := distance_scale(distance)
	return Vector3(maxf(width, 0.01) * boost, maxf(depth, 0.01), maxf(height, 0.01) * boost)


static func material_description(path: String) -> Dictionary:
	var material: Dictionary = HitEffectTable.MATERIALS.get(path, {})
	if material.is_empty():
		return {}
	var params: Dictionary = material.get("params", {})
	var textures: Dictionary = material.get("textures", {})
	var tint := Color.WHITE
	var color: Variant = params.get("g_vColorTint")
	if color is Array and color.size() >= 3:
		tint = Color(float(color[0]), float(color[1]), float(color[2]), float(color[3]) if color.size() > 3 else 1.0)
	return {
		"material": path, "authored": true,
		"color": textures.get("g_tColor", ""), "occlusion": textures.get("g_tAmbientOcclusion", ""), "normal": textures.get("g_tNormal", ""),
		"width": params.get("DecalWorldWidth", 5.0), "height": params.get("DecalWorldHeight", 5.0),
		"variance": params.get("DecalSizeVariance", 0.0), "height_variance": params.get("DecalHeightVariance", 0.0), "depth_variance": params.get("DecalDepthVariance", 0.0),
		"depth": params.get("DecalDepth", DEFAULT_DEPTH), "offset": params.get("DecalDepthOffset", DEFAULT_DEPTH_OFFSET),
		"fade_start": params.get("DecalFadeStartTime", DEFAULT_FADE_START), "fade_duration": params.get("DecalFadeDuration", DEFAULT_FADE_DURATION),
		# Godot's one scalar cannot reproduce Source 2's cutoff/softness pair;
		# the cosine gives a conservative approximation rather than disabling it.
		"normal_fade": cos(deg_to_rad(float(params.get("g_flCutoffAngle", 60.0)))) if float(params.get("F_CUTOFF_ANGLE", 1.0)) != 0.0 else 0.0,
		"cutoff_angle": params.get("g_flCutoffAngle", 60.0), "cutoff_softness": params.get("g_flCutoffAngleSoftness", 5.0), "tint": tint,
	}


func _group_variants(group: String) -> Array:
	if _groups.has(group):
		return _groups[group]
	var result := []
	for option: Dictionary in HitEffectTable.DECAL_GROUPS.get(group, []):
		var hole := _material_for(option["material"])
		if hole.is_empty() or float(option["weight"]) <= 0.0:
			continue
		var variant := hole.duplicate()
		variant["weight"] = float(option["weight"])
		result.append(variant)
	_groups[group] = result
	return result


func _material_for(path: String) -> Dictionary:
	if _materials.has(path):
		return _materials[path]
	var hole := material_description(path)
	if hole.is_empty():
		_materials[path] = {}
		return {}
	var color := _authored_texture(hole["color"])
	if color == null:
		_materials[path] = {}
		return {}
	var ao := _authored_texture(hole["occlusion"])
	var normal := _authored_texture(hole["normal"])
	hole["albedo_texture"] = ImageTexture.create_from_image(occluded(color.get_image(), ao.get_image() if ao != null else null))
	if normal != null:
		var image := _plain(normal.get_image())
		image.generate_mipmaps()
		hole["normal_texture"] = ImageTexture.create_from_image(image)
	else:
		hole["normal_texture"] = null
	_materials[path] = hole
	return hole


static func _authored_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	for root in [SpriteSheet.DIR, DECALS_ROOT.get_base_dir().get_base_dir()]:
		var png: String = root.path_join(path.get_basename() + ".png")
		if ResourceLoader.exists(png):
			return load(png) as Texture2D
	return null


## The holes of a set, read and made once: the ones whose colour texture
## is there.
func _variants_for(hole_set: String) -> Array:
	if _variants.has(hole_set):
		return _variants[hole_set]
	var authored: Array = _groups.get("Impact." + hole_set.capitalize(), [])
	if not authored.is_empty():
		_variants[hole_set] = authored
		return authored
	var found := []
	for material in HOLE_MATERIALS.get(hole_set, []):
		var path := DECALS_ROOT.path_join(material + ".vmat")
		if not FileAccess.file_exists(path):
			continue
		var hole := read_hole(path)
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
	var longest := maxi(copy.get_width(), copy.get_height())
	if longest > MAX_TEXELS:
		var ratio := float(MAX_TEXELS) / longest
		copy.resize(maxi(1, roundi(copy.get_width() * ratio)), maxi(1, roundi(copy.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
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
