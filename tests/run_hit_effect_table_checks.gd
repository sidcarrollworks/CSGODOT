extends "res://tests/check_suite.gd"

const Tables := preload("res://scripts/impact_effect_tables.gd")
const Hits := preload("res://src/effects/hit_effect_table.gd")


func _init() -> void:
	super()
	_normalization()
	_material_data()
	_graph_integrity()
	_current_numbers()
	_finish("hit-effect-table")


func _normalization() -> void:
	# Modern DATA dumps contain expanded default descriptors and a gradient
	# between the color and motion texture. Neither can be mistaken for tex_mv.
	var definition := {
		"m_nMaxParticles": 3,
		"m_Emitters": [{"_class": "C_OP_InstantaneousEmitter", "m_nParticlesToEmit": {
			"m_nType": "PF_TYPE_PARTICLE_DETAIL_LEVEL", "m_flLOD0": 1.0, "m_flLOD1": 2.0, "m_flLOD2": 3.0, "m_flLOD3": 3.0}}],
		"m_Initializers": [
			{"_class": "C_INIT_InitFloat", "m_nOutputField": 1, "m_InputValue": {"m_nType": "PF_TYPE_RANDOM_BIASED", "m_flRandomMin": 0.35, "m_flRandomMax": 0.75, "m_nBiasType": "PF_BIAS_TYPE_EXPONENTIAL", "m_flBiasParameter": -0.5}},
			{"_class": "C_INIT_PositionOffset", "m_OffsetMin": {"m_nType": "PVEC_TYPE_LITERAL", "m_vLiteralValue": [0.0, 0.0, 32.0]}},
			{"_class": "C_INIT_PositionPlaceOnGround", "m_flMaxTraceLength": {"m_nType": "PF_TYPE_LITERAL", "m_flLiteralValue": 256.0}},
			{"_class": "C_INIT_InitialVelocityNoise", "m_vecOutputMin": [0.0, 0.0, 25.0], "m_TransformInput": {"m_nType": "PT_TYPE_INVALID"}},
		],
		"m_Operators": [{"_class": "C_OP_BasicMovement", "m_Gravity": {"m_nType": "PVEC_TYPE_LITERAL", "m_vLiteralValue": [0.0, 0.0, -450.0]}, "m_fDrag": 0.05}],
		"m_Renderers": [{"_class": "C_OP_RenderSprites", "m_vecTexturesInput": [
			{"m_hTexture": "materials/particle/blood.vtex"},
			{"m_bReplaceTextureWithGradient": true, "m_nTextureType": "SPRITECARD_TEXTURE_1D_COLOR_LOOKUP", "m_nTextureBlendMode": "SPRITECARD_TEXTURE_BLEND_REPLACE", "m_nTextureChannels": "SPRITECARD_TEXTURE_CHANNEL_MIX_RGB", "m_Gradient": {"m_Stops": [{"m_flPosition": 0.0, "m_Color": [154.0, 13.0, 13.0]}]}},
			{"m_hTexture": "materials/particle/blood_mv.vtex", "m_nTextureType": "SPRITECARD_TEXTURE_ANIMMOTIONVEC"},
			{"m_hTexture": "materials/particle/breakup.vtex", "m_nTextureBlendMode": "SPRITECARD_TEXTURE_BLEND_SUBTRACT", "m_flTextureBlend": {"m_nType": "PF_TYPE_COLLECTION_AGE", "m_nMapType": "PF_MAP_TYPE_REMAP", "m_flInput0": 0.0, "m_flInput1": 0.3}},
		], "m_flMotionVectorScaleU": {"m_nType": "PF_TYPE_LITERAL", "m_flLiteralValue": -8.0}}],
	}
	var layer := Tables.normalize_particle(definition)
	_check_equal(layer["count"], [1.0, 2.0, 3.0, 3.0], "detail counts remain separate from particle capacity")
	_check_equal(layer["life"], [0.35, 0.75], "biased lifetime retains the authored range")
	_check_near(layer["bias"]["life"]["parameter"], -0.5, "biased lifetime retains its authored bias")
	_check_equal(layer["gravity"], [0.0, 0.0, -450.0], "expanded gravity is an authored Source vector")
	_check_equal(layer["offset_min"], [0.0, 0.0, 32.0], "expanded ground offset is not a runtime descriptor")
	_check_near(layer["ground_trace"], 256.0, "expanded trace length is reduced to units")
	_check_equal(layer["noise_transform"], "PT_TYPE_INVALID", "world-space velocity noise must not rotate with its impact CP")
	_check_near(layer["noise_cp"], 0.0, "velocity noise keeps the authored transform CP")
	_check_equal(layer["tex_mv"], "materials/particle/blood_mv.vtex", "gradient slot does not hide the motion texture")
	_check_equal(layer["gradient"], [[0.0, [154.0, 13.0, 13.0]]], "gradient retains color lookup stop")
	_check_equal(layer["gradient_blend"], "SPRITECARD_TEXTURE_BLEND_REPLACE", "gradient replace is distinct from default multiply")
	_check_equal(layer["gradient_channels"], "SPRITECARD_TEXTURE_CHANNEL_MIX_RGB", "gradient luminance channel controls survive normalization")
	_check_near(layer["gradient_strength"], 1.0, "gradient default contribution is full strength")
	_check_equal(layer["breakup_blend"], "SPRITECARD_TEXTURE_BLEND_SUBTRACT", "breakup subtraction is not inferred from a texture filename")
	_check_equal(layer["breakup_strength"]["input"], [0.0, 0.3], "breakup uses authored collection-age range")
	_check_near(layer["motion_u"], -8.0, "literal motion scale is a shader number")
	var renderer := Tables.normalize_renderer({"_class": "C_OP_RenderModels", "m_bAnimateInFPS": true, "m_bOrientZ": true})
	_check_equal(renderer["animate_in_fps"], true, "FPS animation is separate from ordinary sequence passes")
	_check_equal(renderer["orient_z"], true, "model renderer retains authored normal alignment axis")
	var default_gradient := Tables.normalize_renderer({"_class": "C_OP_RenderSprites", "m_vecTexturesInput": [{"m_bReplaceTextureWithGradient": true}]})
	_check_equal(default_gradient["gradient_blend"], "SPRITECARD_TEXTURE_BLEND_MULTIPLY", "omitted gradient blend keeps the source default multiply")
	var dynamic: Variant = Tables.scalar({"m_nType": "PF_TYPE_CONTROL_POINT_COMPONENT", "m_nControlPoint": 6, "m_nVectorComponent": 0, "m_flMultFactor": 2.0, "m_Curve": {"m_spline": [{"x": 0.0, "y": 0.65}, {"x": 1.0, "y": 2.0}]}})
	_check_equal(dynamic["curve"], [[0.0, 0.65], [1.0, 2.0]], "dynamic radius keeps authored curve points")
	_check_near(dynamic["multiplier"], 2.0, "dynamic input multiplier survives normalization")


