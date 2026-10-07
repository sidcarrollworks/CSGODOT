extends SceneTree

## Reads the installed CS2 particle KV3, projected-material DATA and impact
## surface/decal tables. Only extraction runs this; the game uses the generated
## HitEffectTable constants and never reads particle definitions on a tick.
##
## godot --headless --path . --script scripts/impact_effect_tables.gd -- <raw> [manifest|dependencies]
##
## `manifest` writes materials.txt/textures.txt/models.txt under raw, for the
## archive extraction stage. `dependencies` resolves material texture slots
## without replacing tables. Run without a mode after material/texture DATA
## has been checked and the sheets reconstructed. That generates reference/effects/
## hits.{json,csv,md} and src/effects/hit_effect_table.gd deterministically.
## SpriteSheet assets keep their archive path under assets/effects/.

const OUT := "res://reference/effects"
const TABLE := "res://src/effects/hit_effect_table.gd"
## These three references are in the shared Core archive, checked 1.41.8.8.
const CORE_TEXTURES := [
	"materials/particle/ash_flecks.vtex",
	"materials/particle/particle_flares/flares_screenmult.vtex",
	"materials/particles/light_flare/light_glow_01.vtex",
]
const BODY_TEXTURES := [
	"materials/blood/blood_default_color.vtex",
	"materials/blood/blood_default_impact.vtex",
	"materials/blood/blood_default_normal.vtex",
]
const START_ROOTS := [
	"blood_impact_low", "blood_impact_med", "blood_impact_high",
	"blood_impact_light_headshot", "blood_impact_friendly",
	"blood_impact_localplayer", "blood_impact_localfrontsimple",
	"blood_impact_localfrontenemy", "blood_impact_localrearhit", "blood_impact_localkillshot",
	"impact_helmet_headshot", "impact_concrete", "impact_metal",
	"impact_dirt", "impact_wood", "impact_glass", "impact_tile",
	"impact_plaster", "impact_metal_grate", "impact_metal_vent",
]

var _failed := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: impact_effect_tables.gd -- <raw directory> [manifest|dependencies]")
		quit(1)
		return
	var raw := args[0].replace("\\", "/").trim_suffix("/")
	var particles := read_particles(raw)
	var surfaces := read_surfaces(raw.path_join("scripts/surfaceproperties_impact_effects.txt"))
	var groups := read_groups(raw.path_join("scripts/decalgroups.vdata"))
	var selected := _select(particles)
	var requests := asset_requests(selected, groups)
	_write_list(raw.path_join("materials.txt"), requests["materials"])
	_write_list(raw.path_join("textures.txt"), requests["textures"])
	_write_list(raw.path_join("core_textures.txt"), CORE_TEXTURES)
	_write_list(raw.path_join("models.txt"), requests["models"])
	if args.size() > 1 and args[1] == "manifest":
		print("impact effects: requested %d materials, %d particle textures, %d models" % [requests["materials"].size(), requests["textures"].size(), requests["models"].size()])
		quit(1 if _failed else 0)
		return
	var materials := read_materials(FileAccess.get_file_as_string(raw.path_join("materials_data.txt")))
	for path: String in requests["materials"]:
		if not materials.has(path):
			printerr("impact effects: missing material DATA for " + path)
			_failed = true
	if _failed:
		# A failed/incomplete extraction must not replace good committed tables.
		quit(1)
		return
	for material: Dictionary in materials.values():
		for path: String in material.get("textures", {}).values():
			(requests["textures"] as Array).append(path)
	requests["textures"] = _unique_sorted(requests["textures"])
	_write_list(raw.path_join("textures.txt"), requests["textures"])
	if args.size() > 1 and args[1] == "dependencies":
		print("impact effects: resolved %d material/particle textures without replacing tables" % requests["textures"].size())
		quit(1 if _failed else 0)
		return
	var layers := {}
	var roots := {}
	var root_params := {}
	var ground := {}
	for name: String in selected:
		var definition: Dictionary = selected[name]
		var normalized := normalize_particle(definition)
		for i in (normalized["children"] as Array).size():
			var child_name: String = normalized["children"][i]
			if selected.has(child_name):
				normalized["child_groups"][i] = selected[child_name].get("m_nGroupID", 0.0)
		if not normalized["children"].is_empty():
			roots[name] = normalized["children"]
			var params := {}
			for key in ["distance_cp", "choose_child", "choose_child_group", "child_groups", "screen_space"]:
				if normalized.has(key):
					params[key] = normalized[key]
			root_params[name] = params
		if not normalized["renderers"].is_empty():
			layers[name] = normalized
			if normalized["kind"] == "projected":
				ground[name] = normalized
	var source := _build(raw.path_join("steam.inf"))
	var table := {"source": source, "roots": roots, "root_params": root_params, "layers": layers, "ground": ground,
		"surfaces": surfaces, "decal_groups": groups, "materials": materials, "textures": requests["textures"], "models": requests["models"]}
	_write_outputs(table)
	print("impact effects: %d roots, %d rendered layers, %d materials, %d textures" % [roots.size(), layers.size(), materials.size(), requests["textures"].size()])
	quit(1 if _failed else 0)


