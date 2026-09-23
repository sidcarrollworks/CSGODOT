extends "res://tests/check_suite.gd"

## Checks the extracted weapons and player models, if there are any.
##
##   godot --headless --path . --script tests/run_model_checks.gd
##
## Like the dust2 checks, this passes without checking anything on a machine
## where scripts/extract_assets.sh has not been run. Where it has, it is the
## test that what Godot made of the exports is what the game will need: a
## skeleton to animate, the first-person arm meshes to draw, the weapon's own
## animations, and the first-person clips as animations of their own; and
## that the view model puts them together, with the weapon in the hands.

const WEAPONS_DIR := "res://assets/weapons"
const CHARACTERS_DIR := "res://assets/characters"

var _frames: int = 0
var _view_model: ViewModel
var _player_model: PlayerModel
var _bot: Bot
var _bot_world: Node3D
var _bot_started_frame: int = 0
var _bot_phase: int = 0
var _bot_died_usec: int = 0
var _bot_events: Array[String] = []
var _victim: PlayerController
var _victim_events: Array[String] = []
var _victim_at_respawn: Dictionary = {}
var _combat_started_usec: int = 0


func _init() -> void:
	# CS2's field of view numbers are horizontal at 4:3; Godot's are vertical.
	_check(
		absf(ViewModelProjection.vertical_fov(90.0) - 73.74) < 0.05
			and absf(ViewModelProjection.vertical_fov(68.0) - 53.64) < 0.05,
		"CS2's fov 90 and viewmodel_fov 68 convert to 73.7 and 53.6 vertical"
	)

	# The locomotion from CS2's own blend spaces (reference/animgraph/
	# locomotion.json), which is in the repository. No assets needed.
	_check(
		PlayerModel.body_speeds(Vector3(0, 0, -250), 0.0).is_equal_approx(Vector2(250, 0))
			and PlayerModel.body_speeds(Vector3(250, 0, 0), 0.0).is_equal_approx(Vector2(0, -250))
			and PlayerModel.body_speeds(Vector3(0, 0, 240), 180.0).is_equal_approx(Vector2(240, 0))
			and PlayerModel.body_speeds(Vector3(-100, 0, 0), 180.0).is_equal_approx(Vector2(0, -100)),
		"a velocity becomes CS2's two speeds: along where the body faces, and to its left"
	)
	var table := PlayerModel.read_locomotion()
	var tree := PlayerModel.build_tree(table, PlayerModel.VARIATION)
	var stand := tree.get_node(&"stand") as AnimationNodeBlendSpace2D if tree != null else null
	var crouch := tree.get_node(&"crouch") as AnimationNodeBlendSpace2D if tree != null else null
	var points := {}
	if stand != null:
		for i in stand.get_blend_point_count():
			points[(stand.get_blend_point_node(i) as AnimationNodeAnimation).animation] = stand.get_blend_point_position(i)
	_check(
		stand != null and stand.get_blend_point_count() == 17 and stand.get_triangle_count() == 24
			and points.get(&"idle", Vector2.ONE) == Vector2.ZERO and points.get(&"run_n", Vector2.ZERO) == Vector2(225, 0)
			and points.get(&"walk_e", Vector2.ZERO) == Vector2(0, -136) and points.get(&"run_nw", Vector2.ZERO) == Vector2(159, 159)
			and crouch != null and crouch.get_blend_point_count() == 9
			and (tree.get_node(&"air_stand") as AnimationNodeBlendSpace2D).get_blend_point_count() == 5,
		"the tree has CS2's blend spaces: the idle, runs at 225 and walks at 136 in its 24 triangles, the crouch's nine, the air's five"
	)
	# CS2's additive clips hold bare differences; Godot adds a clip's
	# difference from the bone's rest, so each key is re-expressed from it.
	var bones := Skeleton3D.new()
	bones.add_bone("spine_0")
	var spine_rest := Transform3D(Basis(Quaternion(Vector3.UP, 0.5)), Vector3(0, 10, 0))
	bones.set_bone_rest(0, spine_rest)
	var bare := Animation.new()
	var turn := bare.add_track(Animation.TYPE_ROTATION_3D)
	bare.track_set_path(turn, NodePath("Rig:spine_0"))
	bare.rotation_track_insert_key(turn, 0.0, Quaternion(Vector3.RIGHT, 0.2))
	var shift := bare.add_track(Animation.TYPE_POSITION_3D)
	bare.track_set_path(shift, NodePath("Rig:spine_0"))
	bare.position_track_insert_key(shift, 0.0, Vector3(1, 0, 0))
	var grow := bare.add_track(Animation.TYPE_SCALE_3D)
	bare.track_set_path(grow, NodePath("Rig:spine_0"))
	bare.scale_track_insert_key(grow, 0.0, Vector3.ZERO)
	var added := PlayerModel.rest_relative(bare, bones)
	_check(
		added.get_track_count() == 2
			and (added.track_get_key_value(0, 0) as Quaternion).is_equal_approx(spine_rest.basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, 0.2))
			and (added.track_get_key_value(1, 0) as Vector3).is_equal_approx(Vector3(1, 10, 0))
			and bare.get_track_count() == 3,
		"an additive clip's keys become the rest times the difference and the rest plus it, its scale offsets dropped, the clip itself untouched"
	)
	bones.free()
	var rings := {}
	var lengths := {"run_n": 0.733, "run_ne": 0.733, "run_e": 0.733, "run_se": 0.733, "run_s": 0.733, "run_sw": 0.733, "run_w": 0.733, "run_nw": 0.733}
	for clip in ["walk_n", "walk_ne", "walk_e", "walk_se", "walk_s", "walk_sw", "walk_w", "walk_nw"]:
		lengths[clip] = 1.0
	for clip in ["crouch_n", "crouch_ne", "crouch_e", "crouch_se", "crouch_s", "crouch_sw", "crouch_w", "crouch_nw"]:
		lengths[clip] = 0.8
	rings[&"stand"] = PlayerModel.cycle_rings(PlayerModel.find_space(table, "/Move/", &"idle", PlayerModel.VARIATION), PlayerModel.VARIATION, lengths)
	rings[&"crouch"] = PlayerModel.cycle_rings(PlayerModel.find_space(table, "/Move/", &"idle_crouch", PlayerModel.VARIATION), PlayerModel.VARIATION, lengths)
	_check(
		is_equal_approx(PlayerModel.cycle_length(rings, 0.0, 0.0), 1.0) and is_equal_approx(PlayerModel.cycle_length(rings, 250.0, 0.0), 0.733)
			and is_equal_approx(PlayerModel.cycle_length(rings, 180.0, 0.0), lerpf(1.0, 0.733, (180.0 - 135.0) / 90.0))
			and is_equal_approx(PlayerModel.cycle_length(rings, 96.0, 1.0), 0.8),
		"a stride lasts the idle's second standing, the walk's 1 s at 136, the run's 0.73 s from 225, between the two in between, the crouch's 0.8 s crouched (%s)" % [rings]
	)

	# The suffix a set's clips share, which comes off their names, and the
	# spare body a weapon's export carries. No assets needed.
	_check(
		RigModel.common_suffix(PackedStringArray(["draw_ak.gltf", "idle_ak.gltf", "reload_ak.gltf"])) == "ak"
			and RigModel.common_suffix(PackedStringArray(["a/draw_glock.vnmclip_c", "a/shoot1_glock.vnmclip_c", "a/idle_glock18.vnmclip_c"])) == "glock"
			and RigModel.common_suffix(PackedStringArray(["draw_default_t.gltf", "light_miss1_default_t.gltf", "idle_default_t.gltf"])) == "default_t"
			and RigModel.common_suffix(PackedStringArray([
				"draw_revolver.gltf", "prepare_shoot_revolver.gltf", "prepare_shoot_revolver.vnmclip+non_additive.gltf",
				"chamber_revolver_0.vnmclip+non_additive.gltf", "chamber_revolver_1.vnmclip+non_additive.gltf",
			])) == "revolver",
		"a set's clips lose the suffix most share: a word (_ak), or more where all share more (the T knife's _default_t), the clips' non-additive copies not counted"
	)
	var legacy := Node.new()
	legacy.name = "weapon_body_legacy"
	var hd := Node.new()
	hd.name = "weapon_body_hd"
	_check(
		RigModel.is_spare_body(legacy, [legacy, hd]) and not RigModel.is_spare_body(hd, [legacy, hd])
			and not RigModel.is_spare_body(legacy, [legacy]),
		"a weapon's old-hardware body is spare beside another, and is the weapon where it is the only one (the default knives)"
	)
	legacy.free()
	hd.free()

	_test_view_model_motion()
	_test_hitbox_set_parsing()
	_test_nm_graph()
	_test_sound_sets()
	_check(
		BulletImpacts.surface_for("physics_group_sand") == "sand" and BulletImpacts.surface_for("physics_group_wood_crate") == "wood"
			and BulletImpacts.surface_for("physics_group_metalvent") == "metal" and BulletImpacts.surface_for("physics_group") == "concrete"
			and BulletImpacts.surface_for("") == "concrete" and BulletImpacts.surface_for("physics_group_glass") == "default",
		"a hull part's name says which impact a round makes on it: sand, wood, metal, concrete, or the general one"
	)
	_test_hole_materials()
	_check(
		GameHud.where_line(Vector3(-780.44, 123.0, -1330.2), -138.0, -32.04) == "pos -780.4 123.0 -1330.2   yaw 222.0   pitch -32.0",
		"the HUD says where you stand and look, yaw from 0 to 360, in the numbers a render is set up from"
	)

	var weapons := _find(WEAPONS_DIR, "weapon_rif_")
	var agents := _find(CHARACTERS_DIR.path_join("agents"), "")
	var clips := _find(CHARACTERS_DIR.path_join("animation/anims"), "")
	if weapons.is_empty() and agents.is_empty():
		print("no weapons or characters have been extracted; only the arithmetic was checked.")
		_report()
		return

	_check(weapons.size() >= 2, "both weapons are there (%d found; scripts/extract_assets.sh weapons)" % weapons.size())
	for path in weapons:
		if path.get_file().ends_with("_mag.gltf"):
			continue
		var scene := _instantiate(path)
		if scene == null:
			continue
		var player := scene.find_children("*", "AnimationPlayer", true, false)
		var animations: PackedStringArray = (player[0] as AnimationPlayer).get_animation_list() if not player.is_empty() else PackedStringArray()
		_check(
			not scene.find_children("*", "Skeleton3D", true, false).is_empty(),
			"%s has a skeleton" % path.get_file()
		)
		_check(
			_has(animations, "shoot") and _has(animations, "reload"),
			"%s has its shoot and reload animations (%s)" % [path.get_file(), ", ".join(animations)]
		)
		scene.free()

	_check(agents.size() >= 2, "both player models are there (%d found; scripts/extract_assets.sh characters)" % agents.size())
	for path in agents:
		var scene := _instantiate(path)
		if scene == null:
			continue
		var skeletons := scene.find_children("*", "Skeleton3D", true, false)
		_check(
			not skeletons.is_empty() and (skeletons[0] as Skeleton3D).get_bone_count() >= 80,
			"%s has a full skeleton (%d bones)" % [path.get_file(), (skeletons[0] as Skeleton3D).get_bone_count() if not skeletons.is_empty() else 0]
		)
		for part in ["firstperson_default_gloves_arms", "firstperson_sleeves", "thirdperson_body"]:
			var found := scene.find_children("*%s*" % part, "MeshInstance3D", true, false)
			_check(
				not found.is_empty() and (found[0] as MeshInstance3D).mesh != null,
				"%s has its %s mesh" % [path.get_file(), part]
			)
		scene.free()

	_check(clips.size() >= 20, "the first-person rifle animations are there (%d found)" % clips.size())
	var checked := 0
	for path in clips:
		if not ("shoot" in path.get_file() or "draw" in path.get_file() or "reload" in path.get_file()):
			continue
		var scene := _instantiate(path)
		if scene == null:
			continue
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		var ok := false
		if not players.is_empty():
			var list := (players[0] as AnimationPlayer).get_animation_list()
			if list.size() == 1:
				var animation := (players[0] as AnimationPlayer).get_animation(list[0])
				# One track per bone of the 69-bone view-model skeleton.
				ok = animation.get_track_count() >= 50 and animation.length > 0.1
		_check(ok, "%s is one animation over the view-model skeleton" % path.get_file())
		scene.free()
		checked += 1
		if checked >= 4:
			break

	# The rest needs frames: the rigs only pose once the tree has processed.
	_view_model = ViewModel.new()
	root.add_child(_view_model)
	var data := WeaponLibrary.ak47()
	_check(_view_model.setup("T", data.model_path, data.clip_set), "the view model builds for the AK-47 and a T")
	ViewModelProjection.claim(_view_model)
	_test_every_gun_builds()
	_test_every_equipment_builds()

	_player_model = PlayerModel.new()
	root.add_child(_player_model)
	_check(_player_model.setup("CT", WeaponLibrary.m4a1s().model_path), "the third-person model builds for the M4A1-S and a CT")