func _material_data() -> void:
	var report := '--- Material report ---\n<!-- kv3 encoding:text -->\n{ m_materialName = "materials/decals/example.vmat" m_shaderName = "csgo_projected_decals.vfx" m_floatAttributes = [ { m_name = "DecalWorldWidth" m_flValue = 47.2 }, ] m_textureParams = [ { m_name = "g_tColor" m_pValue = resource:"materials/blood/color.vtex" }, ] m_stringAttributes = [ { m_name = "Label" m_value = "a { brace }" }, ] }\n--- next resource ---\n'
	var parsed := Tables.read_materials(report)
	_check(parsed.has("materials/decals/example.vmat"), "shader version-independent DATA report is parsed")
	var material: Dictionary = parsed["materials/decals/example.vmat"]
	_check_near(material["params"]["DecalWorldWidth"], 47.2, "material attributes supply actual decal dimensions")
	_check_equal(material["params"]["Label"], "a { brace }", "quoted braces do not truncate a material DATA block")
	_check_equal(material["textures"]["g_tColor"], "materials/blood/color.vtex", "typed texture reference survives DATA parsing")


func _graph_integrity() -> void:
	for root_name: String in Hits.ROOTS:
		for child: String in Hits.ROOTS[root_name]:
			_check(Hits.ROOTS.has(child) or Hits.LAYERS.has(child), "%s child %s is extracted" % [root_name, child])
	for layer_name: String in Hits.LAYERS:
		var layer: Dictionary = Hits.LAYERS[layer_name]
		_check(layer["gravity"] is Array and layer["gravity"].size() == 3, layer_name + " has shader-ready gravity")
		for render: Dictionary in layer["renderers"]:
			for key in ["tex", "tex_mv", "tex_breakup"]:
				if render.has(key):
					_check(Hits.TEXTURES.has(render[key]), "%s texture %s is requested" % [layer_name, key])
			if render.has("material") and not String(render["material"]).is_empty():
				_check(Hits.MATERIALS.has(render["material"]), layer_name + " projection material is decoded")
	for group_name: String in Hits.DECAL_GROUPS:
		for option: Dictionary in Hits.DECAL_GROUPS[group_name]:
			_check(Hits.MATERIALS.has(option["material"]), group_name + " weighted material is decoded")
			_check(float(option["weight"]) > 0.0, group_name + " material has positive probability")
	for material_name: String in Hits.MATERIALS:
		for texture: String in Hits.MATERIALS[material_name]["textures"].values():
			_check(Hits.TEXTURES.has(texture), material_name + " material texture is requested")


