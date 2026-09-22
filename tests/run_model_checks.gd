extends SceneTree

## Checks the extracted weapons and player models, if there are any.
##
##   godot --headless --path . --script tests/run_model_checks.gd
##
## Like the dust2 checks, this passes without checking anything on a machine
## where scripts/extract_assets.sh has not been run. Where it has, it is the
## test that what Godot made of the exports is what the game will need: a
## skeleton to animate, the first-person arm meshes to draw, the weapon's own
## animations, and the first-person clips as animations of their own.

const WEAPONS_DIR := "res://assets/weapons"
const CHARACTERS_DIR := "res://assets/characters"

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	var weapons := _find(WEAPONS_DIR, "weapon_rif_")
	var agents := _find(CHARACTERS_DIR.path_join("agents"), "")
	var clips := _find(CHARACTERS_DIR.path_join("animation/anims"), "")
	if weapons.is_empty() and agents.is_empty():
		print("no weapons or characters have been extracted; nothing to check.")
		quit(0)
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

	_report()


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


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s" % description)


func _report() -> void:
	if _failures == 0:
		print("%d model checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d model checks failed." % [_failures, _checks])
		quit(1)
