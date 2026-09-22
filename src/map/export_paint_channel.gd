class_name ExportPaintChannel
extends RefCounted

## Carries a map's blend paint through Godot's glTF import.
##
## Source 2 paints the mix between a material's two layers onto the vertices
## (TEXCOORD4 in the engine). Source 2 Viewer exports it faithfully, as a float
## VEC4 attribute called "_TEXCOORD_4", and Godot's importer drops it: it looks
## up the attribute names it knows and never sees the rest. No warning, no
## data, and nothing for BlendMaterials to blend by.
##
## Renamed to COLOR_0 it comes through as vertex colour. That is not a
## compromise on precision: every one of dust2's 16.6 million paint components
## is an exact multiple of 1/255, and Godot stores vertex colour as 8 bits a
## channel with no sRGB conversion, so the weights arrive bit for bit. The
## alternative, Godot's custom float channels, would cost four times the memory
## for the same numbers, and needs the accessors restructured rather than a key
## renamed.
##
## The rename is done on the text, not by parsing and rewriting: GDScript's
## JSON turns every integer into a float on the way through, which Godot
## tolerates and other glTF readers do not. The quoted key with its colon can
## only be an attribute name; the leading underscore is reserved by the glTF
## spec for exactly this kind of application-specific attribute.

const FROM := "\"_TEXCOORD_4\":"
const TO := "\"COLOR_0\":"


## Renames the paint attribute throughout one glTF. Returns how many
## primitives were changed: 0 if there was nothing to do or it had been done
## already, -1 if the file was left alone for a reason, having said why.
static func fix_file(gltf_path: String) -> int:
	var text := FileAccess.get_file_as_string(gltf_path)
	var count := text.count(FROM)
	if count == 0:
		if text.contains("\"_TEXCOORD_4\""):
			# Spaced differently from how version 20 writes it. Better to be told
			# than to wonder why the walls have gone back to one layer.
			push_warning("%s names its blend paint in a form this does not rename." % gltf_path)
			return -1
		return 0

	# A primitive with a vertex colour of its own as well would end up with the
	# key twice. dust2 has none; say so rather than produce a broken file.
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Could not read %s as JSON; its blend paint was left alone." % gltf_path)
		return -1
	for mesh: Dictionary in (parsed as Dictionary).get("meshes", []):
		for primitive: Dictionary in mesh.get("primitives", []):
			var attributes: Dictionary = primitive.get("attributes", {})
			if attributes.has("_TEXCOORD_4") and attributes.has("COLOR_0"):
				push_warning(
					"%s has a primitive with both blend paint and vertex colour; left alone."
					% gltf_path
				)
				return -1

	var file := FileAccess.open(gltf_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write %s." % gltf_path)
		return -1
	file.store_string(text.replace(FROM, TO))
	file.close()
	return count
