class_name BuyMenuAgent
extends SubViewport

## Your agent beside the buy menu, as CS2 stands it there. buymenu.xml's
## MapPlayerPreviewPanel lies under the whole menu, full screen, and draws
## CS2's ui/buy_menu map through that map's camera, with the game behind
## (game-background). In it stands your agent (the map's vanity_character),
## in the pose CS2's UI graph gives the item in hand or under the mouse, and
## holding that item (Sid's screenshots of CS2's menu, 2026-09-25: the AK-47
## in the agent's hands while the mouse is over it).
##
## The map's numbers are as its entity lump has them (maps/ui/buy_menu.vpk,
## maps/ui/buy_menu/entities/default_ents.vents, decompiled with Source 2
## Viewer's -d): cam_buymenu, a point_camera_vertical_fov; the agent's place
## and yaw; its one light_environment. The panel pins the camera's field of
## view to its height (pin-fov="vertical"), so the camera sees 30 degrees from
## the top of the screen to the bottom whatever the screen's shape, and the
## agent stands where it does in CS2 at any size.
##
## The poses are CS2's own (animation/anims/ui_anims/buy_menu, one frame
## each), chosen as the graph's BuyMenu state chooses them
## (animation/graphs/ui/uimodel.vnmgraph: its CT and T state machines, each
## item's state entered on its weapon_type, every transition 0 s, so a pose
## snaps to the next); the state adds a breath over them (t_idle_layer01, an
## additive layer, both sides). The item is pinned to the hand's wpn bone,
## as a player's is (PlayerModel.attach_weapon).
##
## A world of its own, drawn into this viewport only while the menu is open,
## and animated only then. The viewport covers part of the screen (the menu
## sets which, frame()), and its camera sees that part of the full-screen
## view, off centre, as the map's camera would.

## The map's camera, cam_buymenu: where it is (Source units) and its yaw; it
## looks level, and its field of view is vertical, over the whole screen.
const CAMERA_AT := Vector3(-60.0, -136.0, 28.0)
const CAMERA_YAW := 90.0
const FOV := 30.0
const NEAR := 4.0
const FAR := 10000.0
## Where the map stands the agent (its feet), and which way it faces.
const AGENT_AT := Vector3(-27.141846, 16.045654, -22.297701)
const AGENT_YAW := 255.000046
## The map's light_environment: how bright, what colour, which way it
## shines (pitch, yaw, roll), and its sky's colour and the colour of the
## light it bounces.
const SUN_BRIGHTNESS := 2.3
const SUN_COLOUR := Color8(245, 238, 232)
const SUN_ANGLES := Vector3(54.179226, 87.803261, -0.249165)
const SKY_COLOUR := Color8(211, 226, 248)
const SKY_BOUNCE := Color8(151, 151, 151)

