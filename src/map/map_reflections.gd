class_name MapReflections
extends Node3D

## Reflections where CS2 has them: a ReflectionProbe at each of the map's
## cubemaps, drawn once as the map starts.
##
## CS2 bakes a cubemap into each env_combined_light_probe_volume (dust2 has
## 43 and no other kind, reference/rendering.md, L4), each env_cubemap_box
## and each env_cubemap. A surface reflects the ones whose boxes hold it,
## each projected onto its box, so that a wall's reflection lands where the
## wall is, and faded out over the box's edge_fade_dists, the more indoor
## one first, until their weights add up to one. That is Source 2 Viewer's
## reading (environment.slang, SceneEnvMap). Godot's probe does the same at
## every pixel: box projection, a blend distance, several probes over one
## another. It has one blend distance where CS2 has one an axis, so the
## largest is taken; and it ranks probes that overlap by size, the smaller
## first, where CS2 goes by indoor_outdoor_level. Nested volumes are small
## rooms in large ones, which comes to the same, except that Godot sorts
## the probes in view in words of 32 and runs the word of the 32 largest
## first: with more than 32 in view, a small one inside a large one can
## lose to it (Godot 4.7.2's LightStorage::update_reflection_probe_buffer
## and the reflection loop in scene_forward_clustered.glsl).
##
## What each shows is Godot's own picture, not CS2's: the probe renders the
## map as it is drawn here, from where CS2 captured its cubemap (the
## entity's origin). The map's own cubemaps (cubemaps/env_cubemap_array in
## its VPK) are not extracted; they would replace these pictures, and bring
## CS2's way of dimming a cubemap by the baked light at each pixel with
## them. The players are left out of a probe's picture, which would keep
## them there, where they stood at the start, for the rest of the map.
##
## Godot draws a probe only once a camera has it in view, one probe at a
## time: a frame for its six faces, then one for each of its rough levels
## (RendererSceneCull::render_probes). So as the map starts a camera of its
## own looks down over all of them for one frame, which puts them all in
## line, and the map's visibility (WorldVisibility) is held, drawing
## everything, until the last is done: from where the player stands it
## hides most of the map, which a probe elsewhere would be drawn without.
## Until its probe is done, a surface reflects the sky.

## The cubemap entities, as Source 2 Viewer's EntityFactory spawns them.
const CLASSES := ["env_combined_light_probe_volume", "env_cubemap_box", "env_cubemap"]
const ENTITIES_FILE := "entities/default_ents.vents"
## The render layer the probes are on, and nothing else (editor layer 12):
## the camera that puts them in line looks at it alone, so it draws nothing.
const LAYER := 1 << 11
## What a probe's picture takes in: everything but the players' models,
## their weapons and arms, and your own body.
const DRAWS := 0xFFFFF & ~(RigModel.LAYER | PlayerSim.UNSEEN_LAYER)
## How far a probe draws, in units: past the far side of any map. Godot
## draws at least to its box's faces, which would cut an outdoor probe's
## picture off at its own edge; it is drawn once, so the distance is cheap.
const DRAW_DISTANCE := 16384.0

var probes: Array[ReflectionProbe] = []
## The map's visibility, held while the probes are drawn; may be null.
var visibility: WorldVisibility

var _capture: SubViewport
var _started := -1