static func read_particles(raw: String) -> Dictionary:
	var particles := {}
	for folder in ["particles/blood_impact", "particles/impact_fx", "particles/water_impact"]:
		for name: String in DirAccess.get_files_at(raw.path_join(folder)):
			if not name.ends_with(".vpcf"):
				continue
			var parsed: Variant = KV3.parse(FileAccess.get_file_as_string(raw.path_join(folder).path_join(name)))
			if parsed is Dictionary:
				particles[name.get_basename()] = parsed
	return particles


func _select(particles: Dictionary) -> Dictionary:
	var pending: Array = START_ROOTS.duplicate()
	var selected := {}
	while not pending.is_empty():
		var name: String = pending.pop_front()
		if selected.has(name):
			continue
		if not particles.has(name):
			printerr("impact effects: no definition for " + name)
			_failed = true
			continue
		var definition: Dictionary = particles[name]
		selected[name] = definition
		for child: Dictionary in definition.get("m_Children", []):
			pending.append(String(child.get("m_ChildRef", "")).get_file().get_basename())
	var sorted := {}
	var names := selected.keys()
	names.sort()
	for name: String in names:
		sorted[name] = selected[name]
	return sorted


static func asset_requests(particles: Dictionary, groups: Dictionary) -> Dictionary:
	var materials: Array = []
	var textures: Array = BODY_TEXTURES.duplicate()
	var models: Array = []
	for definition: Dictionary in particles.values():
		_collect_resources(definition, materials, textures, models)
	for options: Array in groups.values():
		for option: Dictionary in options:
			materials.append(option["material"])
	# RenderModels only names the mesh; its referenced material is read from
	# impact_puff.vmdl's RERL/DATA audit, rather than assumed from its name.
	materials.append("materials/effects/smoke_puff_dirt.vmat")
	models = models.filter(func(path: String) -> bool: return path.begins_with("models/particle/"))
	return {"materials": _unique_sorted(materials), "textures": _unique_sorted(textures), "models": _unique_sorted(models)}


static func _collect_resources(value: Variant, materials: Array, textures: Array, models: Array) -> void:
	if value is Dictionary:
		for nested: Variant in value.values():
			_collect_resources(nested, materials, textures, models)
	elif value is Array:
		for nested: Variant in value:
			_collect_resources(nested, materials, textures, models)
	elif value is String:
		if value.ends_with(".vtex"):
			textures.append(value)
		elif value.ends_with(".vmat"):
			materials.append(value)
		elif value.ends_with(".vmdl"):
			models.append(value)


static func read_surfaces(path: String) -> Dictionary:
	var parsed: Variant = KV3.parse(FileAccess.get_file_as_string(path))
	var surfaces := {}
	if not parsed is Dictionary:
		return surfaces
	for row: Dictionary in parsed.get("SurfacePropertiesList", []):
		var entry := {}
		for pair in [["effect", "effect"], ["effect_simplified", "cheap"], ["impactDecalName", "decal"], ["impactGrazingDecalName", "grazing"]]:
			if row.has(pair[0]):
				var text := String(row[pair[0]])
				entry[pair[1]] = text.get_file().get_basename() if text.ends_with(".vpcf") else text
		surfaces[String(row.get("surfacePropertyName", "default")).to_lower()] = entry
	return surfaces


static func read_groups(path: String) -> Dictionary:
	var parsed: Variant = KV3.parse(FileAccess.get_file_as_string(path))
	var groups := {}
	if not parsed is Dictionary:
		return groups
	for name: String in parsed:
		if not name.begins_with("Blood") and not name.begins_with("Impact."):
			continue
		var options: Array = []
		for entry: Dictionary in parsed[name].get("m_vecOptions", []):
			options.append({"material": entry.get("m_hMaterial", ""), "weight": entry.get("m_flProbability", 1.0)})
		groups[name] = options
	return groups


