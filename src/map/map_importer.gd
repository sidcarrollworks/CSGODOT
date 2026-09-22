class_name MapImporter
extends Node3D

## Turns a glTF exported from Source 2 Viewer into something you can walk
## around in.
##
## The export is a pile of meshes, textures and materials with no collision
## shapes and no nav mesh. This builds the collision and reports what it found:
## mesh counts, a bounding box, where the collision came from and every
## material name. Those answer the questions that are otherwise only settled by
## falling through a floor.
##
## What a Source 2 Viewer export looks like, as of version 20: metres, Y-up,
## one directional light for the sun, the vmat path and flags of every
## material kept as glTF extras, and the collision hull in a separate file
## (see collision_path).

signal import_finished(stats: Dictionary)

## Source 2 Viewer writes glTF in metres. The game is in Source units, which
## are inches. Exactly this, not 39.37: entity coordinates come from another
## file and have to land on the geometry.
const SOURCE2_VIEWER_SCALE := 1.0 / 0.0254

## Path to the exported glTF. Under res:// if the editor has imported it,
## otherwise it is loaded straight off disk.
@export_file("*.gltf", "*.glb") var source_path: String = ""

## Optional: a glTF of the map's collision hull, which Source 2 Viewer exports
## from world_physics.vmdl_c. When it is there, all of it is collision, none
## of it is drawn, and the visible world gets no collision at all. That is
## what the game itself does, and it is the only way to get player-clip
## brushes, which are in the hull and nowhere in the visible world.
@export_file("*.gltf", "*.glb") var collision_path: String = ""

## Optional: the directory scripts/extract_assets.sh put the map's materials/
## under, which is where the second layers of its blend materials are. With
## it, walls and ground that mix two textures do; without it they show their
## first layer only. See BlendMaterials.
@export_dir var layer_textures_dir: String = ""

## Optional: where the map's lightmaps are, relative to the world glTF's
## directory (the extraction puts them in lightmaps/ next to it). With them,
## world surfaces get the bounce light CS2 baked; without, Godot's sky
## ambient. See LightmapMaterials.
@export var lightmaps_dir: String = ""

## Draw everything of this map behind everything else, whatever the
## distance: for a 3D skybox scaled up into the world, whose terrain would
## otherwise show through the map's floors where they lie below it. See
## FarMaterials.
@export var behind_everything: bool = false
## Whether this map's surfaces cast shadows. The map itself does, and with
## both faces: its walls are one-sided and often have no face on their far
## side (a room's wall is the face that looks into the room), so a shadow
## pass that culls back faces sees nothing where the sun hits a wall's
## back, and the sun walks into the room. A 3D skybox does not: its hills
## are one-sided shells too, and cast double-sided they would throw the
## shadow of a far mountain over half the map; the game's skybox never
## casts onto the map at all.
@export var cast_shadows: bool = true

## What to multiply the export by. SOURCE2_VIEWER_SCALE for anything that came
## out of Source 2 Viewer; 1 for geometry already in Source units. If the
## reported bounding box is wrong by a constant factor, this is the knob.
@export var scale_factor: float = 1.0

## glTF is Y-up and Source is Z-up, and the exporter is supposed to convert.
## If the map arrives lying on its side, turn this on.
@export var rotate_z_up_to_y_up: bool = false

enum CollisionSource {
	## Use collision-marked meshes if there are any, otherwise every mesh.
	AUTO,
	## Only meshes whose material matches collision_material_hints.
	COLLISION_MESHES_ONLY,
	## Every mesh, collision-marked or not.
	ALL_MESHES,
	## Nothing: scenery that is never reached, such as a 3D skybox.
	NONE,
}

## Where collision comes from when there is no hull at collision_path.
@export var collision_source: CollisionSource = CollisionSource.AUTO

## Material name fragments that mark geometry as collision: solid but not
## drawn. These are a starting guess; the inventory printed on the first import
## is what tells you the real names.
@export var collision_material_hints: PackedStringArray = PackedStringArray([
	"collision", "clip", "nodraw", "invisible", "trigger",
])

## Material name fragments to drop entirely, drawn or not. Anything under
## materials/tools/ or materials/effects/, or drawn with the sky shader, goes
## the same way without needing a hint, when the export says so. Not
## "skybox": a 3D skybox's ground and far buildings are named that.
@export var skip_material_hints: PackedStringArray = PackedStringArray([
	"skydome", "blocklight",
])

