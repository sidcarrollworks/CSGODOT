class_name Bot
extends PlayerBody

## A player that is not you. The same body, hull and movement solver as the
## local player, pushed by a route rather than by keys, and wearing the
## third-person model. It walks its route round and round, facing the way it
## goes, and can be shot: it wears the model's own hitboxes on its bones,
## dies where the last round lands, and comes back at the start of its
## route. It does not aim, fire, flinch or think yet.
##
## The point of it being the same body is that it moves like a player. A bot
## that walked on rails would be a different thing to shoot at than the
## players it stands in for.

## Where the bot goes, in order, in world units. It turns for the first
## point on arriving at the last.
@export var route: PackedVector3Array = PackedVector3Array()

## Close enough to a point to head for the next, in units.
@export var arrive_distance: float = 24.0

## How fast the bot turns to face its way, in degrees per second.
@export var turn_rate: float = 540.0

## The bot's side, for its model, and what it holds.
@export_enum("T", "CT") var team: String = "T"
@export var weapon_model: String = ""

## How long a dead bot lies there before it is back on its route.
@export var respawn_seconds: float = 5.0

## The way it faces, in the game's degrees (PlayerInput's).
var yaw_degrees: float = 0.0

var model: PlayerModel
## Its health and armour; what a hit is applied to.
var hit_target: HitTarget
## The model's hitboxes, on its bones.
var hitboxes: SkinnedHitboxes
var alive: bool = true

signal died(zone: StringName)
signal respawned

var _next: int = 0
var _deaths: int = 0
var _respawn_at_usec: int = 0


func _ready() -> void:
	super._ready()
	hit_target = HitTarget.new()
	hit_target.name = "HitTarget"
	hit_target.build_own_hitboxes = false
	add_child(hit_target)
	hit_target.died.connect(_on_died)

	model = PlayerModel.new()
	model.name = "Model"
	add_child(model)
	if not model.setup(team, weapon_model):
		model.queue_free()
		model = null
		return
	hitboxes = SkinnedHitboxes.new()
	hitboxes.name = "Hitboxes"
	add_child(hitboxes)
	hitboxes.build(
		model.character_rig, HitboxSet.load_for(PlayerModel.AGENTS.get(team, PlayerModel.AGENTS["T"])),
		hit_target, MapImporter.SOURCE2_VIEWER_SCALE
	)


func _physics_process(delta: float) -> void:
	wants_jump = false
	wants_duck = false
	wish_dir = Vector3.ZERO
	wish_speed = 0.0

	if not alive:
		if Time.get_ticks_usec() >= _respawn_at_usec:
			respawn()
		return

	if not route.is_empty():
		var target := route[_next]
		var to_target := target - global_position
		to_target.y = 0.0
		if to_target.length() < arrive_distance:
			_next = (_next + 1) % route.size()
		elif to_target.length_squared() > 0.0:
			wish_dir = to_target.normalized()
			wish_speed = config.max_speed
			# The game's yaw 0 looks down -Z, and yaw grows towards -X.
			var wanted := rad_to_deg(atan2(-wish_dir.x, -wish_dir.z))
			yaw_degrees = rad_to_deg(rotate_toward(
				deg_to_rad(yaw_degrees), deg_to_rad(wanted), deg_to_rad(turn_rate) * delta
			))

	simulate(delta)
	if model != null:
		model.update_motion(velocity, yaw_degrees, is_ducked, on_ground)


## Dies where the last round landed: the model plays that death and stays
## down, the hull and the hitboxes go, and the route waits.
func _on_died() -> void:
	alive = false
	_deaths += 1
	velocity = Vector3.ZERO
	var zone: StringName = hit_target.last_hitbox.zone if hit_target.last_hitbox != null else &"chest"
	if model != null:
		model.play(PlayerModel.death_for(zone, _deaths), 0.05)
	if hitboxes != null:
		hitboxes.set_active(false)
	collision_layer = 0
	_respawn_at_usec = Time.get_ticks_usec() + int(respawn_seconds * 1_000_000.0)
	died.emit(zone)


## Back at the start of the route, whole.
func respawn() -> void:
	alive = true
	hit_target.reset()
	collision_layer = 2
	if hitboxes != null:
		hitboxes.set_active(true)
	if not route.is_empty():
		global_position = route[0]
		_next = 1 % route.size()
	velocity = Vector3.ZERO
	if model != null:
		model.play(model.idle)
	respawned.emit()