const POSES_DIR := "res://assets/characters/animation/anims/ui_anims/buy_menu"
const BREATH := "res://assets/characters/animation/anims/ui_anims/additive_anims/t/t_idle_layer01.gltf"
## The pose each item strikes, as the graph gives it: the CT pose and the T
## pose, or one both sides share. The graph's M4A4 state plays the CT's
## M4A1-S pose (ct_buymenu_m4a4 is in the files, and unused), and its knife
## state takes every knife but the Shadow Daggers; kevlar_vest and
## kevlar_and_helmet share the armour's, and weapon_defuse_kit is the kit.
const POSES := {
	"weapon_glock": ["ct/ct_buymenu_glock18", "t/t_buymenu_glock18_03"],
	"weapon_hkp2000": ["ct/ct_buymenu_hkp2000", "t/t_buymenu_hkp2000"],
	"weapon_usp_silencer": ["ct/ct_buymenu_usp_silencer", "t/t_buymenu_usp_silencer"],
	"weapon_elite": ["ct/ct_buymenu_elite", "t/t_buymenu_elite"],
	"weapon_p250": ["ct/ct_buymenu_p250", "t/t_buymenu_p250_03"],
	"weapon_tec9": ["ct/ct_buymenu_tec9", "t/t_buymenu_tec9_03"],
	"weapon_fiveseven": ["ct/ct_buymenu_fiveseven", "t/t_buymenu_fiveseven"],
	"weapon_cz75a": ["ct/ct_buymenu_cz75", "t/t_buymenu_cz75"],
	"weapon_deagle": ["ct/ct_buymenu_deagle", "t/t_buymenu_deagle_03"],
	"weapon_revolver": ["ct/ct_buymenu_revolver", "t/t_buymenu_revolver_03"],
	"weapon_taser": ["ct/ct_buymenu_taser", "t/t_buymenu_taser"],
	"weapon_mac10": ["ct/ct_buymenu_mac10", "t/t_buymenu_mac10_03"],
	"weapon_mp9": ["ct/ct_buymenu_mp9", "t/t_buymenu_mp9_03"],
	"weapon_mp7": ["ct/ct_buymenu_mp7", "t/t_buymenu_mp7_03"],
	"weapon_mp5sd": ["ct/ct_buymenu_mp5sd", "t/t_buymenu_mp5sd_03"],
	"weapon_ump45": ["ct/ct_buymenu_ump45", "t/t_buymenu_ump45_03"],
	"weapon_p90": ["ct/ct_buymenu_p90", "t/t_buymenu_p90_03"],
	"weapon_bizon": ["ct/ct_buymenu_bizon", "t/t_buymenu_bizon_03"],
	"weapon_nova": ["ct/ct_buymenu_nova_03", "t/t_buymenu_nova_02"],
	"weapon_xm1014": ["ct/ct_buymenu_xm1014", "t/t_buymenu_xm1014_02"],
	"weapon_sawedoff": ["ct/ct_buymenu_sawedoff", "t/t_buymenu_sawedoff_02"],
	"weapon_mag7": ["ct/ct_buymenu_mag7_03", "t/t_buymenu_mag7_02"],
	"weapon_m249": ["ct/ct_buymenu_m249_03", "t/t_buymenu_m249_02"],
	"weapon_negev": ["ct/ct_buymenu_negev_03", "t/t_buymenu_negev_02"],
	"weapon_galilar": ["ct/ct_buymenu_galilar", "t/t_buymenu_galilar_03"],
	"weapon_famas": ["ct/ct_buymenu_famas", "t/t_buymenu_famas"],
	"weapon_ak47": ["ct/ct_buymenu_ak", "t/t_buymenu_ak_03"],
	"weapon_m4a1": ["ct/ct_buymenu_m4a1", "t/t_buymenu_m4a4"],
	"weapon_m4a1_silencer": ["ct/ct_buymenu_m4a1", "t/t_buymenu_m4a1"],
	"weapon_sg556": ["ct/ct_buymenu_sg556", "t/t_buymenu_sg556_03"],
	"weapon_aug": ["ct/ct_buymenu_aug", "t/t_buymenu_aug"],
	"weapon_ssg08": ["ct/ct_buymenu_ssg08", "t/t_buymenu_ssg08_03"],
	"weapon_awp": ["ct/ct_buymenu_awp", "t/t_buymenu_awp_03"],
	"weapon_g3sg1": ["ct/ct_buymenu_g3sg1", "t/t_buymenu_g3sg1_03"],
	"weapon_scar20": ["ct/ct_buymenu_scar20", "t/t_buymenu_scar20"],
	"weapon_knife": ["shared/sh_buymenu_knife"],
	"weapon_knife_t": ["shared/sh_buymenu_knife"],
	"weapon_hegrenade": ["shared/sh_buymenu_hegrenade"],
	"weapon_flashbang": ["shared/sh_buymenu_flash"],
	"weapon_smokegrenade": ["shared/sh_buymenu_smoke"],
	"weapon_molotov": ["shared/sh_buymenu_molotov"],
	"weapon_incgrenade": ["shared/sh_buymenu_incendiary"],
	"weapon_decoy": ["shared/sh_buymenu_decoy"],
	"weapon_c4": ["shared/sh_buymenu_c4"],
	"item_defuser": ["shared/sh_buymenu_defuser"],
	"item_kevlar": ["shared/sh_buymenu_armor_helmet"],
	"item_assaultsuit": ["shared/sh_buymenu_armor_helmet"],
}
## The pose the body's rig is taken from: one with no weapon's rig in it.
const RIG_POSE := "shared/sh_buymenu_armor_helmet"
## A held model's bones the poses name otherwise: the Dual Berettas'
## holster, which the model hangs from its skeleton rather than from its
## weapon bone as the poses do (_pose_item()).
const RIG_ALIASES := {"eholster": "elite_holster"}