## Material name fragments for geometry that is drawn but not solid. Matters
## only when collision has to come from the visible world: a road marking is a
## sheet floating a hair above the road, and standing on it is standing on a
## lip. Overlay and translucent materials are caught by their flags when the
## export carries them. Deliberately not "decal": dust2's crates are made of
## materials called *_decals.
@export var non_solid_material_hints: PackedStringArray = PackedStringArray([
	"overlay", "_decal_",
])

## Node name fragments in the collision hull to leave out. The hull is grouped
## by what each part interacts with, and grenade clips stop grenades, not
## players.
@export var hull_skip_hints: PackedStringArray = PackedStringArray([
	"grenadeclip",
])

## Print the inventory on import. Worth leaving on until the map is settled.
@export var report: bool = true

## Also write the inventory here. A file rather than only the Output panel,
## because the report is the thing you send to someone when an import is
## misbehaving, and a file survives a console window closing.
@export var report_path: String = "res://map-report.txt"

## Filled in by import(). Also delivered by the import_finished signal.
var stats: Dictionary = {}

var _loaded_from: String = ""

enum Kind { SOLID, NON_SOLID, COLLISION, SKIPPED }


## Finds the world glTF under a directory, at any depth, and returns it as a
## res:// path. Uses the real filesystem underneath because extracted content
## is gitignored and may not have been imported by the editor yet.
##
## Source 2 Viewer's output layout changes between releases, so the directory
## is searched rather than a path assumed. The export puts more than one glTF
## in it, though, and "whichever the filesystem lists first" is a different
## file on a different filesystem: world.gltf wins if there is one, and
## *_physics files are never the world.
static func find_map_file(res_dir: String) -> String:
	return _pick_gltf(res_dir, "world", "_physics")


## Finds the collision hull glTF under a directory. See collision_path.
static func find_collision_file(res_dir: String) -> String:
	return _pick_gltf(res_dir, "world_physics_physics", "")


static func _pick_gltf(res_dir: String, preferred: String, never: String) -> String:
	var candidates := PackedStringArray()
	_list_gltfs(res_dir, candidates)

	var fallback := ""
	for candidate in candidates:
		var basename := candidate.get_file().get_basename()
		if basename == preferred:
			return candidate
		if not never.is_empty() and basename.contains(never):
			continue
		if fallback.is_empty():
			fallback = candidate
	return fallback


## Depth first, each directory in sorted order, so the result does not depend
## on the filesystem.
static func _list_gltfs(res_dir: String, out: PackedStringArray) -> void:
	# Opened rather than listed with get_files_at, which logs an error for a
	# directory that is not there. Not there is the normal state of a fresh
	# clone.
	var dir := DirAccess.open(res_dir)
	if dir == null:
		return

	var files := dir.get_files()
	files.sort()
	for file in files:
		if file.ends_with(".gltf") or file.ends_with(".glb"):
			out.append(res_dir.path_join(file))

	var subdirectories := dir.get_directories()
	subdirectories.sort()
	for subdirectory in subdirectories:
		if not subdirectory.begins_with("."):
			_list_gltfs(res_dir.path_join(subdirectory), out)


func _ready() -> void:
	if source_path.is_empty():
		return
	import_map()