## DATA dumps have resource reports around their KV3 blocks. Read balanced
## objects instead of treating the CLI report as a standalone KV3 file.
static func read_materials(text: String) -> Dictionary:
	var result := {}
	var at := 0
	while true:
		var marker := text.find("<!-- kv3", at)
		if marker < 0:
			break
		var start := text.find("{", text.find("-->", marker) + 3)
		if start < 0:
			break
		var end := _object_end(text, start)
		if end < 0:
			break
		at = end + 1
		var parsed: Variant = KV3.parse(text.substr(start, end - start + 1))
		if not parsed is Dictionary or not parsed.has("m_materialName"):
			continue
		var params := {}
		var textures := {}
		for group in ["m_intParams", "m_floatParams", "m_vectorParams", "m_intAttributes", "m_floatAttributes", "m_vectorAttributes", "m_stringAttributes"]:
			for item: Dictionary in parsed.get(group, []):
				params[item["m_name"]] = item.get("m_nValue", item.get("m_flValue", item.get("m_value")))
		for item: Dictionary in parsed.get("m_textureParams", []):
			textures[item["m_name"]] = item["m_pValue"]
		for item: Dictionary in parsed.get("m_attributes", []):
			params[item.get("m_name", "")] = item.get("m_flValue", item.get("m_nValue", item.get("m_value", item.get("m_pValue"))))
		result[String(parsed["m_materialName"])] = {"shader": parsed.get("m_shaderName", ""), "params": params, "textures": textures}
	return result


static func _object_end(text: String, start: int) -> int:
	var level := 0
	var quoted := false
	var escaped := false
	for i in range(start, text.length()):
		var character := text[i]
		if escaped:
			escaped = false
		elif character == "\\" and quoted:
			escaped = true
		elif character == '"':
			quoted = not quoted
		elif not quoted:
			if character == "{":
				level += 1
			elif character == "}":
				level -= 1
				if level == 0:
					return i
	return -1