var team: String = "T"
## The body: the agent's meshes on the poses' rig.
var body: PlayerModel
## The item in hand, by class; "" before the first.
var holding: String = ""

var _camera: Camera3D
var _tree: AnimationTree
## The models of what the agent has held, by class, pinned to its hand and
## shown only while held; null for an item with none (armour).
var _models := {}

## The poses and the breath as the body plays them, by path: each keeps only
## the body's tracks, the breath re-expressed from the rest as Godot adds.
## Made once for every agent built.
static var _clips := {}
## What each pose does to the held item's own bones, by the pose's path, as
## [bone, track type, value]: its one key of each track on the weapon's rig,
## which the body's clip leaves out (_pose_item()).
static var _item_keys := {}


## The tallest picture drawn with 4x MSAA, in pixels; a taller one has 2x.
## MSAA is what softens the agent's outline against the game behind (FXAA
## and SMAA leave its alpha hard), and its buffers are what the picture
## costs: at 3840x2160, 335 MB of video memory with 4x, 217 with 2x and 114
## with none, for 0.35, 0.31 and 0.21 ms of the GPU a frame while open
## (reference/performance.md). At that size 2x is enough.
const MSAA_4X_UP_TO := 1440


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED


## Builds the agent for a side; false, with nothing built, where its model
## or poses were not extracted.
func build(side: String) -> bool:
	team = side
	var agent := PlayerModel.new()
	agent.name = "Agent"
	# Lit by this world's own light, not the map's probes.
	agent.probe_lit = false
	add_child(agent)
	if not ResourceLoader.exists(pose_path(RIG_POSE)) or not ResourceLoader.exists(BREATH) \
			or not agent.load_clips(PackedStringArray([pose_path(RIG_POSE)]), ""):
		agent.free()
		return false
	var dressed := RigModel.instantiate(PlayerModel.AGENTS.get(side, PlayerModel.AGENTS["T"]))
	if dressed != null:
		for mesh in dressed.find_children("*thirdperson*", "MeshInstance3D", true, false):
			agent.adopt(mesh, agent.character_rig)
		dressed.free()
	body = agent
	body.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	body.position = SourceEntities.to_game(AGENT_AT)
	body.rotation_degrees.y = AGENT_YAW
	_build_tree()

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.near = NEAR
	_camera.far = FAR
	add_child(_camera)
	var at := SourceEntities.to_game(CAMERA_AT)
	var yaw := deg_to_rad(CAMERA_YAW)
	_camera.look_at_from_position(at, at + SourceEntities.to_game(Vector3(cos(yaw), sin(yaw), 0.0)))
	_camera.current = true
	frame(Rect2(Vector2.ZERO, Vector2(1920.0, 1080.0)), Vector2(1920.0, 1080.0))
	_light()
	return true


