class_name MapShadows
extends RefCounted

## The static map's shadow from the sun, as CS2 baked it.
##
## CS2 lights with the sun live, but works out in advance where the map
## shades itself from it: its lightmap bake leaves a page beside the bounce
## light, direct_light_shadows, holding for every texel how much of each
## stationary light is blocked, one channel per light and 1 for all of it,
## and the light probes carry the same for whatever the lightmaps do not
## cover (LightProbes). A light's bakedshadowindex names its channel: on
## dust2 the sun's is 0, and the two lamps down lower tunnels have 1 and 2
## (their shadows are still Godot's, MapLighting.barn_light). A surface
## takes the sun times one minus its channel, as Source 2 Viewer's
## lighting.slang does, and the live shadow map is drawn on top of that,
## so the live one needs only what moves: the map goes on a render layer
## the sun's shadow casters leave out (LAYER, MapLighting).
##
## That is most of what a frame cost to draw: the sun drawing the map into
## its four splits was 2.0 of 3.1 ms of GPU at 1920x1080 on Sid's RTX
## 4070 Ti, 6.3 of 10.4 ms at 3840x2160, and 1.7 ms of the renderer's CPU
## (reference/rendering.md, R4).

## Where the extraction puts the page, relative to the directory the world
## glTF is in: Source 2 Viewer writes a .png, or an .exr for a page it
## finds stored in HDR.
const FILES := ["lightmaps/direct_light_shadows.png", "lightmaps/direct_light_shadows.exr"]
const ENTITIES_FILE := "entities/default_ents.vents"

## The render layer a map with baked shadows is drawn on, which the sun
## leaves out of its live shadow map (editor layer 11). Nothing else uses it.
const LAYER := 1 << 10


## The channel of the page that holds a light's baked shadow, from its
## entity: bakedshadowindex, or bakelightindex in older maps, as Source 2
## Viewer's SceneLight reads them. -1 for none.
static func channel_of(entity: Dictionary) -> int:
	var channel := int(entity.get("bakedshadowindex", entity.get("bakelightindex", "-1")))
	return channel if channel >= 0 and channel <= 3 else -1


## The sun's channel among a map's entities, or -1.
static func sun_channel(entities: Array[Dictionary]) -> int:
	for entity in entities:
		if entity.get("classname", "") == "light_environment":
			return channel_of(entity)
	return -1


## The sun's channel for the map under map_dir, from its entity lump; -1
## when there is no lump or the sun has none.
static func sun_channel_at(map_dir: String) -> int:
	var path := ProjectSettings.globalize_path(map_dir.path_join(ENTITIES_FILE))
	return sun_channel(SourceEntities.parse(path)) if FileAccess.file_exists(path) else -1


## One channel of four picked out: what a texel is dotted with to read that
## light's shadow. Zero for none, which reads as no shadow.
static func channel_mask(channel: int) -> Vector4:
	var mask := Vector4.ZERO
	if channel >= 0 and channel <= 3:
		mask[channel] = 1.0
	return mask


## Puts meshes whose shadows are baked on LAYER, off every other layer: a
## mesh left on any layer the sun's casters include would still be drawn
## into its shadow map.
static func take_out_of_live_shadows(meshes: Array[MeshInstance3D]) -> void:
	for mesh in meshes:
		mesh.layers = LAYER