## Normalized ranges preserve direction (some authored min/max are reversed).
## Radius is a half-width in Source units. Vectors use the authored Source
## particle coordinates, +X forward / +Y side / +Z up. The renderer converts.
static func normalize_particle(definition: Dictionary) -> Dictionary:
	var layer := {"count": [1.0, 1.0, 1.0, 1.0], "count_cap": definition.get("m_nMaxParticles", 1000.0),
		"life": [1.0, 1.0], "half": [1.0, 1.0], "alpha": [1.0, 1.0], "seq": [0, 0],
		"velocity_min": [0.0, 0.0, 0.0], "velocity_max": [0.0, 0.0, 0.0],
		"gravity": [0.0, 0.0, 0.0], "drag": 0.0, "grow": [1.0, 1.0],
		"children": [], "child_groups": [], "renderers": [], "kind": "none"}
	if definition.has("m_bScreenSpaceEffect"):
		layer["screen_space"] = definition["m_bScreenSpaceEffect"]
	if definition.has("m_flMaxDrawDistance"):
		layer["max_distance"] = definition["m_flMaxDrawDistance"]
	for child: Dictionary in definition.get("m_Children", []):
		(layer["children"] as Array).append(String(child.get("m_ChildRef", "")).get_file().get_basename())
		(layer["child_groups"] as Array).append(child.get("m_nGroupID", 0.0))
	for emitter: Dictionary in definition.get("m_Emitters", []):
		var input: Variant = emitter.get("m_nParticlesToEmit", 1.0)
		if input is Dictionary and input.get("m_nType") == "PF_TYPE_PARTICLE_DETAIL_LEVEL":
			layer["count"] = [input.get("m_flLOD0", 0.0), input.get("m_flLOD1", 0.0), input.get("m_flLOD2", 0.0), input.get("m_flLOD3", 0.0)]
		else:
			var range_value: Variant = scalar(input)
			layer["count"] = range_value if range_value is Dictionary else [range_value[0], range_value[0], range_value[0], range_value[0]]
		layer["per_frame"] = emitter.get("m_nMaxEmittedPerFrame", 1000.0)
		if emitter.has("m_flInitFromKilledParentParticles"):
			layer["from_parent_death"] = emitter["m_flInitFromKilledParentParticles"] > 0.0
	for op: Dictionary in definition.get("m_Initializers", []):
		_normalize_init(layer, op)
	for op: Dictionary in definition.get("m_Operators", []):
		_normalize_op(layer, op)
	for op: Dictionary in definition.get("m_PreEmissionOperators", []):
		if op.get("_class") == "C_OP_DistanceBetweenCPsToCP":
			layer["distance_cp"] = {"input": [op.get("m_flInputMin", 0.0), op.get("m_flInputMax", 1.0)], "output": [op.get("m_flOutputMin", 0.0), op.get("m_flOutputMax", 1.0)], "cp": op.get("m_nOutputCP", 0.0), "start_cp": op.get("m_nStartCP", 0.0), "end_cp": op.get("m_nEndCP", 1.0), "output_component": op.get("m_nOutputCPField", 0.0)}
		if op.get("_class") == "C_OP_ChooseRandomChildrenInGroup":
			layer["choose_child"] = true
			if op.has("m_nChildGroupID"):
				layer["choose_child_group"] = op["m_nChildGroupID"]
	for op: Dictionary in definition.get("m_Renderers", []):
		if op.get("m_bOnlyRenderInEffectsBloomPass", false):
			continue
		(layer["renderers"] as Array).append(normalize_renderer(op))
	var unsupported: Array = []
	var supported := ["C_INIT_InitFloat", "C_INIT_RandomSequence", "C_INIT_RandomSecondSequence", "C_INIT_CreateWithinSphereTransform", "C_INIT_InitialVelocityNoise", "C_INIT_RandomColor", "C_INIT_AgeNoise", "C_INIT_RandomYawFlip", "C_INIT_NormalOffset", "C_INIT_PositionOffset", "C_INIT_PositionPlaceOnGround", "C_INIT_PositionWarp", "C_OP_BasicMovement", "C_OP_InterpolateRadius", "C_OP_FadeOut", "C_OP_FadeOutSimple", "C_OP_FadeIn", "C_OP_FadeAndKill", "C_OP_Spin", "C_OP_Decay", "C_OP_SetFloat"]
	for collection in ["m_Initializers", "m_Operators"]:
		for op: Dictionary in definition.get(collection, []):
			if op.get("_class", "") not in supported:
				unsupported.append(op.get("_class", ""))
	if not unsupported.is_empty():
		layer["unsupported_ops"] = _unique_sorted(unsupported)
	if not layer["renderers"].is_empty():
		var first: Dictionary = layer["renderers"][0]
		layer["kind"] = first["kind"]
		for key: String in first:
			if key != "kind":
				layer[key] = first[key]
	return _compact(layer)