## Loads the glTF, builds collision, and returns the stats dictionary. Safe to
## call again; the previously imported geometry is discarded first.
func import_map() -> Dictionary:
	for child in get_children():
		# Out of the tree now, not at the end of the frame: what replaces them
		# wants their names, and the physics space should not hold both.
		remove_child(child)
		child.queue_free()

	var scene := _load_scene(source_path)
	if scene == null:
		stats = {"error": "could not load %s" % source_path}
		_report_missing()
		import_finished.emit(stats)
		return stats
	var loaded_from := _loaded_from

	add_child(scene)
	scene.scale = Vector3.ONE * scale_factor
	if rotate_z_up_to_y_up:
		scene.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	var sun := _take_lights(scene)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(scene, meshes)

	var materials := {}
	var collision_meshes: Array[MeshInstance3D] = []
	var visible_meshes: Array[MeshInstance3D] = []
	var solid_meshes: Array[MeshInstance3D] = []
	var skipped := 0

	for mesh_instance in meshes:
		for material_name in _material_names(mesh_instance):
			materials[material_name] = int(materials.get(material_name, 0)) + 1

		match _classify(mesh_instance):
			Kind.SKIPPED:
				mesh_instance.visible = false
				skipped += 1
			Kind.COLLISION:
				collision_meshes.append(mesh_instance)
				# Collision geometry is not meant to be seen.
				mesh_instance.visible = false
			Kind.NON_SOLID:
				visible_meshes.append(mesh_instance)
			_:
				visible_meshes.append(mesh_instance)
				solid_meshes.append(mesh_instance)
	for mesh_instance in visible_meshes:
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if cast_shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)

	var blend := BlendMaterials.apply(visible_meshes, layer_textures_dir)
	var lightmaps := {"surfaces": 0, "props": 0, "found": false, "ambient": null}
	var probes := {"volumes": 0, "surfaces": 0}
	if not lightmaps_dir.is_empty():
		var map_dir := source_path.get_base_dir().path_join(lightmaps_dir)
		lightmaps = LightmapMaterials.apply(visible_meshes, map_dir, scale_factor)
		# What the lightmaps did not cover, the light probes light: the props
		# placed to be lit by them, once, where they stand; and, through the
		# field left in the scene, whatever moves.
		var field_probes := LightProbes.load_for(map_dir)
		if field_probes.is_loaded():
			var field := LightProbeField.new()
			field.name = "LightProbes"
			field.probes = field_probes
			add_child(field)
			probes["volumes"] = field_probes.volumes.size()
			probes["surfaces"] = ProbeMaterials.apply(visible_meshes, field_probes, LightmapMaterials.PROP_SHADERS)

	var behind := FarMaterials.apply(visible_meshes) if behind_everything else 0

	var collision_from := "the collision hull"
	var targets: Array[MeshInstance3D] = []
	if collision_source == CollisionSource.NONE:
		collision_from = "nowhere, by request"
	else:
		targets = _hull_meshes()
	if targets.is_empty() and collision_source != CollisionSource.NONE:
		targets = _collision_targets(collision_meshes, solid_meshes)
		collision_from = "the visible world"
		if not collision_meshes.is_empty() and collision_source != CollisionSource.ALL_MESHES:
			collision_from = "collision-marked meshes"
	var triangles := _build_collision(targets)

	stats = {
		"meshes": meshes.size(),
		"collision_marked": collision_meshes.size(),
		"visible": visible_meshes.size(),
		"skipped": skipped,
		"collision_bodies": targets.size(),
		"collision_triangles": triangles,
		"collision_from": collision_from,
		"loaded_from": loaded_from,
		"blend": blend,
		"lightmaps": lightmaps,
		"behind": behind,
		"probes": probes,
		"materials": materials,
		"bounds": _bounds(meshes),
	}
	if not sun.is_empty():
		stats["sun"] = sun

	if report:
		_print_report()
	import_finished.emit(stats)
	return stats


## Which meshes get collision when there is no hull, given what the map
## actually contained.
func _collision_targets(
	collision_meshes: Array[MeshInstance3D],
	solid_meshes: Array[MeshInstance3D]
) -> Array[MeshInstance3D]:
	match collision_source:
		CollisionSource.COLLISION_MESHES_ONLY:
			return collision_meshes
		CollisionSource.ALL_MESHES:
			return collision_meshes + solid_meshes
		_:
			# Auto. A map that ships real collision geometry should use it and
			# nothing else, because visual geometry is not a collision hull.
			# A map that does not has to fall back on what it has.
			if not collision_meshes.is_empty():
				return collision_meshes
			return solid_meshes


## Loads collision_path, hidden, and returns the parts of it a player collides
## with. Empty if there is no hull, which sends collision back to the world.
func _hull_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if collision_path.is_empty():
		return meshes
	var hull := _load_scene(collision_path)
	if hull == null:
		push_warning(
			"No collision hull at %s; colliding with the visible world instead."
			% collision_path
		)
		return meshes

	hull.name = "CollisionHull"
	add_child(hull)
	hull.scale = Vector3.ONE * scale_factor
	if rotate_z_up_to_y_up:
		hull.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	hull.visible = false

	var all_meshes: Array[MeshInstance3D] = []
	_collect_meshes(hull, all_meshes)
	for mesh_instance in all_meshes:
		if not _matches_any(PackedStringArray([mesh_instance.name]), hull_skip_hints):
			meshes.append(mesh_instance)
	return meshes


