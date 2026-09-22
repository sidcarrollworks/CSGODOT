class_name LightProbeField
extends Node

## The scene's light probes, for whatever moves through them to read: a
## node in the "light_probes" group holding the map's LightProbes. Put
## there by MapImporter when a map has them; found with find().

var probes: LightProbes


func _ready() -> void:
	add_to_group(&"light_probes")


## The scene's probes, or null when the map has none.
static func find(tree: SceneTree) -> LightProbes:
	var field := tree.get_first_node_in_group(&"light_probes") as LightProbeField
	if field == null or field.probes == null or not field.probes.is_loaded():
		return null
	return field.probes