func _process(_delta: float) -> bool:
	_frames += 1
	if _bot != null:
		# The view model's checks are done and freed; the bot's run on.
		return _bot_step()
	if _view_model == null:
		return _frames > 1
	if _frames < 3:
		return false

	var player: AnimationPlayer = _view_model.animation_player
	_check(
		player != null and player.has_animation(&"draw") and player.has_animation(&"idle")
			and player.has_animation(&"shoot1") and player.has_animation(&"reload"),
		"draw, idle, shoot1 and reload are there under their short names"
	)
	_check(
		player != null and player.get_animation(&"idle").loop_mode == Animation.LOOP_LINEAR
			and player.current_animation == &"draw",
		"idle loops, and the draw is what plays first"
	)
	var meshes := _view_model.find_children("*", "MeshInstance3D", true, false)
	var arms := 0
	var weapon := 0
	var on_layer := 0
	for mesh in meshes:
		if mesh.name.contains("firstperson"):
			arms += 1
		if mesh.name.contains("weapon_rif"):
			weapon += 1
		if ViewModelProjection.claimed(mesh as MeshInstance3D) \
				and (mesh as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			on_layer += 1
	_check(arms == 2 and weapon >= 1, "the arm meshes and the weapon are on the rigs (%d arms, %d weapon)" % [arms, weapon])
	_check(
		_view_model.find_children("*empty_mesh_reference", "MeshInstance3D", true, false).is_empty()
			and _player_model.find_children("*empty_mesh_reference", "MeshInstance3D", true, false).is_empty(),
		"the skeletons' placeholder meshes, which drew as white specks on the bones, are gone"
	)
	_check(on_layer == meshes.size(), "and every mesh draws with the view model's projection, casting no shadow")

	var arm_rig: Skeleton3D = _view_model.character_rig
	var weapon_rig: Skeleton3D = _view_model.weapon_rig
	_check(
		arm_rig != null and arm_rig.find_bone("arm_lower_L_TWIST") >= 0
			and arm_rig.get_bone_parent(arm_rig.find_bone("arm_lower_L_TWIST")) == arm_rig.find_bone("arm_lower_L"),
		"a twist bone the rig lacked was added under its parent"
	)
	if arm_rig != null and weapon_rig != null:
		var wpn: Vector3 = (arm_rig.global_transform * arm_rig.get_bone_global_pose(arm_rig.find_bone("wpn"))).origin
		var weapon_root: Vector3 = (weapon_rig.global_transform * weapon_rig.get_bone_global_pose(0)).origin
		_check(
			wpn.distance_to(weapon_root) < 0.01,
			"the weapon's root sits on the wpn bone (%.3f apart)" % wpn.distance_to(weapon_root)
		)
		var muzzle: Vector3 = (weapon_rig.global_transform * weapon_rig.get_bone_global_pose(weapon_rig.find_bone("muzzle"))).origin
		_check(
			muzzle.z < wpn.z - 10.0,
			"and the muzzle is well ahead of it, down the camera's -Z (%.1f)" % (muzzle.z - wpn.z)
		)

	_view_model.play(&"shoot1")
	_check(player.current_animation == &"shoot1", "a shot plays the shoot clip")
	_view_model.play(&"not_a_clip")
	_check(player.current_animation == &"idle", "an unknown clip falls back to idle")
	_view_model.free()
	_view_model = null

	_test_player_model()
	_test_player_composes_kick_and_bob()
	if _bot == null:
		_start_bot()
		return false
	return _bot_step()


## The animation graph reader, on a graph small enough to write out here in
## Source 2 Viewer's text: two parameters, a condition on both, two clips in
## a state machine. No assets needed. Where the graphs have been dumped
## (scripts/extract_assets.sh animgraphs), the real ones as well, and that
## reference/animgraph/locomotion.json is still what they say.
func _test_nm_graph() -> void:
	var parsed: Variant = NmGraph.parse_kv3('{ a = [ 1, -2.5, "x \\"y\\"" ] b = resource:"p/q.vnmclip" c = { d = true e = null } f = [  ] }')
	_check(
		parsed is Dictionary and parsed["a"] == [1, -2.5, "x \"y\""] and parsed["b"] == "p/q.vnmclip"
			and parsed["c"]["d"] == true and parsed["c"]["e"] == null and parsed["f"] == [],
		"KV3 text reads into dictionaries and arrays: numbers, escaped strings, typed strings, flags, null and empty lists (%s)" % [parsed]
	)
	var graph := NmGraph.from_text("""{
	m_nRootNodeIdx = 7
	m_controlParameterIDs = [ "action", "speed" ]
	m_virtualParameterIDs = [  ]
	m_virtualParameterNodeIndices = [  ]
	m_nodePaths = [ "action", "speed", "SM/Idle/Is Reload", "SM/Idle/Fast", "SM/Idle/And", "SM/Idle/idle", "SM/Reload/reload", "SM", "SM/Idle", "SM/Reload", "SM/Idle/To Reload", ]
	m_resources = [ resource:"animation/anims/a/idle_a.vnmclip", resource:"animation/anims/a/reload_a.vnmclip", ]
	m_nodes =
	[
		{ _class = "CNmControlParameterIDNode::CDefinition" m_nNodeIdx = 0 },
		{ _class = "CNmControlParameterFloatNode::CDefinition" m_nNodeIdx = 1 },
		{ _class = "CNmIDComparisonNode::CDefinition" m_nNodeIdx = 2 m_nInputValueNodeIdx = 0 m_comparison = "Matches" m_comparisionIDs = [ "action_reload" ] },
		{ _class = "CNmFloatComparisonNode::CDefinition" m_nNodeIdx = 3 m_nInputValueNodeIdx = 1 m_nComparandValueNodeIdx = -1 m_comparison = "GreaterThanEqual" m_flComparisonValue = 0.5 },
		{ _class = "CNmAndNode::CDefinition" m_nNodeIdx = 4 m_conditionNodeIndices = [ 2, 3 ] },
		{ _class = "CNmClipNode::CDefinition" m_nNodeIdx = 5 m_nDataSlotIdx = 0 m_bAllowLooping = true m_flSpeedMultiplier = 1.0 m_nPlayInReverseValueNodeIdx = -1 },
		{ _class = "CNmClipNode::CDefinition" m_nNodeIdx = 6 m_nDataSlotIdx = 1 m_bAllowLooping = false m_flSpeedMultiplier = 1.0 m_nPlayInReverseValueNodeIdx = -1 },
		{
			_class = "CNmStateMachineNode::CDefinition"
			m_nNodeIdx = 7
			m_nDefaultStateIndex = 0
			m_stateDefinitions =
			[
				{ m_nStateNodeIdx = 8 m_nEntryConditionNodeIdx = -1 m_transitionDefinitions = [ { m_nTargetStateIdx = 1 m_nConditionNodeIdx = 4 m_nTransitionNodeIdx = 10 m_bCanBeForced = false }, ] },
				{ m_nStateNodeIdx = 9 m_nEntryConditionNodeIdx = 2 m_transitionDefinitions = [  ] },
			]
		},
		{ _class = "CNmStateNode::CDefinition" m_nNodeIdx = 8 m_nChildNodeIdx = 5 },
		{ _class = "CNmStateNode::CDefinition" m_nNodeIdx = 9 m_nChildNodeIdx = 6 },
		{ _class = "CNmTransitionNode::CDefinition" m_nNodeIdx = 10 m_nTargetStateNodeIdx = 9 m_nDurationOverrideNodeIdx = -1 m_flDuration = 0.2 m_blendWeightEasing = "OutQuad" m_transitionOptions = { m_flags = 0 } },
	]
}""")
	var states := graph.states(graph.root())
	_check(
		graph.parameters == PackedStringArray(["action", "speed"]) and graph.kind(graph.root()) == "StateMachine"
			and graph.expression(4) == "action is action_reload and speed >= 0.5" and graph.expression(3) == "speed >= 0.5",
		"a graph's conditions read out with its parameters by name (%s)" % graph.expression(4)
	)
	_check(
		states.size() == 2 and states[0]["name"] == "Idle" and states[1]["entry"] == 2
			and (states[0]["transitions"] as Array).size() == 1 and states[0]["transitions"][0]["to"] == 1
			and graph.transition_blend(states[0]["transitions"][0]["node"]) == "0.2 s, OutQuad"
			and graph.summary(states[0]["plays"]) == "clip idle_a (loops)" and graph.summary(states[1]["plays"]) == "clip reload_a",
		"a state machine lists its states, what each plays, and where each goes, when and how fast (%s)" % [states]
	)
	_check(
		graph.id_values() == {"action": PackedStringArray(["action_reload"])}
			and NmGraph.variation_of("animation/graphs/viewmodel/viewmodel_gun.vnmgraph+ak47.vnmgraph_c") == "ak47"
			and NmGraph.variation_of("animation/graphs/worldmodel/worldmodel.vnmgraph_c").is_empty()
			and NmGraph.base_name("animation/graphs/viewmodel/viewmodel_gun.vnmgraph+ak47.vnmgraph_c") == "viewmodel_gun",
		"the values an ID parameter is tested for are collected, and a graph's variation is read off its name"
	)

	var dump := "res://assets/characters/animation/graphs/graph_data.txt"
	if not FileAccess.file_exists(dump):
		print("animation graphs not dumped; skipping the real ones (scripts/extract_assets.sh animgraphs)")
		return
	var blocks := NmGraph.read_dump(dump)
	var world := NmGraph.from_text(String(blocks.get("animation/graphs/worldmodel/worldmodel.vnmgraph_c", "")))
	_check(
		blocks.size() >= 200 and world.parameters.size() >= 40 and "move_speed_x" in world.parameters
			and world.kind(world.root()) == "SnapWeapon" and "flinch_head_north" in (world.id_values().get("flinch_head_type", PackedStringArray()) as PackedStringArray),
		"CS2's graphs read: %d of them; the third-person one takes %d parameters and starts at %s" % [blocks.size(), world.parameters.size(), world.kind(world.root())]
	)
	var locomotion := NmGraph.from_text(String(blocks.get("animation/graphs/worldmodel/worldmodel_locomotion.vnmgraph+rifle.vnmgraph_c", "")))
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://reference/animgraph/locomotion.json"))
	var same := table is Dictionary and not (table["blend_spaces"] as Array).is_empty()
	if same:
		for space: Dictionary in table["blend_spaces"]:
			var values: Array = locomotion.node(int(space["node"])).get("m_values", [])
			var points: Array = space["points"]
			same = same and values.size() == points.size()
			for i in mini(values.size(), points.size()):
				same = same and is_equal_approx(float(values[i][0]), float(points[i]["x"])) and is_equal_approx(float(values[i][1]), float(points[i]["y"]))
	_check(same, "reference/animgraph/locomotion.json is what the graphs say (scripts/animgraph_tables.gd writes it)")


## CS2's hitbox set is text; the test is that the fields come out of it and
## the groups become the zones the weapon data prices. No assets needed.
func _test_hitbox_set_parsing() -> void:
	var text := """
		{
			_class = "HitboxCapsule"
			radius = 4.3
			point0 = [ -1.0, 1.8, 0.0 ]
			point1 = [ 3.5, 0.2, 0.0 ]
			name = "head_0"
			parent_bone = "head_0"
			surface_property = "playerflesh"
			translation_only = false
			group_id = 8
		},
		{
			_class = "HitboxCapsule"
			radius = 3.0
			point0 = [ 0.0, 0.0, 0.0 ]
			point1 = [ -10.0, 0.0, -0.5 ]
			name = "arm_lower_r"
			parent_bone = "arm_lower_r"
			group_id = 5
		},
		{
			_class = "HitboxSphere"
			radius = 1.0
		}
	"""
	var capsules := HitboxSet.parse(text)
	_check(capsules.size() == 2, "two capsules parse out of a set with a sphere in it (%d)" % capsules.size())
	if capsules.size() == 2:
		_check(
			capsules[0]["bone"] == "head_0" and is_equal_approx(capsules[0]["radius"], 4.3)
				and (capsules[0]["point0"] as Vector3).is_equal_approx(Vector3(-1.0, 1.8, 0.0))
				and (capsules[0]["point1"] as Vector3).is_equal_approx(Vector3(3.5, 0.2, 0.0))
				and capsules[0]["zone"] == &"head" and capsules[0]["side"] == &"",
			"the neck's group is priced as the head, with its bone, radius and points"
		)
		_check(
			capsules[1]["zone"] == &"arm" and capsules[1]["side"] == &"right" and capsules[1]["group"] == 5,
			"the right forearm is an arm on the right"
		)
	_check(HitboxSet.parse("nothing here") .is_empty(), "no capsules in text without any")

	var placed := SkinnedHitboxes.capsule_transform(Vector3(0, 10, 0), Vector3(0, 30, 0))
	var slanted := SkinnedHitboxes.capsule_transform(Vector3(0, 0, 0), Vector3(3, 0, 4))
	_check(
		placed.origin.is_equal_approx(Vector3(0, 20, 0)) and placed.basis.y.is_equal_approx(Vector3.UP)
			and slanted.basis.y.is_equal_approx(Vector3(0.6, 0.0, 0.8))
			and slanted.basis.is_equal_approx(slanted.basis.orthonormalized()),
		"a capsule stands between its two points with its own Y along them"
	)
	_check(
		PlayerModel.death_for(&"stomach", 0) == &"death_gut_a"
			and PlayerModel.death_for(&"stomach", 1) == &"death_gut_b"
			and PlayerModel.death_for(&"head", 4) == &"death_chest_a"
			and PlayerModel.death_for(&"arm", 0) == &"death_rshoulder"
			and PlayerModel.death_for(&"leg", 3) == &"death_rknee_b",
		"a death falls the way the last round said, from the game's own pair where it has one"
	)


## The sound bank and the surface mapping; the bank's checks need the
## sounds extracted, the mapping's do not.
func _test_sound_sets() -> void:
	_check(
		Footsteps.set_for("physics_group_sand") == "sand" and Footsteps.set_for("physics_group_wood_plank") == "wood"
			and Footsteps.set_for("physics_group_metalvent") == "metal_vent"
			and Footsteps.set_for("physics_group_solidmetal") == "metal_solid"
			and Footsteps.set_for("physics_group_metal_dumpster") == "metal_solid"
			and Footsteps.set_for("physics_group") == "concrete_ct" and Footsteps.set_for("CollisionShape3D") == "concrete_ct",
		"the hull's material names map to the game's footstep sets, concrete when unknown"
	)
	_check(
		WeaponSounds.set_name_for(WeaponLibrary.ak47().model_path) == "ak47"
			and WeaponSounds.set_name_for(WeaponLibrary.m4a1s().model_path) == "m4a1_silencer"
			and WeaponSounds.SETS.has("ak47") and WeaponSounds.SETS.has("m4a1_silencer"),
		"each weapon's model names its sound set, and both sets are known"
	)
	if not SoundBank.available():
		print("sounds not extracted; skipping the bank's checks (scripts/extract_assets.sh sounds)")
		return
	_check(
		SoundBank.variants("weapons/ak47/ak47_0").size() == 4
			and SoundBank.variants("player/footsteps/sand_").size() == 12
			and SoundBank.variants("player/footsteps/land_concrete").size() == 1
			and SoundBank.variants("player/kevlar").size() >= 5
			and SoundBank.variants("nothing/here_").is_empty(),
		"the bank finds a set's variants by their shared stem: four AK shots, twelve sand steps, one concrete landing"
	)
	var random := SoundBank.randomizer("weapons/ak47/ak47_0")
	_check(
		random != null and random.streams_count == 4 and SoundBank.randomizer("weapons/ak47/ak47_0") == random
			and SoundBank.randomizer("nothing/here_") == null,
		"a set plays through one randomizer, made once, and an empty set has none"
	)
	for part: Array in WeaponSounds.SETS["ak47"]["reload"] + WeaponSounds.SETS["m4a1_silencer"]["reload"]:
		_check(not SoundBank.variants(part[1]).is_empty(), "the reload part %s is there" % part[1])
	var impact_sets := 0
	for surface in BulletImpacts.SOUND_SETS:
		impact_sets += 1 if not SoundBank.variants(BulletImpacts.SOUND_SETS[surface]).is_empty() else 0
	_check(
		impact_sets == BulletImpacts.SOUND_SETS.size() and SoundBank.variants("physics/concrete/concrete_impact_bullet").size() == 7,
		"every impact set is there, seven for concrete (%d of %d)" % [impact_sets, BulletImpacts.SOUND_SETS.size()]
	)


## A bot on a floor, to be shot. The hitboxes are areas, so the physics
## space has to see a frame before a trace finds them.
func _start_bot() -> void:
	_bot_world = Node3D.new()
	root.add_child(_bot_world)
	# Ground, which a round does not go through: 2 units of it did, once
	# rounds went through walls (PR #31), and the round meant to leave a hole
	# in it went on into nothing. Its top is still at 0.
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(1000, 128, 1000)
	ground.add_child(shape)
	ground.position.y = -64.0
	_bot_world.add_child(ground)
	_bot = (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	_bot.team = "CT"
	_bot.weapon_data = WeaponLibrary.ak47()
	_bot.weapon_data.inaccuracy_standing = 0.0
	_bot.weapon_data.inaccuracy_per_shot = 0.0
	_bot.weapon_model = _bot.weapon_data.model_path
	_bot.respawn_seconds = 0.05
	_bot.position = Vector3(0, 0, -200)
	_bot.route = PackedVector3Array([Vector3(0, 0, -200)])
	_bot_world.add_child(_bot)
	_bot.died.connect(func(zone: StringName) -> void:
		_bot_events.append("died:" + zone)
		_bot_died_usec = Time.get_ticks_usec())
	_bot.respawned.connect(func() -> void: _bot_events.append("respawned"))
	_bot_started_frame = _frames
	var impacts := BulletImpacts.new()
	impacts.max_holes = 2
	_bot_world.add_child(impacts)


## A round into the floor leaves a hole and a sound there; the holes are
## recycled past the limit; a round into a person leaves nothing.
## A bullet-hole material as Source 2 Viewer decompiles it, read; and a
## hole's colour darkened by its occlusion.
func _test_hole_materials() -> void:
	var path := "user://hole_fixture/concrete9.vmat"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""// THIS FILE IS AUTO-GENERATED

Layer0
{
	shader "csgo_projected_decals.vfx"
	"g_flCutoffAngle" "60"
	"TextureColor" "materials/decals/concrete/hole_color.png"
	"Compiled Textures"
	{
		"g_tAmbientOcclusion" "materials/decals/concrete/hole_ao_tif_1234abcd.vtex"
		"g_tColor" "materials/decals/concrete/hole_color_psd_5678ef01.vtex"
		"g_tNormal" "materials/decals/concrete/hole_normal_tif_9abc2345.vtex"
	}
	"Attributes"
	{
		"DecalDepth" "10"
		"DecalSizeVariance" "1.25"
		"DecalWorldHeight" "7"
		"DecalWorldWidth" "6"
	}
}
""")
	file.close()
	var hole := BulletImpacts.read_hole(path)
	_check(
		hole.get("color") == "res://assets/decals/materials/decals/concrete/hole_color_psd_5678ef01.png"
			and str(hole.get("occlusion")).ends_with("concrete/hole_ao_tif_1234abcd.png")
			and str(hole.get("normal")).ends_with("concrete/hole_normal_tif_9abc2345.png")
			and hole.get("width") == 6.0 and hole.get("height") == 7.0 and hole.get("variance") == 1.25
			and hole.get("depth") == 10.0 and hole.get("offset") == BulletImpacts.DEFAULT_DEPTH_OFFSET,
		"a bullet-hole material says which compiled texture is which, how big the hole is and how deep it reaches"
	)
	_check(BulletImpacts.read_hole("user://hole_fixture/none.vmat").is_empty(), "and a missing one says nothing")

	var color := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	color.fill(Color(0.8, 0.6, 0.4, 0.5))
	var occlusion := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	occlusion.fill(Color(0.5, 1.0, 1.0))
	var folded := BulletImpacts.occluded(color, occlusion)
	var texel := folded.get_pixel(10, 10)
	_check(
		folded.get_width() == BulletImpacts.MAX_TEXELS and folded.has_mipmaps()
			and absf(texel.r - 0.4) < 0.01 and absf(texel.g - 0.3) < 0.01 and absf(texel.a - 0.5) < 0.01,
		"a hole's colour is darkened by its occlusion's red, its alpha kept, at most %d texels across (%s)" % [BulletImpacts.MAX_TEXELS, texel]
	)


func _test_bullet_impacts() -> void:
	var impacts := _bot_world.get_node_or_null("BulletImpacts") as BulletImpacts
	if impacts == null:
		impacts = _bot_world.get_child(_bot_world.get_child_count() - 1) as BulletImpacts
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(100.0, 64.0, 0.0)
	var space := _bot_world.get_world_3d().direct_space_state
	var angles := PlayerInput.angles_from_direction(Vector3(100.0, 0.0, -100.0) - origin)
	var shot := weapon.fire(0, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	var result := Hitscan.trace(space, shot, data)
	_check(
		result.hit and result.hitbox == null and result.surface == "CollisionShape3D",
		"a round into the floor reports the hull part it met (%s)" % result.surface
	)
	if not DirAccess.dir_exists_absolute(BulletImpacts.DECALS_ROOT):
		print("decals not extracted; skipping the holes (scripts/extract_assets.sh sounds)")
		return
	impacts.mark(result)
	var decals := impacts.find_children("*", "Decal", false, false)
	var hole := decals[0] as Decal if decals.size() == 1 else null
	_check(
		impacts.holes == 1 and hole != null and hole.texture_albedo != null and hole.texture_normal != null
			and hole.global_transform.basis.y.normalized().dot(result.normal) > 0.99
			and (hole.cull_mask & RigModel.LAYER) == 0,
		"and gets a hole there, the game's colour and normal, facing out of the surface, printed on the world and not on people"
	)
	if hole != null:
		# The box reaches 4 units in front of the surface and 8 behind it.
		var along := (result.position - hole.global_position).dot(result.normal)
		_check(
			is_equal_approx(hole.size.y, BulletImpacts.DEFAULT_DEPTH) and absf(along - 2.0) < 0.01
				and hole.size.x >= 2.0 and hole.size.x <= 10.0 and hole.upper_fade == 0.0 and hole.lower_fade == 0.0,
			"projected through a box 12 deep from 4 in front of the surface, a few inches across (%.1f), unfaded" % hole.size.x
		)
	var sky := Hitscan.Result.new()
	sky.hit = true
	sky.surface = "physics_sky"
	sky.normal = Vector3.DOWN
	impacts.mark(sky)
	_check(impacts.holes == 1, "a round into the sky leaves no hole")
	for i in 3:
		shot = weapon.fire((i + 1) * 200_000, 0.0, origin, angles.x + i, angles.y, Weapon.ShooterState.new(0.0, true, false))
		impacts.mark(Hitscan.trace(space, shot, data))
	_check(
		impacts.holes == 4 and impacts.find_children("*", "Decal", false, false).size() == 2,
		"past the limit the oldest holes are reused (%d holes, %d decals)" % [impacts.holes, impacts.find_children("*", "Decal", false, false).size()]
	)
	var person := Hitscan.Result.new()
	person.hit = true
	person.hitbox = _bot.hitboxes.hitboxes[0]
	impacts.mark(person)
	_check(impacts.holes == 4, "a round into a person leaves no hole")


## Returns true when the bot's checks are done. Each step waits for the
## bot to be still: a clip moves the head, and the physics space sees a
## hitbox where it was at the last tick, so a shot is only aimed at a body
## that has settled. Headless frames can outrun the physics ticks, so the
## waits are on the clock and the animation, not the frame count.
func _bot_step() -> bool:
	var since := _frames - _bot_started_frame
	var settled: bool = _bot.model != null and _bot.model.state() == &"idle" \
		and not _bot.model.playing_one_shot()
	match _bot_phase:
		0:
			if since >= 3:
				_test_bot_sounds()
				_test_bullet_impacts()
				_test_bot_wears_hitboxes()
				_test_bot_is_hit_where_aimed()
				_bot_phase = 1
		1:
			if (settled and since >= 6) or since > 4000:
				_test_bot_dies_where_shot()
				_bot_phase = 2
		2:
			if Time.get_ticks_usec() >= _bot_died_usec + 400_000 or since > 8000:
				_test_bot_comes_back()
				_start_combat()
				_bot_phase = 3
		3:
			# Reaction time, then a burst; on the clock, with a limit.
			if _bot.rounds_fired >= 3 or Time.get_ticks_usec() >= _combat_started_usec + 4_000_000:
				_test_bot_shoots_back()
				_bot_phase = 4
		4:
			if _victim_events.has("respawned") or Time.get_ticks_usec() >= _combat_started_usec + 12_000_000:
				_test_victim_dies_and_returns()
				_bot_world.free()
				_report()
				return true
	return false


## A player in front of the bot, in its sight, doing nothing.
func _start_combat() -> void:
	_victim = (load("res://src/player/player.tscn") as PackedScene).instantiate() as PlayerController
	_victim.respawn_seconds = 0.3
	_bot_world.add_child(_victim)
	_victim.place(Vector3(0, 0, 0), 180.0)
	_victim.died.connect(func() -> void:
		_victim_events.append("died")
		# Its body limp and on the floor, and shown to its own camera now.
		var mesh := _victim.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D if _victim.model != null else null
		if _victim.ragdoll != null and _victim.ragdoll.bodies.size() >= 10 and mesh != null and (mesh.layers & _victim.camera.cull_mask) != 0:
			_victim_events.append("ragdoll"))
	_victim.respawned.connect(func() -> void:
		# Its state the instant it is back, before the bot's next burst.
		_victim_events.append("respawned")
		_victim_at_respawn = {
			"alive": _victim.alive, "health": _victim.hit_target.health, "position": _victim.global_position,
			"layer": _victim.hit_target.hitboxes()[0].collision_layer, "ammo": _victim.weapon.ammo,
		})
	_bot.yaw_degrees = 180.0
	_combat_started_usec = Time.get_ticks_usec()
	_check(
		_bot.weapon != null and _bot.weapon_sounds != null and _bot.weapon_sounds.spatial
			and _bot.can_see(_victim) and _victim.hit_target != null and _victim.hit_target.hitboxes().size() > 0,
		"the bot has a weapon that sounds from where it stands, sees the player in front of it, and the player can be hit"
	)
	_check(
		_bot.model != null and not _bot.model.animation_player.has_animation(&"shoot")
			and (_bot.weapon_sounds.get_child(0) as Node3D).global_position.distance_to(_bot.global_position) < 1.0,
		"its body has no whole-body firing clip to fold over with, and its shots sound from the bot itself"
	)
	# The player wears the capsules the bot does, on a body their own camera
	# does not see: the view draws its own.
	var hidden := _victim.model != null and (_victim.camera.cull_mask & PlayerSim.UNSEEN_LAYER) == 0
	if hidden:
		for mesh in _victim.model.find_children("*", "MeshInstance3D", true, false):
			hidden = hidden and (mesh as MeshInstance3D).layers == PlayerSim.UNSEEN_LAYER
	var head_height: float = _victim.hitboxes.hitboxes[0].global_position.y - _victim.global_position.y \
		if _victim.hitboxes != null and not _victim.hitboxes.hitboxes.is_empty() else 0.0
	_check(
		_victim.hit_target.hitboxes().size() == 19 and hidden and head_height > 50.0 and head_height < 72.0,
		"the player wears CS2's nineteen capsules too (%d), on a body their camera leaves out, the head %.0f up (%s)"
			% [_victim.hit_target.hitboxes().size(), head_height, _victim.hitbox_source()]
	)


func _test_bot_shoots_back() -> void:
	_check(
		_bot.target == _victim and _bot.rounds_fired > 0 and _bot.weapon.ammo < _bot.weapon.data.magazine_size,
		"after its reaction time the bot turns on the player and fires (%d rounds)" % _bot.rounds_fired
	)
	_check(
		_victim.hit_target.health < 100.0 or _victim_events.has("died"),
		"and its rounds land: the player's health is %.0f" % _victim.hit_target.health
	)
	_check(
		absf(angle_difference(deg_to_rad(_bot.yaw_degrees), deg_to_rad(180.0))) < deg_to_rad(Bot.FIRE_WITHIN_DEGREES + 1.0),
		"facing the player (yaw %.0f)" % _bot.yaw_degrees
	)


func _test_victim_dies_and_returns() -> void:
	_check(
		_victim_events.has("died"),
		"the player dies to the bot's fire"
	)
	_check(
		_victim_events.has("ragdoll") and _victim.ragdoll == null,
		"its body falls limp as a ragdoll its own camera sees, and gets up with it"
	)
	var back := _victim_at_respawn
	_check(
		_victim_events.has("respawned") and bool(back.get("alive", false))
			and is_equal_approx(float(back.get("health", 0.0)), 100.0)
			and (back.get("position", Vector3.ONE * 99.0) as Vector3).distance_to(Vector3.ZERO) < 4.0
			and int(back.get("layer", 0)) == Hitbox.LAYER
			and int(back.get("ammo", 0)) == _victim.weapon.data.magazine_size,
		"and is back where the map put it, whole and reloaded, to be shot again (%s)" % back
	)


func _test_bot_sounds() -> void:
	var footsteps := _bot.get_node_or_null("Footsteps") as Footsteps
	_check(footsteps != null and footsteps.body == _bot, "the bot has feet that sound")
	if footsteps == null or not SoundBank.available():
		return
	var on_floor := footsteps.surface_below()
	var floor_shape := _bot_world.get_child(0).get_child(0) as CollisionShape3D
	floor_shape.name = "physics_group_sand"
	var on_sand := footsteps.surface_below()
	floor_shape.name = "CollisionShape3D"
	_check(
		on_floor == "concrete_ct" and on_sand == "sand",
		"the surface under its feet is read off the hull part's name (%s, then %s)" % [on_floor, on_sand]
	)
	footsteps.step()
	footsteps.land()
	_check(
		footsteps.steps == 1 and footsteps.landings == 1
			and (footsteps.get_child(0) as AudioStreamPlayer3D).playing,
		"a step and a landing play from the feet"
	)
	# Loaded before they are first played, which hitched: every footstep and
	# landing set, where it has walked on one surface; its gun's shot, reload
	# and hits, and every surface's impacts.
	var wanted := Footsteps.all_sets()
	wanted.append_array(PackedStringArray(BulletImpacts.SOUND_SETS.values()))
	wanted.append_array(PackedStringArray(WeaponSounds.HIT_SETS))
	for part: Array in _bot.weapon_sounds.weapon_set.get("reload", []):
		wanted.append(part[1])
	var missing := PackedStringArray()
	for stem in wanted:
		if not SoundBank._randomizers.has(stem):
			missing.append(stem)
	_check(missing.is_empty(), "every sound set a body, its gun and a round can play is loaded before it is needed (not: %s)" % ", ".join(missing))


func _test_bot_wears_hitboxes() -> void:
	_check(
		_bot.hitboxes != null and _bot.hitboxes.hitboxes.size() == 19,
		"the bot wears CS2's nineteen capsules (%d)" % (_bot.hitboxes.hitboxes.size() if _bot.hitboxes else 0)
	)
	if _bot.hitboxes == null:
		return
	var zones := {}
	var head: Hitbox = null
	for hitbox in _bot.hitboxes.hitboxes:
		zones[hitbox.zone] = zones.get(hitbox.zone, 0) + 1
		if hitbox.name == "Hitbox_head_0":
			head = hitbox
	_check(
		zones.get(&"head", 0) == 2 and zones.get(&"chest", 0) == 3 and zones.get(&"stomach", 0) == 2
			and zones.get(&"arm", 0) == 6 and zones.get(&"leg", 0) == 6,
		"head and neck, three of chest, two of stomach, six each of arm and leg"
	)
	var head_height := head.global_position.y - _bot.global_position.y if head != null else 0.0
	_check(
		head != null and head_height > 58.0 and head_height < 70.0 and head.target == _bot.hit_target,
		"the head capsule rides the head bone, %.1f up, and reports to the bot's target" % head_height
	)
	_check(
		(head.get_child(0) as CollisionShape3D).shape is CapsuleShape3D
			and is_equal_approx(((head.get_child(0) as CollisionShape3D).shape as CapsuleShape3D).radius, 4.3),
		"with the game's own radius"
	)


func _test_bot_is_hit_where_aimed() -> void:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(0.0, 64.0, 0.0)
	var space := _bot_world.get_world_3d().direct_space_state
	var shin: Hitbox = null
	for hitbox in _bot.hitboxes.hitboxes:
		if hitbox.name == "Hitbox_leg_lower_l":
			shin = hitbox
	var angles := PlayerInput.angles_from_direction(shin.global_position - origin)
	var shot := weapon.fire(0, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	var result := Hitscan.fire_at(space, shot, data)
	_check(
		result.hit and result.hitbox != null and result.zone == &"leg"
			and is_equal_approx(result.damage, data.damage_at(result.distance) * data.leg_multiplier)
			and is_equal_approx(_bot.hit_target.health, 100.0 - result.damage) and _bot.alive,
		"a shot at the shin hits a leg capsule ahead of the hull, for three quarters and no armour (%s, %.0f damage, %.0f left)"
			% [result.zone, result.damage, _bot.hit_target.health]
	)
	_check(
		result.hitbox != null and result.hitbox.side == &"left"
			and _bot.hit_target.last_hitbox == result.hitbox
			and _bot.model.state() == &"idle",
		"the target remembers which capsule, on which side, and the body carries on standing"
	)
	# The hull is not what bullets hit: a shot at the hips passes the box and lands on a capsule.
	var hips := _bot.global_position + Vector3(0, 36, 0)
	angles = PlayerInput.angles_from_direction(hips - origin)
	shot = weapon.fire(200_000, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	result = Hitscan.trace(space, shot, data)
	_check(
		result.hit and result.hitbox != null and result.zone in [&"stomach", &"chest", &"arm", &"leg"],
		"a shot at the hips lands on a capsule (%s), not the movement hull" % result.zone
	)


func _test_bot_dies_where_shot() -> void:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(0.0, 64.0, 0.0)
	var space := _bot_world.get_world_3d().direct_space_state
	var head := _bot.hitboxes.hitboxes[0]
	var angles := PlayerInput.angles_from_direction(head.global_position - origin)
	var shot := weapon.fire(0, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	var result := Hitscan.fire_at(space, shot, data)
	_check(
		result.zone == &"head" and result.damage > 100.0 and not _bot.alive and _bot_events.has("died:head"),
		"one round to the head kills through the helmet (%.0f), and it says where it landed" % result.damage
	)
	_check(
		_bot.ragdoll != null and _bot.ragdoll.bodies.size() >= 10 and not _bot.model.is_animating()
			and _bot.collision_layer == 0 and head.collision_layer == 0,
		"dead, it goes limp: a body on each bone with a capsule (%d), the animation off, and neither its hull nor its hitboxes there to hit"
			% (_bot.ragdoll.bodies.size() if _bot.ragdoll != null else 0)
	)
	shot = weapon.fire(300_000, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	_check(not Hitscan.trace(space, shot, data).hit, "a shot at the body now passes through")


func _test_bot_comes_back() -> void:
	_check(
		_bot.alive and _bot_events.has("respawned") and is_equal_approx(_bot.hit_target.health, 100.0)
			and _bot.collision_layer == 2 and _bot.hitboxes.hitboxes[0].collision_layer == Hitbox.LAYER
			and _bot.global_position.distance_to(Vector3(0, 0, -200)) < 2.0
			and _bot.ragdoll == null and _bot.model.is_animating()
			and _bot.model.state() == &"idle",
		"after its respawn time it is back at the start of its route, whole, standing, the ragdoll gone (%s)"
			% [_bot.model.state()]
	)


## The controller writes the weapon model's whole transform every frame:
## the bob and sway in the camera's frame, the recoil kick in the model's.
## Standing still and looking steadily, that must leave the kick exactly as
## the weapon gives it, or the recoil work would be undone here.
func _test_player_composes_kick_and_bob() -> void:
	var player := (load("res://src/player/player.tscn") as PackedScene).instantiate() as PlayerController
	root.add_child(player)
	if player.view_model == null:
		_check(false, "the player builds its view model")
		player.free()
		return
	_check(player.body_model != null and player.body_model.character_rig != null, "the player builds its own body")
	_check(
		player.weapon_sounds != null and player.footsteps != null
			and (not SoundBank.available() or player.weapon_sounds.weapon_set.has("fire")),
		"and its weapon and footstep sounds, the AK's set taken up on equip"
	)
	if SoundBank.available():
		player.weapon_sounds.shot()
		_check(
			(player.weapon_sounds.get_child(0) as AudioStreamPlayer).playing
				and (player.weapon_sounds.get_child(0) as AudioStreamPlayer).stream is AudioStreamRandomizer,
			"a shot plays one of the AK's four through the randomizer"
		)
	if player.body_model != null:
		var rig: Skeleton3D = player.body_model.character_rig
		_check(
			rig.get_bone_pose_scale(rig.find_bone("head_0")).is_equal_approx(Vector3.ONE * RigModel.FOLDED)
				and rig.get_bone_pose_scale(rig.find_bone("arm_upper_R")).is_equal_approx(Vector3.ONE * RigModel.FOLDED)
				and rig.get_bone_pose_scale(rig.find_bone("pelvis")).is_equal_approx(Vector3.ONE),
			"with its head and arms folded and the rest whole"
		)
		var shadow_rig: Skeleton3D = player.body_shadow.character_rig if player.body_shadow != null else null
		var body_casting := 0
		for mesh in player.body_model.find_children("*", "MeshInstance3D", true, false):
			if (mesh as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				body_casting += 1
		var shadow_only := 0
		var shadow_meshes := player.body_shadow.find_children("*", "MeshInstance3D", true, false) if player.body_shadow != null else []
		for mesh in shadow_meshes:
			if (mesh as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				shadow_only += 1
		_check(
			shadow_rig != null and body_casting == 0 and not shadow_meshes.is_empty() and shadow_only == shadow_meshes.size()
				and shadow_rig.get_bone_pose_scale(shadow_rig.find_bone("head_0")).is_equal_approx(Vector3.ONE)
				and shadow_rig.get_bone_pose_scale(shadow_rig.find_bone("arm_upper_R")).is_equal_approx(Vector3.ONE * RigModel.FOLDED),
			"and its shadow is cast by a twin drawn only into the shadow maps, with its head and without its arms"
		)
		player.view._process(1.0 / 60.0)
		_check(
			player.body_shadow != null and player.body_shadow.global_position.is_equal_approx(player.body_model.global_position)
				and player.body_shadow.state() == player.body_model.state()
				and player.body_shadow.animation_tree.get("parameters/stand/blend_position") == player.body_model.animation_tree.get("parameters/stand/blend_position"),
			"the twin stands where the body stands, moving as it moves"
		)

	# Frame one captures the rest pose; then a kick from a real shot.
	player.velocity = Vector3.ZERO
	player.on_ground = true
	player.view._update_viewmodel(1.0 / 60.0)
	var rest := player.view_model.transform
	var now := Time.get_ticks_usec()
	player.weapon.fire(now, 0.5, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new())
	player.weapon.update(SimClock.tick_seconds(), now + SimClock.tick_usec())
	var kick := player.weapon.viewmodel_punch()
	# The same over the last two ticks, so a frame between them, which is
	# where the view draws the kick, shows it exactly.
	player.previous_viewmodel_punch = kick
	player.view._update_viewmodel(1.0 / 60.0)
	var expected := rest.basis * Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0))
	_check(
		kick.length() > 0.01 and player.view_model.transform.basis.is_equal_approx(expected)
			and player.view_model.transform.origin.is_equal_approx(rest.origin),
		"standing still, a round's kick reaches the weapon model exactly as the weapon gives it (%.2f, %.2f degrees)" % [kick.x, kick.y]
	)

	# Running: the same kick, on top of the bob's offset.
	player.velocity = Vector3(0.0, 0.0, -250.0)
	player.previous_viewmodel_punch = player.weapon.viewmodel_punch()
	for frame in 20:
		player.view._update_viewmodel(1.0 / 60.0)
	kick = player.weapon.viewmodel_punch()
	var moved := player.view_model.transform
	var motion_only := player.view.viewmodel_motion.update(0.0, Vector3(0.0, 0.0, -250.0), true, Vector2.ZERO)
	_check(
		not moved.origin.is_equal_approx(rest.origin)
			and moved.basis.is_equal_approx(
				motion_only.basis * rest.basis * Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0))
			),
		"running, the bob moves the model and the kick still sits inside it"
	)
	player.free()


## The bob and sway need no assets: a clock, a speed and a look.
## Every gun in reference/weapons/models.md builds into the first-person view
## model from what the extraction wrote: the model on its own clip set (a
## pistol's under pistol/), a draw, a reload, a firing clip and an idle to
## rest on, the gun on its own rig, and nothing but the gun and the arms (the
## Dual Berettas' thigh holster is third-person only).
func _test_every_gun_builds() -> void:
	var guns: Array = (load("res://scripts/weapon_tables.gd") as GDScript).get_script_constant_map()["GUNS"]
	var built := 0
	var failures := PackedStringArray()
	for gun in guns:
		var dir := "res://assets/weapons/weapons/models".path_join(gun[2])
		var model := ""
		for file in DirAccess.get_files_at(dir):
			var stem := file.get_basename()
			if file.get_extension() == "gltf" and stem.begins_with("weapon_") and not stem.ends_with("_mag") and not stem.ends_with("_physics"):
				model = dir.path_join(file)
		if model.is_empty():
			continue
		var view_model := ViewModel.new()
		root.add_child(view_model)
		var ok := view_model.setup("T", model, gun[3])
		var clips := view_model.animation_player.get_animation_list() if view_model.animation_player != null else PackedStringArray()
		var fires := view_model.shoot_clips.size() > 0 or clips.has(&"shoot_right1")
		var holstered := not view_model.find_children("*eholster", "MeshInstance3D", true, false).is_empty()
		if not ok or view_model.weapon_rig == null or not clips.has(&"draw") or not clips.has(&"reload") \
				or not fires or not clips.has(view_model.idle) or holstered:
			failures.append("%s (%s: %s)" % [gun[0], gun[3], ", ".join(clips)])
		built += 1
		view_model.free()
	if built == 0:
		print("no guns extracted; skipping the every-gun build (scripts/extract_assets.sh weapons)")
		return
	_check(
		built == guns.size() and failures.is_empty(),
		"every gun builds in first person on its own clips, %d of %d (%s)" % [built - failures.size(), guns.size(), "; ".join(failures)]
	)


## And every piece of equipment in reference/weapons/equipment.md, the same
## way: its model on its own clip set, a draw, an idle and what it is for (the
## plant, a stab, the Zeus's shot, a throw), with a mesh on the weapon's rig.
## The default knives' one mesh is the body the guns carry a spare of; they
## keep it, in the third-person model's hand too. The kit, which no one holds,
## has only to load.
func _test_every_equipment_builds() -> void:
	var items: Array = (load("res://scripts/weapon_tables.gd") as GDScript).get_script_constant_map()["EQUIPMENT"]
	var actions := {"weapon_c4": &"plant", "weapon_knife": &"light_miss1", "weapon_knife_t": &"light_miss1", "weapon_taser": &"shoot1"}
	var built := 0
	var failures := PackedStringArray()
	var knife := ""
	for item in items:
		var model := "res://assets/weapons/weapons/models".path_join(String(item[2]) + ".gltf")
		if not ResourceLoader.exists(model):
			continue
		built += 1
		if String(item[3]).is_empty():
			var scene := _instantiate(model)
			if scene == null or scene.find_children("*", "MeshInstance3D", true, false).is_empty():
				failures.append("%s (%s has no mesh)" % [item[0], model.get_file()])
			if scene != null:
				scene.free()
			continue
		var view_model := ViewModel.new()
		root.add_child(view_model)
		var ok := view_model.setup("CT", model, item[3])
		var clips := view_model.animation_player.get_animation_list() if view_model.animation_player != null else PackedStringArray()
		var action: StringName = actions.get(item[0], &"throw_overhand")
		var meshes: Array = view_model.weapon_rig.get_parent().find_children("*", "MeshInstance3D", true, false) if view_model.weapon_rig != null else []
		if not ok or meshes.is_empty() or not clips.has(&"draw") or not clips.has(view_model.idle) or not clips.has(action):
			failures.append("%s (%s: %d meshes; %s)" % [item[0], item[3], meshes.size(), ", ".join(clips)])
		if item[0] == "weapon_knife":
			knife = model
		view_model.free()
	if built == 0:
		print("no equipment extracted; skipping the every-equipment build (scripts/extract_assets.sh equipment)")
		return
	_check(
		built == items.size() and failures.is_empty(),
		"every piece of equipment builds in first person on its own clips, %d of %d (%s)" % [built - failures.size(), items.size(), "; ".join(failures)]
	)
	if knife.is_empty():
		return
	var body := PlayerModel.new()
	root.add_child(body)
	var held := body.setup("CT", knife)
	var shown := 0
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		if mesh.name.contains("knife") and (mesh as MeshInstance3D).visible:
			shown += 1
	_check(held and shown == 1, "the third-person model holds the knife, its one mesh shown (%d)" % shown)
	body.free()


func _test_view_model_motion() -> void:
	_check(
		ViewModelMotion.bob_at(0.37, 0.0) == Vector2.ZERO
			and ViewModelMotion.bob_at(0.0, 320.0).is_equal_approx(Vector2(0.96 * 0.3, 1.6 * 0.3)),
		"standing still there is no bob; at full speed it starts at three tenths of its amounts"
	)
	var peak := ViewModelMotion.bob_at(ViewModelMotion.BOB_CYCLE * ViewModelMotion.BOB_UP * 0.5, 320.0)
	var trough := ViewModelMotion.bob_at(ViewModelMotion.BOB_CYCLE * (ViewModelMotion.BOB_UP + (1.0 - ViewModelMotion.BOB_UP) * 0.5), 320.0)
	_check(
		is_equal_approx(peak.x, 0.96) and is_equal_approx(trough.x, -0.96 * 0.4)
			and is_equal_approx(peak.y, 1.6 * 0.3 + 1.6 * 0.7 * sin(PI * 0.25)),
		"the vertical bob peaks a quarter cycle in and troughs at three quarters; the lateral runs at half the rate"
	)

	var motion := ViewModelMotion.new()
	var still := motion.update(1.0 / 60.0, Vector3.ZERO, true, Vector2(90.0, 0.0))
	_check(
		still.origin.is_zero_approx() and still.basis.is_equal_approx(Basis.IDENTITY),
		"standing still and looking steadily, the weapon is where the clip put it"
	)
	var running := Transform3D.IDENTITY
	for frame in 30:
		running = motion.update(1.0 / 60.0, Vector3(0.0, 0.0, -250.0), true, Vector2(90.0, 0.0))
	_check(
		running.origin.z > 1.0 and running.origin.y < 0.0 and absf(running.origin.x) <= 1.6 * 0.8 + 0.001,
		"running settles the weapon back and down, and bobs it sideways within its amount (%s)" % running.origin
	)
	var airborne := motion.update(1.0 / 60.0, Vector3(0.0, 0.0, -250.0), false, Vector2(90.0, 0.0))
	_check(
		is_zero_approx(motion.vertical_bob) and airborne.origin.z < 0.001,
		"in the air there is no bob and nothing to settle"
	)
	var turned := motion.update(1.0 / 60.0, Vector3.ZERO, true, Vector2(95.0, 0.0))
	_check(
		motion.sway.x < 0.0 and motion.sway.x >= -ViewModelMotion.SWAY_MAX
			and turned.basis.get_euler().y < 0.0,
		"turning left, the weapon lags to the right, within its limit (%.2f degrees)" % motion.sway.x
	)
	for frame in 120:
		motion.update(1.0 / 60.0, Vector3.ZERO, true, Vector2(95.0, 0.0))
	_check(absf(motion.sway.x) < 0.01, "and settles back once the turn stops")


func _test_player_model() -> void:
	var model := _player_model
	if model == null:
		return
	var animations := model.animation_player
	_check(
		animations != null and animations.has_animation(&"run_n") and animations.has_animation(&"walk_sw")
			and animations.has_animation(&"crouch_e") and animations.has_animation(&"idle")
			and animations.has_animation(&"inair_stand"),
		"the eight-way run, walk and crouch clips, the idles and the in-air clip are there"
	)
	var body := model.find_children("*thirdperson_body", "MeshInstance3D", true, false)
	var arms := model.find_children("*firstperson*", "MeshInstance3D", true, false)
	_check(not body.is_empty() and arms.is_empty(), "the third-person body is on the rig and the first-person arms are not")
	var off_layer := 0
	var all_meshes := model.find_children("*", "MeshInstance3D", true, false).filter(
		func(mesh: Node) -> bool: return mesh.name.contains("thirdperson") or mesh.name.contains("weapon_")
	)
	for mesh in all_meshes:
		if (mesh as MeshInstance3D).layers != RigModel.LAYER:
			off_layer += 1
	_check(
		all_meshes.size() > 2 and off_layer == 0,
		"the body and its weapon are drawn on the people's layer, where the bullet holes do not print (%d of %d off it)" % [off_layer, all_meshes.size()]
	)
	var rig: Skeleton3D = model.character_rig
	_check(
		rig != null and rig.find_bone("arm_lower_R_TWIST") >= 0,
		"the twist bones the body is skinned to were added to the rig"
	)
	var weapon_root: Node3D = null
	for child in rig.get_parent().get_children():
		if child.name.contains("weapon_rif"):
			weapon_root = child
	var skeleton: Skeleton3D = weapon_root.find_children("*", "Skeleton3D", true, false)[0] if weapon_root != null else null
	if rig != null and skeleton != null:
		var wpn: Vector3 = (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("wpn"))).origin
		var weapon_at: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(0)).origin
		_check(wpn.distance_to(weapon_at) < 0.01, "the weapon's root bone sits on the hand's wpn bone (%.3f apart)" % wpn.distance_to(weapon_at))
	var head: Vector3 = (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("head_0"))).origin
	_check(
		head.y > 60.0 and head.y < 72.0 and (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("root_motion"))).origin.y < 0.5,
		"the model stands on its origin with its head about five and a half feet up (%.1f)" % head.y
	)

	# Facing +Z at yaw 180 (the game's forward is -Z at yaw 0), running forward.
	var tree := model.animation_tree
	var ankle := rig.find_bone("ankle_L")
	model.update_motion(Vector3(0, 0, 240), 180.0, 0.0, true)
	tree.advance(0.1)
	var stride_start := (rig.global_transform * rig.get_bone_global_pose(ankle)).origin
	tree.advance(0.2)
	var stride := (rig.global_transform * rig.get_bone_global_pose(ankle)).origin.distance_to(stride_start)
	_check(
		tree != null and tree.active and not animations.active and model.state() == &"move"
			and (tree.get("parameters/stand/blend_position") as Vector2).is_equal_approx(Vector2(240, 0))
			and is_zero_approx(float(tree.get("parameters/move/blend_amount")))
			and is_equal_approx(float(tree.get("parameters/cycle/scale")), 1.0 / animations.get_animation(&"run_n").length)
			and stride > 1.0,
		"running forward at 240, the tree is at (240, 0) in CS2's standing space, a stride each run cycle, and the feet move (%s, %.2f, %.1f units)"
			% [tree.get("parameters/stand/blend_position"), float(tree.get("parameters/cycle/scale")), stride]
	)
	model.update_motion(Vector3(0, 0, 180), 180.0, 0.0, true)
	tree.advance(1.3)
	var run_at := float(tree.get("parameters/stand/run_n/current_position"))
	var walk_at := float(tree.get("parameters/stand/walk_n/current_position"))
	_check(
		absf(run_at - walk_at) < 0.001,
		"between a walk and a run, the 0.73 s run and the 1 s walk stay at the same point of the stride, as CS2 syncs them (%.3f, %.3f)" % [run_at, walk_at]
	)
	model.update_motion(Vector3(-100, 0, 0), 180.0, 0.5, true)
	_check(
		(tree.get("parameters/stand/blend_position") as Vector2).is_equal_approx(Vector2(0, -100))
			and (tree.get("parameters/crouch/blend_position") as Vector2).is_equal_approx(Vector2(0, -100))
			and is_equal_approx(float(tree.get("parameters/move/blend_amount")), 0.5),
		"sidestepping to the right half crouched, the standing and crouched spaces are both at (0, -100) and mixed half and half"
	)
	model.update_motion(Vector3(0, 0, 240), 180.0, 0.0, false)
	model.pose_now()
	_check(
		model.state() == &"air" and tree.get("parameters/ground/current_state") == "air"
			and is_equal_approx(((tree.tree_root as AnimationNodeBlendTree).get_node(&"ground") as AnimationNodeTransition).xfade_time, PlayerModel.TO_AIR),
		"off the ground, it cross-fades to the air in CS2's 0.1 s"
	)
	model.play(&"death_chest_a", 0.05)
	model.update_motion(Vector3(0, 0, 240), 180.0, 0.0, true)
	model.pose_now()
	_check(
		model.state() == &"death_chest_a" and model.playing_one_shot() and tree.get("parameters/death/current_state") == "dead",
		"a death blends in over the top and is held, whatever the body does after (%s)" % model.state()
	)
	model.play(model.idle)
	model.pose_now()
	_check(
		not model.playing_one_shot() and tree.get("parameters/death/current_state") == "alive",
		"and the idle ends it, as when the body gets up"
	)

	_test_weapon_layers()
	_test_bodies_share_what_they_read()

	# The first-person body: the head and arms folded away, and staying so
	# under the clips, which animate every bone's scale.
	model.update_motion(Vector3.ZERO, 180.0, 0.0, true)
	model.fold_bones(PackedStringArray(["head_0", "arm_upper_L"]))
	tree.advance(0.25)
	var folded_head := rig.get_bone_pose_scale(rig.find_bone("head_0"))
	var idle: Animation = animations.get_animation(&"idle")
	var head_scale_tracks := 0
	var head_tracks := 0
	for track in idle.get_track_count():
		if String(idle.track_get_path(track).get_subname(0)) == "head_0":
			head_tracks += 1
			head_scale_tracks += 1 if idle.track_get_type(track) == Animation.TYPE_SCALE_3D else 0
	_check(
		folded_head.is_equal_approx(Vector3.ONE * RigModel.FOLDED)
			and head_scale_tracks == 0 and head_tracks > 0
			and model.state() == &"idle" and model.is_animating(),
		"folding a bone shrinks it to nothing and takes its scale track, and only that, out of the clips, which keep playing"
	)
	model.free()
	_player_model = null


## A body is built from what the bodies before it read: a second one loads
## no scene the first did not (each body read about eighty from the disk,
## and at half time everyone's body is built again). What the caches hand
## out are copies, so a caller changing one changes nothing for the next.
func _test_bodies_share_what_they_read() -> void:
	var ak := WeaponLibrary.ak47()
	var first := PlayerModel.new()
	root.add_child(first)
	first.setup("T", ak.model_path, ak.world_clip_set)
	var scenes_read: int = RigModel._scenes.size()
	var second := PlayerModel.new()
	root.add_child(second)
	var built := second.setup("T", ak.model_path, ak.world_clip_set)
	_check(
		built and RigModel._scenes.size() == scenes_read and scenes_read > 50
			and second.animation_player.get_animation_list().size() == first.animation_player.get_animation_list().size(),
		"a second body loads no scene the first did not (%d read, %d after the second)" % [scenes_read, RigModel._scenes.size()]
	)
	var clip := RigModel.list_clips(PlayerModel.CLIPS_DIR)[0]
	var listed := RigModel.list_clips(PlayerModel.CLIPS_DIR)
	listed.append("not a clip")
	var capsules := HitboxSet.load_for(PlayerModel.AGENTS["T"])
	capsules.clear()
	var table := PlayerModel.read_locomotion()
	table.clear()
	_check(
		RigModel.list_clips(PlayerModel.CLIPS_DIR).size() == listed.size() - 1
			and HitboxSet.load_for(PlayerModel.AGENTS["T"]).size() == 19
			and not PlayerModel.read_locomotion().is_empty()
			and is_same(RigModel.clip_animation(clip), RigModel.clip_animation(clip)),
		"the clips listed, the capsules and the locomotion table are handed out as copies, and a clip's animation is the same one each time"
	)
	first.free()
	second.free()


## A body holding the AK-47 with its own third-person clips: the gun's hold
## over the locomotion, each shot kicking the upper body and leaving the legs,
## the reload over the upper body while the legs run on under it.
func _test_weapon_layers() -> void:
	var ak := WeaponLibrary.ak47()
	var model := PlayerModel.new()
	root.add_child(model)
	if not model.setup("T", ak.model_path, ak.world_clip_set) or not model.has_weapon_layers:
		_check(false, "the AK-47's own third-person clips load (%s)" % ak.world_clip_set)
		model.free()
		return
	var tree := model.animation_tree
	var rig := model.character_rig
	var at := func(bone_name: String) -> Vector3:
		return (rig.global_transform * rig.get_bone_global_pose(rig.find_bone(bone_name))).origin
	var upper := {}
	for track in model.upper_body_tracks():
		upper[String(track.get_subname(0))] = true
	_check(
		model.animation_player.has_animation(&"weapon_shoot") and model.animation_player.has_animation(&"weapon_reload")
			and model.animation_player.has_animation(&"weapon_draw") and model.animation_player.has_animation(&"weapon_idle_crouch")
			and upper.has("spine_0") and upper.has("hand_R") and upper.has("head_0") and upper.has("wpn")
			and not upper.has("pelvis") and not upper.has("ankle_L") and not upper.has("leg_upper_R"),
		"the AK-47's hold, shot, reload and draw are loaded, and CS2's upper body is the spine up and the gun's bones, not the hips or legs"
	)
	model.pose_now()
	tree.advance(0.5)
	var hand: Vector3 = at.call("hand_R")
	var ankle: Vector3 = at.call("ankle_L")
	tree.set("parameters/hold/add_amount", 0.0)
	tree.advance(0.0)
	var unheld: float = (at.call("hand_R") as Vector3).distance_to(hand)
	tree.set("parameters/hold/add_amount", 1.0)
	tree.advance(0.0)
	_check(
		unheld > 0.3 and unheld < 3.0 and (at.call("hand_R") as Vector3).distance_to(hand) < 0.001,
		"the gun's own hold moves the hands a little from the rifle locomotion's (%.2f units), not off the body" % unheld
	)
	model.fire()
	for step in 4:
		tree.advance(0.05)
	var kicked: float = (at.call("hand_R") as Vector3).distance_to(hand)
	var legs: float = (at.call("ankle_L") as Vector3).distance_to(ankle)
	_check(
		bool(tree.get("parameters/shoot/active")) and kicked > 0.5 and legs < 0.001,
		"a shot kicks the upper body (the hand %.1f units at 0.2 s) and leaves the legs where they were" % kicked
	)
	for step in 14:
		tree.advance(0.05)
	_check(
		not bool(tree.get("parameters/shoot/active")) and (at.call("hand_R") as Vector3).distance_to(hand) < 0.05,
		"and it is over with the clip, the hands back in the hold"
	)
	model.play(&"reload", 0.1)
	var furthest := 0.0
	for step in 20:
		tree.advance(0.05)
		furthest = maxf(furthest, (at.call("hand_R") as Vector3).distance_to(hand))
	_check(
		bool(tree.get("parameters/gun_action/active")) and furthest > 2.0 and (at.call("ankle_L") as Vector3).distance_to(ankle) < 0.001,
		"a reload plays the gun's own over the upper body (the hand as far as %.1f units in its first second), the legs untouched" % furthest
	)
	model.update_motion(Vector3(0, 0, 225), 180.0, 0.0, true)
	tree.advance(0.1)
	var stride_from: Vector3 = at.call("ankle_L")
	tree.advance(0.2)
	_check(
		bool(tree.get("parameters/gun_action/active")) and (at.call("ankle_L") as Vector3).distance_to(stride_from) > 1.0,
		"and running meanwhile, the legs run on under the reload"
	)
	model.free()


func _find(dir_path: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".gltf") and not file.ends_with("_physics.gltf") and file.begins_with(prefix):
			out.append(dir_path.path_join(file))
	for subdirectory in dir.get_directories():
		out.append_array(_find(dir_path.path_join(subdirectory), prefix))
	return out


func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	_check(packed != null, "%s imports as a scene" % path.get_file())
	if packed == null:
		return null
	return packed.instantiate()


func _has(names: PackedStringArray, fragment: String) -> bool:
	for name in names:
		if name.contains(fragment):
			return true
	return false


func _report() -> void:
	_finish("model")