## The export's lights come in at their physical intensity, which for dust2's
## sun is 1700 times what a Godot scene expects, so they cannot stay. The sun's
## direction and colour are worth having though, and are returned for whoever
## lights the scene: {"basis": Basis, "color": Color}, or empty if no sun.
func _take_lights(scene: Node) -> Dictionary:
	var sun := {}
	# owned = false: nothing in a generated scene has an owner.
	for node in scene.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light is DirectionalLight3D and sun.is_empty():
			sun = {
				"basis": light.global_transform.basis.orthonormalized(),
				"color": light.light_color,
			}
		light.get_parent().remove_child(light)
		light.free()
	return sun


func _load_scene(path: String) -> Node3D:
	# Fast path: the editor has already imported it, so use the native scene.
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			_loaded_from = "Godot's import"
			return packed.instantiate() as Node3D

	# Otherwise read the file directly, which works the moment extraction
	# finishes without waiting for an editor import pass.
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(absolute, state)
	if error != OK:
		push_error("glTF load failed for %s (error %d)" % [path, error])
		return null
	_loaded_from = "the glTF file, parsed just now"
	return document.generate_scene(state) as Node3D


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _material_names(mesh_instance: MeshInstance3D) -> PackedStringArray:
	var names := PackedStringArray()
	var mesh := mesh_instance.mesh
	for surface in mesh.get_surface_count():
		# The surface name first: it is the glTF material name on both load
		# paths, where Godot's import renames some of the materials themselves.
		var surface_name := ""
		if mesh is ArrayMesh:
			surface_name = (mesh as ArrayMesh).surface_get_name(surface)
		var material := mesh_instance.get_active_material(surface)
		if surface_name.is_empty() and material != null:
			surface_name = material.resource_name
			if surface_name.is_empty():
				surface_name = material.resource_path.get_file()
		if not surface_name.is_empty():
			names.append(surface_name)
	if names.is_empty():
		names.append(mesh_instance.name)
	return names


func _classify(mesh_instance: MeshInstance3D) -> Kind:
	var names := _material_names(mesh_instance)
	if _matches_any(names, skip_material_hints):
		return Kind.SKIPPED
	if _matches_any(names, collision_material_hints):
		return Kind.COLLISION

	# Names only go so far. Source 2 Viewer also records where each material
	# came from and its shader flags, which say the same thing reliably.
	var surfaces := mesh_instance.mesh.get_surface_count()
	var non_solid_surfaces := 0
	for surface in surfaces:
		var vmat := _vmat(mesh_instance.get_active_material(surface))
		var vmat_path: String = vmat.get("Name", "")
		if vmat_path.begins_with("materials/tools/") or vmat_path.begins_with("materials/effects/"):
			return Kind.SKIPPED
		# A sky dome would hide the real sky.
		if String(vmat.get("ShaderName", "")).begins_with("sky"):
			return Kind.SKIPPED
		var flags: Dictionary = vmat.get("IntParams", {})
		# The flags arrive as floats.
		if int(flags.get("F_OVERLAY", 0)) == 1 or int(flags.get("F_TRANSLUCENT", 0)) == 1:
			non_solid_surfaces += 1

	if surfaces > 0 and non_solid_surfaces == surfaces:
		return Kind.NON_SOLID
	if _matches_any(names, non_solid_material_hints):
		return Kind.NON_SOLID
	return Kind.SOLID


## The vmat description Source 2 Viewer attaches to a material, or empty.
func _vmat(material: Material) -> Dictionary:
	if material == null:
		return {}
	var extras: Variant = material.get_meta("extras", {})
	if not extras is Dictionary:
		return {}
	var vmat: Variant = (extras as Dictionary).get("vmat", {})
	if not vmat is Dictionary:
		return {}
	return vmat


func _matches_any(names: PackedStringArray, hints: PackedStringArray) -> bool:
	for candidate in names:
		var lowered := candidate.to_lower()
		for hint in hints:
			if lowered.contains(hint.to_lower()):
				return true
	return false