static func _normalize_init(layer: Dictionary, op: Dictionary) -> void:
	match String(op.get("_class", "")):
		"C_INIT_InitFloat":
			var fields := {1: "life", 3: "half", 4: "roll", 7: "alpha", 10: "trail_time", 38: "frame"}
			var field := int(op.get("m_nOutputField", 3))
			if fields.has(field):
				var key: String = fields[field]
				var value: Variant = scalar(op.get("m_InputValue", 0.0))
				var source: Variant = op.get("m_InputValue", 0.0)
				if source is Dictionary and source.get("m_nType") == "PF_TYPE_RANDOM_BIASED":
					if not layer.has("bias"):
						layer["bias"] = {}
					layer["bias"][key] = {"type": source.get("m_nBiasType", "PF_BIAS_TYPE_STANDARD"), "parameter": source.get("m_flBiasParameter", 0.0)}
				if op.get("m_nSetMethod") == "PARTICLE_SET_SCALE_INITIAL_VALUE":
					layer[key + "_scale"] = value
				else:
					layer[key] = value
		"C_INIT_RandomSequence", "C_INIT_RandomSecondSequence":
			layer["seq2" if op["_class"] == "C_INIT_RandomSecondSequence" else "seq"] = [op.get("m_nSequenceMin", 0.0), op.get("m_nSequenceMax", 0.0)]
		"C_INIT_CreateWithinSphereTransform":
			layer["velocity_min"] = vector_input(op.get("m_LocalCoordinateSystemSpeedMin", [0.0, 0.0, 0.0]))
			layer["velocity_max"] = vector_input(op.get("m_LocalCoordinateSystemSpeedMax", [0.0, 0.0, 0.0]))
			layer["sphere"] = [op.get("m_fRadiusMin", 0.0), op.get("m_fRadiusMax", 0.0)]
			layer["sphere_speed"] = [op.get("m_fSpeedMin", 0.0), op.get("m_fSpeedMax", 0.0)]
			layer["velocity_cp"] = op.get("m_TransformInput", {}).get("m_nControlPoint", 0.0)
		"C_INIT_InitialVelocityNoise":
			layer["noise_velocity_min"] = op.get("m_vecOutputMin", [0.0, 0.0, 0.0])
			layer["noise_velocity_max"] = op.get("m_vecOutputMax", [0.0, 0.0, 0.0])
			if op.has("m_TransformInput"):
				var transform: Dictionary = op["m_TransformInput"]
				layer["noise_transform"] = transform.get("m_nType", "")
				layer["noise_cp"] = transform.get("m_nControlPoint", 0.0)
		"C_INIT_RandomColor":
			layer["color_min"] = (op.get("m_ColorMin", [255.0, 255.0, 255.0]) as Array).slice(0, 3)
			layer["color_max"] = (op.get("m_ColorMax", [255.0, 255.0, 255.0]) as Array).slice(0, 3)
		"C_INIT_AgeNoise":
			layer["age_noise"] = [op.get("m_flAgeMin", 0.0), op.get("m_flAgeMax", 0.0)]
		"C_INIT_RandomYawFlip":
			layer["yaw_flip"] = true
		"C_INIT_NormalOffset":
			layer["normal_offset"] = vector_input(op.get("m_OffsetMin", [0.0, 0.0, 0.0]))
			layer["normal_offset_max"] = vector_input(op.get("m_OffsetMax", op.get("m_OffsetMin", [0.0, 0.0, 0.0])))
			layer["normal_local"] = op.get("m_bLocalCoords", false)
			layer["normal_normalize"] = op.get("m_bNormalize", false)
		"C_INIT_PositionOffset":
			layer["offset_min"] = vector_input(op.get("m_OffsetMin", [0.0, 0.0, 0.0]))
			layer["offset_max"] = vector_input(op.get("m_OffsetMax", [0.0, 0.0, 0.0]))
		"C_INIT_PositionPlaceOnGround":
			var trace: Variant = scalar(op.get("m_flMaxTraceLength", 128.0))
			layer["ground_trace"] = trace[0] if trace is Array else trace
			layer["ground_normal"] = op.get("m_bSetNormal", false)
		"C_INIT_PositionWarp":
			layer["warp_min"] = vector_input(op.get("m_vecWarpMin", [1.0, 1.0, 1.0]))
			layer["warp_max"] = vector_input(op.get("m_vecWarpMax", [1.0, 1.0, 1.0]))
		"C_INIT_RandomScalar":
			layer["scalar_" + str(int(op.get("m_nField", 3)))] = [op.get("m_flMin", 0.0), op.get("m_flMax", 1.0)]


static func _normalize_op(layer: Dictionary, op: Dictionary) -> void:
	match String(op.get("_class", "")):
		"C_OP_BasicMovement":
			layer["gravity"] = op.get("m_Gravity", [0.0, 0.0, 0.0])
			layer["drag"] = op.get("m_fDrag", 0.0)
		"C_OP_InterpolateRadius":
			layer["grow"] = [op.get("m_flStartScale", 1.0), op.get("m_flEndScale", 1.0)]
			layer["grow_bias"] = op.get("m_flBias", 0.5)
			layer["grow_time"] = [op.get("m_flStartTime", 0.0), op.get("m_flEndTime", 1.0)]
			layer["grow_ease"] = op.get("m_bEaseInAndOut", false)
		"C_OP_FadeOut":
			layer["fade_out"] = [op.get("m_flFadeOutTimeMin", 0.25), op.get("m_flFadeOutTimeMax", 0.25)]
			layer["fade_proportional"] = op.get("m_bProportional", true)
			layer["fade_out_ease"] = op.get("m_bEaseInAndOut", true)
		"C_OP_FadeOutSimple":
			layer["fade_out"] = [op.get("m_flFadeOutTime", 0.25), op.get("m_flFadeOutTime", 0.25)]
			layer["fade_proportional"] = true
			layer["fade_out_ease"] = false
		"C_OP_FadeIn":
			layer["fade_in"] = [op.get("m_flFadeInTimeMin", 0.25), op.get("m_flFadeInTimeMax", 0.25)]
			layer["fade_in_proportional"] = op.get("m_bProportional", true)
		"C_OP_FadeAndKill":
			layer["fade_in_frac"] = op.get("m_flEndFadeInTime", 0.5)
			layer["fade_out_frac"] = op.get("m_flStartFadeOutTime", 0.5)
			layer["fade_in_start_frac"] = op.get("m_flStartFadeInTime", 0.0)
			layer["fade_in_start_alpha"] = op.get("m_flStartAlpha", 0.0)
			layer["fade_out_end_frac"] = op.get("m_flEndFadeOutTime", 1.0)
			layer["fade_out_end_alpha"] = op.get("m_flEndAlpha", 0.0)
		"C_OP_Spin":
			layer["spin"] = op.get("m_nSpinRateDegrees", 0.0)
		"C_OP_SetFloat":
			var fields := {3: "half", 4: "roll", 7: "alpha", 10: "trail_time", 18: "material_age", 38: "frame"}
			var field := int(op.get("m_nOutputField", 3))
			var key: String = fields.get(field, "field_" + str(field))
			layer[key + "_curve"] = scalar(op.get("m_InputValue", 0.0))
			layer[key + "_method"] = op.get("m_nSetMethod", "PARTICLE_SET_REPLACE_VALUE")


