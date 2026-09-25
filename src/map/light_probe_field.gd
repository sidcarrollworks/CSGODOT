class_name LightProbeField
extends Node

## The scene's light probes, for whatever moves through them to read: a
## node in the "light_probes" group holding the map's LightProbes. Put
## there by MapImporter when a map has them; found with find(). While it is
## in the scene, the probes' baked sun shadow is what every probe-lit
## shader reads (LightProbes.SUN_UNIFORM); out of it, they read the
## default, which lets the whole sun through.

var probes: LightProbes

## The field whose sun the shaders read, so that a map's field leaving after
## the next map's has come does not take the next one's away.
static var _drawn: LightProbeField


func _ready() -> void:
	add_to_group(&"light_probes")


func _enter_tree() -> void:
	if probes != null and probes.has_sun_shadows():
		RenderingServer.global_shader_parameter_set(LightProbes.SUN_UNIFORM, probes.sun_texture())
		_drawn = self


func _exit_tree() -> void:
	if _drawn == self:
		RenderingServer.global_shader_parameter_set(LightProbes.SUN_UNIFORM, null)
		_drawn = null


## The scene's probes, or null when the map has none.
static func find(tree: SceneTree) -> LightProbes:
	var field := tree.get_first_node_in_group(&"light_probes") as LightProbeField
	if field == null or field.probes == null or not field.probes.is_loaded():
		return null
	return field.probes