## Builds one static body holding a trimesh per mesh, and returns the triangle
## count. Trimesh is right here: map geometry is static and concave, and a
## convex decomposition of dust2 would both take forever and round off exactly
## the corners that movement is judged on.
##
## Each mesh's transform is baked into its triangles, so the body and its
## shapes sit unscaled at the origin whatever scale_factor is. A scaled
## physics body is something Godot only tolerates, and collision is the last
## place to find out how far.
func _build_collision(targets: Array[MeshInstance3D]) -> int:
	if targets.is_empty():
		return 0

	var body := StaticBody3D.new()
	body.name = "Collision"
	add_child(body)
	var to_body := body.global_transform.affine_inverse()

	var triangles := 0
	for mesh_instance in targets:
		var faces := (to_body * mesh_instance.global_transform) * mesh_instance.mesh.get_faces()
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)

		var collision := CollisionShape3D.new()
		# In a hull this is the surface type (physics_group_concrete, _wood,
		# _sand...), which is what footsteps and penetration will want.
		collision.name = mesh_instance.name
		collision.shape = shape
		body.add_child(collision)
		@warning_ignore("integer_division")
		triangles += faces.size() / 3
	return triangles


## In world space, so scale_factor is already in there by way of the scene's
## transform.
func _bounds(meshes: Array[MeshInstance3D]) -> AABB:
	var result := AABB()
	var first := true
	for mesh_instance in meshes:
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _print_report() -> void:
	var text := _report_text()
	print(text)
	write_report(text)


## Writes arbitrary text to report_path. Public so the map scene can record
## the "not extracted yet" case the same way, which is the state someone is
## most likely to be asking about.
func write_report(text: String) -> void:
	if report_path.is_empty():
		return
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write %s" % report_path)
		return
	file.store_string(text)
	file.close()
	print("(also written to %s)" % report_path)


func _report_text() -> String:
	var bounds: AABB = stats["bounds"]
	var lines: Array[String] = [
		"--- map import: %s" % source_path,
		"    loaded from %s" % stats["loaded_from"],
		"    meshes %d (collision-marked %d, visible %d, skipped %d)" % [
			stats["meshes"], stats["collision_marked"],
			stats["visible"], stats["skipped"],
		],
		"    collision: %d shapes, %d triangles, from %s" % [
			stats["collision_bodies"], stats["collision_triangles"],
			stats["collision_from"],
		],
		"    bounds: %.0f x %.0f x %.0f units, centred near (%.0f, %.0f, %.0f)" % [
			bounds.size.x, bounds.size.y, bounds.size.z,
			bounds.get_center().x, bounds.get_center().y, bounds.get_center().z,
		],
		"    (dust2 should be about 7000 units across. If it is 180, the export",
		"     is still in metres: set scale_factor to SOURCE2_VIEWER_SCALE.)",
	]
	var blend: Dictionary = stats["blend"]
	lines.append("    blend materials: %d, on %d surfaces" % [blend["materials"], blend["blended"]])
	var lightmaps: Dictionary = stats["lightmaps"]
	if lightmaps["found"]:
		lines.append("    baked bounce light on %d surfaces, %d of them props" % [lightmaps["surfaces"], lightmaps["props"]])
		var probes: Dictionary = stats["probes"]
		if probes["volumes"] > 0:
			lines.append("    light probes: %d volumes, lighting %d more prop surfaces" % [probes["volumes"], probes["surfaces"]])
		else:
			lines.append("    no light probes found; run 'scripts/extract_assets.sh lightmaps' for them")
		if lightmaps["ambient"] == null:
			lines.append("    the lightmap's average is not measured yet (scripts/prepare_export.gd); the rest get the sky's light")
	elif not lightmaps_dir.is_empty():
		lines.append("    no lightmaps found; run 'scripts/extract_assets.sh lightmaps' for the bounce light")
	if not (blend["missing"] as PackedStringArray).is_empty():
		lines.append(
			"    %d more are showing their first layer only, their second not being on disk."
			% (blend["missing"] as PackedStringArray).size()
		)
		lines.append("    Run 'scripts/extract_assets.sh layers' to fetch them.")
	if stats.has("sun"):
		var towards_sun: Vector3 = (stats["sun"]["basis"] as Basis).z
		lines.append(
			"    sun: %.0f degrees above the horizon"
			% rad_to_deg(asin(clampf(towards_sun.y, -1.0, 1.0)))
		)

	var materials: Dictionary = stats["materials"]
	var names := materials.keys()
	names.sort()
	lines.append("    %d distinct materials:" % names.size())
	for material_name in names:
		lines.append("      %s (%d surfaces)" % [material_name, materials[material_name]])

	return "\n".join(lines)


func _report_missing() -> void:
	push_warning(
		"Map not imported: %s is missing or would not load. "
		% source_path
		+ "Run scripts/extract_assets.sh map on a machine with CS2 installed."
	)