## Dynamic inputs remain descriptors, including exact authored curve points;
## callers evaluate them when the burst is created, never parse the source.
static func scalar(input: Variant) -> Variant:
	if not input is Dictionary:
		return [float(input), float(input)]
	var type := String(input.get("m_nType", "PF_TYPE_LITERAL"))
	if type == "PF_TYPE_LITERAL":
		var value := float(input.get("m_flLiteralValue", 0.0))
		return [value, value]
	if type.begins_with("PF_TYPE_RANDOM"):
		return [input.get("m_flRandomMin", 0.0), input.get("m_flRandomMax", 1.0)]
	var value := {"type": type, "map": input.get("m_nMapType", "PF_MAP_TYPE_DIRECT"), "cp": input.get("m_nControlPoint", 0.0), "component": input.get("m_nVectorComponent", 0.0), "bias_type": input.get("m_nBiasType", "PF_BIAS_TYPE_STANDARD"), "attribute": input.get("m_nScalarAttribute", 3.0), "input_mode": input.get("m_nInputMode", "PF_INPUT_MODE_CLAMPED"),
		"input": [input.get("m_flInput0", 0.0), input.get("m_flInput1", 1.0)], "output": [input.get("m_flOutput0", 0.0), input.get("m_flOutput1", 1.0)], "multiplier": input.get("m_flMultFactor", 1.0)}
	var points: Array = []
	for point: Dictionary in input.get("m_Curve", {}).get("m_spline", []):
		points.append([point.get("x", 0.0), point.get("y", 0.0)])
	if not points.is_empty():
		value["curve"] = points
	if input.get("m_nMapType") == "PF_MAP_TYPE_REMAP_BIASED":
		value["bias"] = input.get("m_flBiasParameter", 0.0)
	if input.get("m_nMapType") == "PF_MAP_TYPE_NOTCHED":
		value["notched_range"] = [input.get("m_flNotchedRangeMin", 0.0), input.get("m_flNotchedRangeMax", 1.0)]
		value["notched_output"] = [input.get("m_flNotchedOutputOutside", 0.0), input.get("m_flNotchedOutputInside", 1.0)]
	return value


static func vector_input(input: Variant) -> Variant:
	return input.get("m_vLiteralValue", [0.0, 0.0, 0.0]) if input is Dictionary else input


