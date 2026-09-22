class_name Footsteps
extends Node3D

## A body's footsteps and landings, by what it walks on.
##
## Placed under a PlayerBody. Each physics tick it looks at how the body
## moves: running, a step every third of a second or so; walking slower
## than the game's walk speed, or crouched, nothing, which is what makes
## walking quiet in CS; a landing after a fall, a thump. The surface is the
## map's own: the collision hull names each of its parts by material
## (physics_group_sand, physics_group_wood_plank), and a ray down from the
## feet reads the name off the part it stands on. Each name maps to one of
## the game's footstep sets; the sound then comes from the feet, in the
## world, for everyone within earshot.

## Below this speed, in units a second, no step: walking (130) is silent.
const QUIET_BELOW := 131.0
## The gap between steps at full run and at a slow jog, in seconds.
const RUN_INTERVAL := 0.34
const JOG_INTERVAL := 0.5
const JOG_BELOW := 220.0
## A landing sounds when the body was falling faster than this, in units
## a second, when it met the ground: a jump's own fall does.
const LANDING_FALL_SPEED := 200.0
## Godot's 3D audio is set out in metres; the map is in inches.
const METRE := 39.37

## The hull's material names to the game's footstep sets. Anything
## beginning with "wood" or "metal" goes with those; anything unknown is
## concrete, which is most of dust2.
const SURFACE_SETS := {
	"sand": "sand", "dirt": "dirt", "concrete": "concrete_ct", "tile": "tile", "rock": "gravel",
	"carpet": "carpet", "glass": "glass", "rubbertire": "rubber", "plastic": "plastic_barrel",
	"chainlink": "metal_chainlink", "metalvent": "metal_vent", "solidmetal": "metal_solid",
	"pottery": "tile", "computer": "plastic_barrel",
}
const DEFAULT_SET := "concrete_ct"
## Sets with no landing of their own land on the general one.
const LANDINGS := ["concrete", "dirt", "sand", "metal_solid", "metal_vent", "metal_grate", "tile", "gravel", "grass", "carpet", "glass", "rubber", "mud"]

var body: PlayerBody
var _player: AudioStreamPlayer3D
var _since_step: float = 0.0
var _was_on_ground: bool = true
var _fall_speed: float = 0.0

## The last surface set walked on, and how many steps and landings have
## sounded, for whoever asks.
var surface: String = DEFAULT_SET
var steps: int = 0
var landings: int = 0


func _ready() -> void:
	body = get_parent() as PlayerBody
	_player = AudioStreamPlayer3D.new()
	_player.unit_size = 10.0 * METRE
	_player.max_distance = 80.0 * METRE
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_player)


func _physics_process(delta: float) -> void:
	if body == null or not SoundBank.available():
		return
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if not body.on_ground:
		_fall_speed = -body.velocity.y
		_was_on_ground = false
		_since_step = 0.0
		return
	if not _was_on_ground:
		_was_on_ground = true
		if _fall_speed > LANDING_FALL_SPEED:
			land()
		return
	if speed < QUIET_BELOW or body.is_ducked:
		_since_step = 0.0
		return
	_since_step += delta
	if _since_step >= (RUN_INTERVAL if speed >= JOG_BELOW else JOG_INTERVAL):
		_since_step = 0.0
		step()


## One footstep on whatever is under the feet, now.
func step() -> void:
	surface = surface_below()
	steps += 1
	_play("player/footsteps/%s_" % surface, 0.0)


## A landing on whatever is under the feet.
func land() -> void:
	surface = surface_below()
	landings += 1
	var set_name := surface.trim_suffix("_ct")
	if set_name not in LANDINGS:
		set_name = "auto"
	_play("player/footsteps/land_%s" % set_name, 0.0)


## The footstep set for the hull part under the body's feet.
func surface_below() -> String:
	if not is_inside_tree():
		return DEFAULT_SET
	var space := get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * 8.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 24.0, Hitscan.WORLD_LAYER, [body.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return DEFAULT_SET
	var collider: Object = hit["collider"]
	if not collider is CollisionObject3D:
		return DEFAULT_SET
	var owner_id: int = (collider as CollisionObject3D).shape_find_owner(hit["shape"])
	var shape_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
	return set_for(shape_node.name if shape_node != null else "")


## The footstep set for a hull part's name.
static func set_for(hull_name: String) -> String:
	var material := hull_name.trim_prefix("physics_group_").trim_prefix("physics_")
	if SURFACE_SETS.has(material):
		return SURFACE_SETS[material]
	if material.begins_with("wood"):
		return "wood"
	if material.begins_with("metal"):
		return "metal_solid"
	return DEFAULT_SET


func _play(stem: String, volume_db: float) -> void:
	var stream := SoundBank.randomizer(stem)
	if stream == null:
		return
	if _player.stream != stream:
		_player.stream = stream
	_player.volume_db = volume_db
	_player.play()
