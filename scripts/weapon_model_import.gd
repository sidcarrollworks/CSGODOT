@tool
extends EditorScenePostImport

## Run on every weapon model as Godot imports it (write_import_settings.gd
## sets it as the import script of every glTF under the weapons' models):
## leaves out the second body a gun carries, ...body_legacy, which CS2
## draws only for skins marked use_legacy_model and this game never draws.
## Hidden, it was still loaded, and its textures were 14% of every gun's
## (reference/research/weapon-preload.md). The rule is the one the models
## are drawn by (RigModel.is_spare_body): a weapon whose only body it is
## keeps it (the default knives), and any other mesh stays (the Dual
## Berettas' holster, the C4's screen). The import is not run again when
## the rule changes: run write_import_settings.gd's reimport after such a
## change.


func _post_import(scene: Node) -> Object:
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var spare := meshes.filter(func(mesh: Node) -> bool: return RigModel.is_spare_body(mesh, meshes))
	for mesh: Node in spare:
		mesh.get_parent().remove_child(mesh)
		mesh.free()
	return scene