static func normalize_renderer(op: Dictionary) -> Dictionary:
	var class_names := {"C_OP_RenderSprites": "sprite", "C_OP_RenderTrails": "trail", "C_OP_RenderProjected": "projected", "C_OP_RenderModels": "model"}
	var render := {"kind": class_names.get(op.get("_class", ""), "unsupported"), "blend": "alpha"}
	for texture: Dictionary in op.get("m_vecTexturesInput", []):
		if texture.get("m_bReplaceTextureWithGradient", false):
			var stops: Array = []
			for stop: Dictionary in texture.get("m_Gradient", {}).get("m_Stops", []):
				stops.append([stop.get("m_flPosition", 0.0), stop.get("m_Color", [255.0, 255.0, 255.0])])
			render["gradient"] = stops
			_texture_metadata(render, texture, "gradient")
			continue
		var path := String(texture.get("m_hTexture", ""))
		# A layer switched off (impact_light_flash's second renderer turns
		# off ash_flecks and draws particle_glow_04 alone) is not drawn.
		if path.is_empty() or not bool(texture.get("m_bEnabled", true)):
			continue
		if texture.get("m_nTextureType") == "SPRITECARD_TEXTURE_ANIMMOTIONVEC":
			render["tex_mv"] = path
		elif not render.has("tex"):
			render["tex"] = path
		else:
			render["tex_breakup"] = path
			_texture_metadata(render, texture, "breakup")
	for pair in [["m_flRadiusScale", "radius_scale"], ["m_flOverbrightFactor", "overbright"], ["m_flAnimationRate", "frame_rate"], ["m_flMaxLength", "max_length"], ["m_flMaxSize", "max_screen"], ["m_flMinSize", "min_screen"], ["m_flAlphaScale", "render_alpha"], ["m_flMotionVectorScaleU", "motion_u"], ["m_flMotionVectorScaleV", "motion_v"], ["m_materialName", "material"], ["m_flMinProjectionDepth", "projection_min"], ["m_flMaxProjectionDepth", "projection_max"], ["m_bOrientToNormal", "orient_normal"], ["m_bEnableFadingAndClamping", "screen_clamp"], ["m_nAnimationType", "animation_type"], ["m_flLengthFadeInTime", "length_fade_in"]]:
		if op.has(pair[0]):
			render[pair[1]] = op[pair[0]]
	for pair in [["m_bAnimateInFPS", "animate_in_fps"], ["m_bOrientZ", "orient_z"]]:
		if op.has(pair[0]):
			render[pair[1]] = op[pair[0]]
	# The renderer's own colour, multiplied into the particle's: the darken
	# sprites are authored white particles drawn at 33/27/27. Only a literal
	# colour is kept; a gradient or attribute input is not drawn yet.
	var tint: Variant = op.get("m_vecColorScale")
	if tint is Dictionary and tint.get("m_nType") == "PVEC_TYPE_LITERAL_COLOR":
		var literal: Array = tint.get("m_LiteralColor", [255, 255, 255])
		var rgb := [float(literal[0]), float(literal[1]), float(literal[2])]
		if rgb != [255.0, 255.0, 255.0]:
			render["color_scale"] = rgb
	if op.has("m_flStartFadeSize") or op.has("m_flEndFadeSize"):
		render["screen_fade"] = [op.get("m_flStartFadeSize", 0.0), op.get("m_flEndFadeSize", 1.0)]
	if op.has("m_flSourceAlphaValueToMapToZero"):
		render["alpha_threshold"] = scalar(op["m_flSourceAlphaValueToMapToZero"])
	if op.get("m_nOutputBlendMode") == "PARTICLE_OUTPUT_BLEND_MODE_ADD":
		render["blend"] = "add"
	if op.has("m_ModelList"):
		render["model"] = op["m_ModelList"][0].get("m_model", "")
	if op.has("m_vecProjectedMaterials") and not op["m_vecProjectedMaterials"].is_empty():
		render["material"] = op["m_vecProjectedMaterials"][0].get("m_hMaterial", "")
	return render


## ParticleTextureLayer defaults are MULTIPLY / MIX_RGBA / strength 1.
## Keep the authored operation even where this renderer does not yet draw it.
static func _texture_metadata(render: Dictionary, texture: Dictionary, prefix: String) -> void:
	render[prefix + "_blend"] = texture.get("m_nTextureBlendMode", "SPRITECARD_TEXTURE_BLEND_MULTIPLY")
	render[prefix + "_channels"] = texture.get("m_nTextureChannels", "SPRITECARD_TEXTURE_CHANNEL_MIX_RGBA")
	render[prefix + "_strength"] = texture.get("m_flTextureBlend", 1.0)
	if texture.has("m_TextureControls"):
		render[prefix + "_controls"] = texture["m_TextureControls"]


static func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("m_nType"):
			if value.get("m_nType") == "PVEC_TYPE_LITERAL":
				return value.get("m_vLiteralValue", [0.0, 0.0, 0.0])
			var normalized: Variant = scalar(value)
			return normalized[0] if value.get("m_nType") == "PF_TYPE_LITERAL" else normalized
		var result := {}
		for key: String in value:
			result[key] = _compact(value[key])
		return result
	if value is Array:
		var result: Array = []
		for nested: Variant in value:
			result.append(_compact(nested))
		return result
	return value


