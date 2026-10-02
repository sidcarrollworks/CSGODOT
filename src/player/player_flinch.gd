class_name PlayerFlinch
extends RefCounted

## CS2's separate BodyFlinch and HeadFlinch additive layers. Authored clips
## are sampled by the draw clock, so an unseen body's deferred animation
## step cannot play a hit late. Two poses cross-fade on another hit, as the
## graph's Flinch_WPNs and Flinch_WPNs0 do; locomotion and gun actions keep
## running below them. All assets are loaded when the body is built.

const RESTART_FADE := 0.1
const HEAD_FADE := 0.1

var _clips: Array[AnimationNodeAnimation] = []
var _seek_paths: Array[StringName] = []
var _blend_path: StringName
var _amount_path: StringName
var _started := PackedInt64Array([0, 0])
var _lengths := PackedFloat64Array([0.0, 0.0])
var _current := 0
var _cross_fading := false
var _due := false
var _head := false


func _init(head: bool = false) -> void:
	_head = head


## Adds a layer and returns its output. The poses are held by TimeScale 0
## and explicitly sought, leaving every other animation's timing alone.
func attach(tree: AnimationNodeBlendTree, moving: StringName, first_clip: StringName) -> StringName:
	var prefix := "head_flinch" if _head else "body_flinch"
	var output := StringName(prefix)
	var mix := StringName(prefix + "_mix")
	_blend_path = StringName("parameters/" + prefix + "_mix/blend_amount")
	_amount_path = StringName("parameters/" + prefix + "/add_amount")
	tree.add_node(output, AnimationNodeAdd2.new())
	tree.add_node(mix, AnimationNodeBlend2.new())
	for lane in 2:
		var clip_name := StringName(prefix + "_clip_%d" % lane)
		var seek_name := StringName(prefix + "_seek_%d" % lane)
		var hold_name := StringName(prefix + "_hold_%d" % lane)
		var clip := AnimationNodeAnimation.new()
		clip.animation = first_clip
		_clips.append(clip)
		_seek_paths.append(StringName("parameters/" + String(seek_name) + "/seek_request"))
		tree.add_node(clip_name, clip)
		tree.add_node(seek_name, AnimationNodeTimeSeek.new())
		tree.add_node(hold_name, AnimationNodeTimeScale.new())
		tree.connect_node(seek_name, 0, clip_name)
		tree.connect_node(hold_name, 0, seek_name)
		tree.connect_node(mix, lane, hold_name)
	tree.connect_node(output, 0, moving)
	tree.connect_node(output, 1, mix)
	return output


func initialize(tree: AnimationTree) -> void:
	for lane in 2:
		var prefix := "head_flinch" if _head else "body_flinch"
		tree.set(StringName("parameters/" + prefix + "_hold_%d/scale" % lane), 0.0)
	tree.set(_amount_path, 0.0)


## Repeated hits of the same type start again, without restarting the old
## pose that fades into them. Head and body instances never reset each other.
func start(clip: StringName, length: float, at_usec: int) -> void:
	_cross_fading = weight(at_usec) > 0.0
	if _cross_fading:
		_current = 1 - _current
	_clips[_current].animation = clip
	_started[_current] = at_usec
	_lengths[_current] = length
	_due = true


func clear(tree: AnimationTree) -> void:
	_lengths.fill(0.0)
	_cross_fading = false
	_due = false
	tree.set(_amount_path, 0.0)


func apply(tree: AnimationTree, now_usec: int) -> void:
	if not _due:
		return
	var amount := weight(now_usec)
	tree.set(_amount_path, amount)
	if amount <= 0.0:
		_due = false
		return
	var blend := restart_share(now_usec)
	tree.set(_blend_path, blend if _current == 1 else 1.0 - blend)
	for lane in 2:
		tree.set(_seek_paths[lane], clampf(age(lane, now_usec), 0.0, _lengths[lane]))


func age(lane: int, now_usec: int) -> float:
	return maxf(0.0, float(now_usec - _started[lane]) / 1_000_000.0)


func restart_share(now_usec: int) -> float:
	return clampf(age(_current, now_usec) / RESTART_FADE, 0.0, 1.0) if _cross_fading else 1.0


func weight(now_usec: int) -> float:
	var length := _lengths[_current]
	if length <= 0.0:
		return 0.0
	var seconds := age(_current, now_usec)
	if seconds < length:
		return 1.0
	return clampf(1.0 - (seconds - length) / HEAD_FADE, 0.0, 1.0) if _head else 0.0


## toward_source: body-local forward and left, from victim toward shooter.
## The graph names north = front, south = rear, east = right, west = left.
## Arms/legs use the capsule's side; stomach has only front/rear variants.
static func clip_for(zone: StringName, side: StringName, toward_source: Vector2, variation: String) -> StringName:
	var clip := ""
	match zone:
		&"arm", &"leg":
			clip = "flinch_" + String(zone) + ("_left" if side == &"left" else "_right")
		&"stomach":
			clip = "flinch_stomach" + ("_rear" if toward_source.x < 0.0 else "")
		&"head", &"chest":
			clip = "flinch_" + String(zone)
			if absf(toward_source.y) > absf(toward_source.x):
				clip += "_left" if toward_source.y > 0.0 else "_right"
			elif toward_source.x < 0.0:
				clip += "_rear"
		_:
			return &""
	return StringName(clip + ("_" + variation if variation in ["pistol", "knife"] else ""))
