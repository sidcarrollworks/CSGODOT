class_name BodyWounds
extends Node3D

## CS2 accumulates impact RG into skin UV2. These bounded projected marks
## use its actual R mask and tissue colour, following the struck bone;
## bone projection approximates that deforming texture accumulation.
const LIMIT := 48
const SIZE := 8.0
var marks: Array[Dictionary] = []
var _texture: Texture2D
var _normal: Texture2D
var _following := {}  # Skeleton3D -> final-pose callback


func _ready() -> void:
	var color := SpriteSheet.named("materials/blood/blood_default_color.vtex")
	var mask := SpriteSheet.named("materials/blood/blood_default_impact.vtex")
	var normal := SpriteSheet.named("materials/blood/blood_default_normal.vtex")
	if color == null or mask == null:
		return
	var image := color.texture.get_image()
	var coverage := mask.texture.get_image()
	if image == null or coverage == null:
		return
	if image.is_compressed():
		image.decompress()
	if coverage.is_compressed():
		coverage.decompress()
	image.resize(coverage.get_width(), coverage.get_height())
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			c.a = coverage.get_pixel(x, y).r
			image.set_pixel(x, y, c)
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	_normal = normal.texture if normal != null else null


func mark(userid: int, models: Array[PlayerModel], bone_name: StringName, at: Vector3, normal: Vector3) -> void:
	if _texture == null or models.is_empty() or bone_name == &"":
		return
	var source := models[0].character_rig
	if not is_instance_valid(source):
		return
	var bone := source.find_bone(bone_name)
	if bone < 0:
		return
	var pose := source.global_transform * source.get_bone_global_pose(bone)
	var local_at := pose.affine_inverse() * at
	var local_normal := pose.basis.inverse() * normal
	for model in models:
		if not _has_receiver(model):
			continue
		var skeleton := model.character_rig
		if not is_instance_valid(skeleton):
			continue
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		if marks.size() >= LIMIT:
			(marks.pop_front().node as Decal).queue_free()
		var decal := Decal.new()
		decal.size = Vector3(SIZE, 6.0, SIZE)
		decal.texture_albedo = _texture
		decal.texture_normal = _normal
		decal.cull_mask = RigModel.LAYER
		decal.albedo_mix = 0.9
		decal.normal_fade = 0.5
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		add_child(decal)
		marks.append({"userid": userid, "skeleton": skeleton, "bone": index,
			"at": local_at, "normal": local_normal, "node": decal})
		if not _following.has(skeleton):
			var follow := _follow_skeleton.bind(skeleton)
			skeleton.skeleton_updated.connect(follow)
			_following[skeleton] = follow
	_prune_following()
	update_marks()


func update_marks() -> void:
	for i in range(marks.size() - 1, -1, -1):
		var mark := marks[i]
		if not is_instance_valid(mark.skeleton) or not mark.skeleton.is_inside_tree():
			(mark.node as Decal).queue_free()
			marks.remove_at(i)
			continue
		_update_mark(mark)
	_prune_following()


## The frame read follows node movement; this signal follows the final
## fitted skin. Before it, bone getters still return the pre-modifier pose.
func _follow_skeleton(skeleton: Skeleton3D) -> void:
	for mark: Dictionary in marks:
		if mark.skeleton == skeleton:
			_update_mark(mark)


func _update_mark(mark: Dictionary) -> void:
	var pose: Transform3D = mark.skeleton.global_transform * mark.skeleton.get_bone_global_pose(int(mark.bone))
	var direction := (pose.basis * (mark.normal as Vector3)).normalized()
	if direction.length_squared() < 1e-8:
		direction = Vector3.UP
	# A decal projects along -Y, into the outward-facing surface normal.
	var side := direction.cross(Vector3.FORWARD)
	if side.length_squared() < 1e-8:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var basis := Basis(side, direction, side.cross(direction))
	mark.node.global_transform = Transform3D(basis, pose * (mark.at as Vector3) + direction * 0.05)


## Shadow-only and hidden authority rigs stand beside the drawn body.
## Another projector there would also print on the same visible receiver.
static func _has_receiver(model: PlayerModel) -> bool:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null and mesh.is_visible_in_tree() and (mesh.layers & RigModel.LAYER) != 0 \
				and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			return true
	return false


func _prune_following() -> void:
	for skeleton in _following.keys():
		if not is_instance_valid(skeleton):
			_following.erase(skeleton)
			continue
		if not marks.any(func(mark: Dictionary) -> bool: return mark.skeleton == skeleton):
			skeleton.skeleton_updated.disconnect(_following[skeleton])
			_following.erase(skeleton)


func _exit_tree() -> void:
	for skeleton in _following:
		if is_instance_valid(skeleton):
			skeleton.skeleton_updated.disconnect(_following[skeleton])
	_following.clear()


func clear_player(userid: int) -> void:
	for i in range(marks.size() - 1, -1, -1):
		if int(marks[i].userid) == userid:
			(marks[i].node as Decal).queue_free()
			marks.remove_at(i)
	_prune_following()