static func _unique_sorted(values: Array) -> Array:
	var seen := {}
	for value: Variant in values:
		if value is String and not value.is_empty():
			seen[value] = true
	var sorted := seen.keys()
	sorted.sort()
	return sorted


func _write_list(path: String, values: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failed = true
		return
	for value: String in values:
		file.store_line(value + "_c")


static func _build(path: String) -> Dictionary:
	var build := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.contains("="):
			build[line.get_slice("=", 0)] = line.get_slice("=", 1).strip_edges()
	return build


func _write_outputs(table: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_write_file(OUT.path_join("hits.json"), JSON.stringify(table, "\t", false) + "\n")
	var code := "class_name HitEffectTable\nextends RefCounted\n\n## Generated by scripts/impact_effect_tables.gd from installed CS2.\n## Source coordinates: +X forward, +Y side, +Z up; units are inches/seconds.\n## life/half/alpha are ranges, count is LOD0..3 or a dynamic CP descriptor.\n## renderers contains the main-pass composition; the first is also flattened\n## onto each layer for simple clients. Ground splats spawn from parent death.\n## Shader features and game-side root selection are not proved by this table.\n"
	for pair in [["source", "SOURCE"], ["roots", "ROOTS"], ["root_params", "ROOT_PARAMS"], ["layers", "LAYERS"], ["ground", "GROUND"], ["surfaces", "SURFACES"], ["decal_groups", "DECAL_GROUPS"], ["materials", "MATERIALS"], ["textures", "TEXTURES"], ["models", "MODELS"]]:
		code += "\nconst %s := %s\n" % [pair[1], JSON.stringify(table[pair[0]], "\t", false)]
	_write_file(TABLE, code)
	var page := "# Current CS2 blood and bullet impact asset tables\n\nGenerated by `scripts/impact_effect_tables.gd`; regenerate, do not hand-edit.\n\n"
	page += "Read from CS2 **%s**, source revision **%s**, built **%s %s**.\n\n" % [table["source"].get("PatchVersion", "unknown"), table["source"].get("SourceRevision", "unknown"), table["source"].get("VersionDate", "unknown"), table["source"].get("VersionTime", "unknown")]
	page += "Particles are decoded KV3, material parameters are decoded DATA (including shader version 72), surface mappings and weighted decal groups are read directly from the archive. `hits.json` retains normalized numbers and current material texture/size/aging flags. `HitEffectTable` exposes the same data as constants so no source files are parsed during gameplay.\n\n"
	page += "Renderers keep their own colour (`color_scale`, 0-255), alpha scale (`render_alpha`) and size limits as shares of the screen's height (`min_screen`, `max_screen`); a texture the renderer switches off is left out. Layer counts retain all four authored detail settings and the separate particle cap; actual CS2 budgets and the engine's low/med/high/headshot selection remain unverified. Numeric ranges preserve the authored order. Motion vectors, noise, breakup and gradient lighting need renderer support; listing assets does not imply every Source 2 operator is reproduced. CP curves retain points but not spline tangents. Ground decals are parent-death projections, separate from persistent Blood-group world decals and body wound accumulation.\n\n"
	page += "| Layer | Kind | Count (LOD0–3) | Radius | Lifetime (s) | Texture/material/model |\n|---|---|---|---|---|---|\n"
	var csv := FileAccess.open(OUT.path_join("hits.csv"), FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(["layer", "kind", "count", "radius", "life", "asset"]))
	for name: String in table["layers"]:
		var layer: Dictionary = table["layers"][name]
		var values := PackedStringArray([name, layer["kind"], JSON.stringify(layer["count"]), JSON.stringify(layer["half"]), JSON.stringify(layer["life"]), layer.get("tex", layer.get("material", layer.get("model", "")))])
		page += "| %s | %s | %s | %s | %s | %s |\n" % Array(values)
		csv.store_csv_line(values)
	_write_file(OUT.path_join("hits.md"), page)
	_write_file(OUT.path_join("hits.csv.import"), "[remap]\n\nimporter=\"keep\"\n")


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("impact effects: could not write " + path)
		_failed = true
		return
	file.store_string(text)