## The pose clips, the breath, and the tree that adds the one over the
## other: the pose at the root, the breath added whole, as the graph's
## Layer Blend adds its local layer.
func _build_tree() -> void:
	var library := body.animation_player.get_animation_library(&"")
	var paths := PackedStringArray([BREATH])
	for item_class: String in POSES:
		var pose := pose_for(item_class, team)
		if not pose.is_empty() and not paths.has(pose_path(pose)):
			paths.append(pose_path(pose))
	for path in paths:
		var clip := _clip(path)
		var clip_name := StringName(path.get_file().get_basename())
		if clip != null and not library.has_animation(clip_name):
			library.add_animation(clip_name, clip)
	# The other side's poses and agent are read now too, not at half time,
	# when the sides swap and the agent is built again mid-match.
	var other := "T" if team == "CT" else "CT"
	for item_class: String in POSES:
		var pose := pose_for(item_class, other)
		if not pose.is_empty():
			_clip(pose_path(pose))
	RigModel.preload_scene(PlayerModel.AGENTS.get(other, PlayerModel.AGENTS["T"]))
	var root := AnimationNodeBlendTree.new()
	var pose := AnimationNodeAnimation.new()
	pose.animation = StringName(RIG_POSE.get_file())
	root.add_node(&"pose", pose)
	var breath := AnimationNodeAnimation.new()
	breath.animation = StringName(BREATH.get_file().get_basename())
	root.add_node(&"breath", breath)
	root.add_node(&"add", AnimationNodeAdd2.new())
	root.connect_node(&"add", 0, &"pose")
	root.connect_node(&"add", 1, &"breath")
	root.connect_node(&"output", 0, &"add")
	_tree = AnimationTree.new()
	_tree.name = "Pose"
	body.animation_player.get_parent().add_child(_tree)
	_tree.root_node = body.animation_player.root_node
	_tree.add_animation_library(&"", library)
	_tree.tree_root = root
	body.animation_player.active = false
	_tree.set("parameters/add/add_amount", 1.0)
	_tree.active = false
	_tree.advance(0.0)


## A pose's or the breath's clip as the body plays it (_clips).
func _clip(path: String) -> Animation:
	if _clips.has(path):
		return _clips[path]
	var source := RigModel.clip_animation(path)
	if source == null:
		return null
	var clip := source.duplicate() as Animation
	var body_node := "animation_skeletons_characters_worldmodel_vnmskel/Skeleton3D"
	var item_keys := []
	for track in range(clip.get_track_count() - 1, -1, -1):
		if String(clip.track_get_path(track).get_concatenated_names()) != body_node:
			if clip.track_get_key_count(track) > 0:
				item_keys.append([String(clip.track_get_path(track).get_subname(0)), clip.track_get_type(track),
					clip.track_get_key_value(track, 0)])
			clip.remove_track(track)
	_item_keys[path] = item_keys
	if path == BREATH:
		clip = PlayerModel.rest_relative(clip, body.character_rig)
	clip.loop_mode = Animation.LOOP_LINEAR
	_clips[path] = clip
	return clip


## The map's sun and sky round the agent, as the game's maps translate theirs
## (MapLighting.build, for a map with no lightmap measured): the sun's
## brightness in Godot's energy, the sky's colours for the ambient with its
## bounce under them, ACES with the saturation the game adds, and no
## background, for the game to show through. The map has no post-processing
## volume, so the exposure is 1.
func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = SUN_COLOUR
	sun.light_energy = SUN_BRIGHTNESS * MapLighting.SUN_ENERGY_PER_BRIGHTNESS
	add_child(sun)
	var aim := SourceEntities.to_game(BrushVolume.source_basis(SUN_ANGLES).x)
	sun.look_at_from_position(Vector3.ZERO, aim)
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = SKY_COLOUR.darkened(0.3)
	sky.sky_horizon_color = SKY_COLOUR
	sky.ground_horizon_color = SKY_COLOUR
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.sky = Sky.new()
	environment.sky.sky_material = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.7
	environment.ambient_light_color = SKY_BOUNCE
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.15
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


