class_name Bot
extends PlayerBody

## A player that is not you. The same body, hull and movement solver as the
## local player, pushed by a route rather than by keys, and wearing the
## third-person model. It walks its route round and round, facing the way it
## goes, and for now that is all it does: no aim, no fire, no sense.
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

## The way it faces, in the game's degrees (PlayerInput's).
var yaw_degrees: float = 0.0

var model: PlayerModel
var _next: int = 0


func _ready() -> void:
	super._ready()
	model = PlayerModel.new()
	model.name = "Model"
	add_child(model)
	if not model.setup(team, weapon_model):
		model.queue_free()
		model = null


func _physics_process(delta: float) -> void:
	wants_jump = false
	wants_duck = false
	wish_dir = Vector3.ZERO
	wish_speed = 0.0

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