## The cubemaps in an entity lump, each as {"origin", "angles", "mins",
## "maxs" (Source axes and units, the box about the origin), "box" (whether
## it projects onto its box), "fade" (how far in from each face it fades
## out), "level" (indoor_outdoor_level)}. An env_cubemap is a sphere of its
## influenceradius, taken as the box round it, unprojected as CS2 has it.
## One whose customcubemaptexture names a texture of its own is left out,
## as Source 2 Viewer leaves it, and so is one with no box.
static func read(entities: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entity in entities:
		var classname := String(entity.get("classname", ""))
		if not classname in CLASSES or not String(entity.get("customcubemaptexture", "")).is_empty():
			continue
		var cubemap := {
			"origin": SourceEntities.vector(String(entity.get("origin", "[ 0 0 0 ]"))),
			"angles": SourceEntities.vector(String(entity.get("angles", "[ 0 0 0 ]"))),
			"box": classname != "env_cubemap",
			"fade": SourceEntities.vector(String(entity.get("edge_fade_dists", "[ 0 0 0 ]"))),
			"level": int(entity.get("indoor_outdoor_level", "0")),
		}
		if classname == "env_cubemap":
			var radius := float(entity.get("influenceradius", "0"))
			cubemap["mins"] = -Vector3.ONE * radius
			cubemap["maxs"] = Vector3.ONE * radius
		else:
			cubemap["mins"] = SourceEntities.vector(String(entity.get("box_mins", "[ 0 0 0 ]")))
			cubemap["maxs"] = SourceEntities.vector(String(entity.get("box_maxs", "[ 0 0 0 ]")))
		var size: Vector3 = cubemap["maxs"] - cubemap["mins"]
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			continue
		out.append(cubemap)
	return out


## A probe for one cubemap (read), placed in game space: its box where the
## entity's is, and its picture taken from the entity's origin.
static func probe_for(cubemap: Dictionary) -> ReflectionProbe:
	var turn := BrushVolume.source_basis(cubemap["angles"])
	var mins: Vector3 = cubemap["mins"]
	var maxs: Vector3 = cubemap["maxs"]
	var centre := (mins + maxs) * 0.5
	var fade: Vector3 = cubemap["fade"]
	var probe := ReflectionProbe.new()
	probe.position = SourceEntities.to_game(cubemap["origin"] + turn * centre)
	# Source's X is the game's Z, its Y the game's X, its Z the game's Y.
	probe.basis = Basis(SourceEntities.to_game(turn.y), SourceEntities.to_game(turn.z), SourceEntities.to_game(turn.x))
	# The size first: Godot keeps the origin offset inside the box it has.
	probe.size = SourceEntities.to_game(maxs - mins)
	probe.origin_offset = SourceEntities.to_game(-centre)
	probe.box_projection = cubemap["box"]
	probe.blend_distance = maxf(fade.x, maxf(fade.y, fade.z))
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.max_distance = DRAW_DISTANCE
	probe.cull_mask = DRAWS
	# The map's bounce light is the ambient already (baked_light.gdshaderinc),
	# and a probe's own would take its place.
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.layers = LAYER
	return probe


## A probe for each of the map's cubemaps under a new node in parent, which
## draws them all once it is in the tree, holding visibility (which may be
## null) meanwhile. Null when the map has none.
static func build(parent: Node, entities: Array[Dictionary], map_visibility: WorldVisibility) -> MapReflections:
	var cubemaps := read(entities)
	if cubemaps.is_empty():
		return null
	var reflections := MapReflections.new()
	reflections.name = "Reflections"
	reflections.visibility = map_visibility
	for cubemap in cubemaps:
		var probe := probe_for(cubemap)
		reflections.probes.append(probe)
		reflections.add_child(probe)
	# Godot keeps one atlas of probe pictures for a world, with room for as
	# many as the project says, and takes all of it up as the first probe is
	# drawn: about 6 MB a place in Forward+, so about 400 MB for its default
	# 64 (Godot 4.7.2's LightStorage::reflection_probe_instance_begin_render;
	# inferred, not measured). Scripts cannot size it for a map.
	var room := int(ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_count", 64))
	if cubemaps.size() > room:
		push_warning("%d cubemaps and room for %d probes (rendering/reflections/reflection_atlas/reflection_count): the rest reflect the sky." % [
			cubemaps.size(), room])
	if map_visibility != null:
		map_visibility.set_process(false)
	parent.add_child(reflections)
	return reflections


## How many frames drawing every probe takes: for each, one for its faces
## and one for each rough level after the first, one to spare, and two
## more for the camera that puts them in line.
func frames_to_capture() -> int:
	var levels := int(ProjectSettings.get_setting("rendering/reflections/sky_reflections/roughness_layers", 8))
	return probes.size() * (levels + 1) + 2


## Whether the probes are still being drawn.
func is_capturing() -> bool:
	return is_processing()


func _process(_delta: float) -> void:
	# Headless nothing is drawn and the count of frames drawn stays at 0, so
	# there the frames processed stand in, and the visibility is let go.
	advance(Engine.get_frames_drawn() if DisplayServer.get_name() != "headless" else Engine.get_process_frames())


## One frame of the drawing, by the number of frames drawn so far: the
## first puts every probe in line, the last lets the visibility go.
func advance(frame: int) -> void:
	if _started < 0:
		_started = frame
		_put_in_line()
		return
	if frame - _started >= frames_to_capture():
		_finish()


func _exit_tree() -> void:
	if is_capturing():
		_finish()


## A camera over every probe's box, drawing once, into a viewport of four
## pixels, what is on the probes' layer, which is nothing: seeing them is
## what queues them to be drawn.
func _put_in_line() -> void:
	var bounds := AABB()
	for i in probes.size():
		var box := probes[i].global_transform * AABB(-probes[i].size * 0.5, probes[i].size)
		bounds = box if i == 0 else bounds.merge(box)
	var margin := 64.0
	_capture = SubViewport.new()
	_capture.name = "PutInLine"
	_capture.size = Vector2i(4, 4)
	_capture.render_target_update_mode = SubViewport.UPDATE_ONCE
	var eye := Camera3D.new()
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = maxf(bounds.size.x, bounds.size.z) + margin * 2.0
	eye.near = 1.0
	eye.far = bounds.size.y + margin * 2.0
	eye.cull_mask = LAYER
	eye.position = Vector3(bounds.get_center().x, bounds.end.y + margin, bounds.get_center().z)
	eye.basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
	_capture.add_child(eye)
	add_child(_capture)
	eye.current = true


func _finish() -> void:
	if _capture != null:
		_capture.queue_free()
		_capture = null
	if visibility != null and is_instance_valid(visibility):
		visibility.set_process(true)
	set_process(false)