## The file of a pose in POSES.
static func pose_path(pose: String) -> String:
	return POSES_DIR.path_join(pose + ".gltf")


## The pose an item strikes for a side, as POSES has it; "" for an item the
## graph has none for.
static func pose_for(item_class: String, side: String) -> String:
	var poses: Array = POSES.get(item_class, [])
	if poses.is_empty():
		return ""
	return poses[0] if poses.size() == 1 or side == "CT" else poses[1]


## Sets the part of the screen this viewport draws: rect, on a screen
## screen_size across, both in the menu's units, the viewport already sized
## to it in pixels (its MSAA goes by that, MSAA_4X_UP_TO). The camera sees
## what the map's camera sees over the whole screen, cut down to rect: a
## frustum the height of rect at the near plane, moved off centre by as much
## as rect is.
func frame(rect: Rect2, screen_size: Vector2) -> void:
	msaa_3d = Viewport.MSAA_4X if size.y <= MSAA_4X_UP_TO else Viewport.MSAA_2X
	if _camera == null or screen_size.y <= 0.0:
		return
	var cut := frustum(rect, screen_size)
	_camera.size = cut[0]
	_camera.frustum_offset = cut[1]


## The frustum that sees rect of the map camera's full-screen view (frame()):
## [its height at the near plane, its offset from the middle there].
static func frustum(rect: Rect2, screen_size: Vector2) -> Array:
	var per_unit := 2.0 * NEAR * tan(deg_to_rad(FOV * 0.5)) / screen_size.y
	return [rect.size.y * per_unit, Vector2(
		rect.get_center().x - screen_size.x * 0.5, screen_size.y * 0.5 - rect.get_center().y
	) * per_unit]


## Starts or stops drawing and animating it: only while the menu is open.
func draw_while(open: bool) -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	if _tree != null:
		_tree.active = open


## Takes an item in hand, by class, in its pose; an item the graph has no
## pose for leaves the agent as it is.
func show_item(item_class: String) -> void:
	if body == null or item_class == holding:
		return
	var pose := pose_for(item_class, team)
	if pose.is_empty():
		return
	holding = item_class
	var node := (_tree.tree_root as AnimationNodeBlendTree).get_node(&"pose") as AnimationNodeAnimation
	node.animation = StringName(pose.get_file())
	for held: String in _models:
		if _models[held] != null:
			(_models[held] as Node3D).visible = held == item_class
	if not _models.has(item_class):
		var look := WeaponLibrary.look(item_class, team)
		var model := body.attach_weapon(String(look.get("model_path", ""))) if not look.is_empty() else null
		if model != null:
			_pose_item(model, pose)
		_models[item_class] = model


## Puts the held model's own bones where its pose has them (_item_keys): the
## Dual Berettas one in each hand and their holster out of sight, the
## Molotov's bottle and lighter each in a hand, the R8's loader out of the
## way, the XM1014's shells gone, the bomb set in the hand. Its root is left:
## it is pinned to the hand's wpn bone, where CS2's Snap Weapon puts it
## (the two-handed items' poses have that bone at the agent's feet, in the
## root's own frame, and their hand bones reach the hands from there). A
## bone the model hangs from its skeleton, which the pose hangs from the
## root, is placed from the root's rest.
func _pose_item(model: Node3D, pose: String) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var root_rest := skeleton.get_bone_rest(0)
	for key: Array in _item_keys.get(pose_path(pose), []):
		var bone := skeleton.find_bone(RIG_ALIASES.get(key[0], key[0]))
		if bone <= 0:
			continue
		var from_root := skeleton.get_bone_parent(bone) < 0
		match int(key[1]):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, root_rest * (key[2] as Vector3) if from_root else key[2])
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone,
					root_rest.basis.get_rotation_quaternion() * (key[2] as Quaternion) if from_root else key[2])
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, key[2])