func _current_numbers() -> void:
	for root_name in ["blood_impact_low", "blood_impact_med", "blood_impact_high"]:
		_check(Hits.ROOTS[root_name].has("blood_impact_low_forw_spray"), root_name + " includes the recent forward spray")
	_check_equal(Hits.LAYERS["blood_impact_low_forw_spray"]["life"], [0.35, 0.75], "current forward spray base lifetime")
	_check_equal(Hits.LAYERS["blood_impact_med_vis_spray"]["half"], [11.0, 16.0], "current medium spray base radius")
	_check_equal(Hits.LAYERS["blood_impact_med_vis_spray"]["gravity"], [0.0, 0.0, -250.0], "current medium spray gravity")
	_check_equal(Hits.GROUND["blood_impact_med_ground_decal"]["life"], [5.0, 10.0], "ground splats do not inherit generic persistent decal lifetime")
	_check_equal(Hits.GROUND["blood_impact_med_ground_decalaltb"]["life"], [20.0, 20.0], "third medium ground variant keeps twenty-second lifetime")
	for ground_name: String in Hits.GROUND:
		_check(Hits.GROUND[ground_name].get("from_parent_death", false), ground_name + " spawns from parent death")
		_check_near(Hits.GROUND[ground_name]["ground_trace"], 256.0, ground_name + " uses authored ground trace")
	_check_equal(Hits.LAYERS["impact_fx_hit_darken_model"]["kind"], "model", "recent dust puff is a model renderer")
	_check_equal(Hits.LAYERS["impact_fx_hit_darken_model"]["model"], "models/particle/impacts/impact_puff.vmdl", "recent dust puff uses the shipped mesh")
	_check_equal(Hits.LAYERS["impact_fx_hit_darken_model"]["normal_offset_max"], [0.0, 0.0, 10.0], "recent puff adds an authored ten-unit normal vector, not a position offset")
	_check(Hits.LAYERS["impact_fx_hit_darken_model"].normal_local and Hits.LAYERS["impact_fx_hit_darken_model"].normal_normalize, "puff normal offset retains local-frame and normalization flags")
	_check_equal(Hits.LAYERS["impact_helmet_headshot_spark"]["blend"], "add", "helmet sparks keep additive main-pass rendering")
	_check_equal(Hits.SURFACES["wood"]["decal"], "Impact.Wood", "case-insensitive surface selection retains authored wood group")
	_check_near(Hits.ROOT_PARAMS["impact_plaster"]["choose_child_group"], 0.0, "plaster chooses one group-zero child rather than starting every fallback")
	_check_equal(Hits.DECAL_GROUPS["Blood"].size(), 7, "current Blood group has seven weighted materials")
	_check_equal(Hits.DECAL_GROUPS["Bloodlvl4"].size(), 12, "current Bloodlvl4 group has twelve weighted materials")
