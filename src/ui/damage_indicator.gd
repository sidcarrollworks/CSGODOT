class_name DamageIndicator
extends Control

## Where the rounds hitting you came from: a red arc round the crosshair on
## the side the shooter stood, for each hit, fading out. The arc keeps
## pointing at where the round was fired from as you turn, so turning
## towards it brings it to the top.
##
## It only draws what the simulation reports (PlayerSim.hurt), and the
## fade is on the clock frames are drawn by.

## How long an arc stays, and how long of that it spends fading, in seconds.
## By eye against CS2; not published.
const SHOW_SECONDS := 1.5
const FADE_SECONDS := 0.6

## The arc's distance from the crosshair, its width either side of where it
## points, and its thickness, in pixels and degrees.
const RADIUS := 110.0
const HALF_WIDTH_DEGREES := 22.0
const THICKNESS := 7.0
const COLOUR := Color(0.9, 0.08, 0.05, 0.85)

## Past this many, the oldest goes.
const MOST := 8

## Whose hits, and the look angles to draw them against.
var player: PlayerController

var _hits: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A hit from a round fired at `from`, in the world.
func hit_from(from: Vector3) -> void:
	_hits.append({"from": from, "left": SHOW_SECONDS})
	if _hits.size() > MOST:
		_hits.pop_front()
	queue_redraw()


func showing() -> int:
	return _hits.size()


func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for i in range(_hits.size() - 1, -1, -1):
		_hits[i]["left"] -= delta
		if _hits[i]["left"] <= 0.0:
			_hits.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var centre := size * 0.5
	for hit in _hits:
		var angle := screen_angle(player.global_position, player.input.yaw_degrees, hit["from"])
		var colour := COLOUR
		colour.a *= clampf(hit["left"] / FADE_SECONDS, 0.0, 1.0)
		# Godot measures arcs from +x, clockwise on screen; straight up is -90.
		var at := angle - PI * 0.5
		var half := deg_to_rad(HALF_WIDTH_DEGREES)
		draw_arc(centre, RADIUS, at - half, at + half, 24, colour, THICKNESS, true)


## Which way a round fired at `from` came from, on the screen of a player at
## `position` looking along `yaw_degrees`: radians clockwise from straight up,
## so 0 is from ahead, PI/2 from the right, PI from behind. Only the bearing
## counts; a shot from above or below reads by where it was fired from on the
## ground.
static func screen_angle(position: Vector3, yaw_degrees: float, from: Vector3) -> float:
	var to := from - position
	if Vector2(to.x, to.z).length_squared() < 1e-6:
		return 0.0
	# The game's yaw 0 looks down -Z, and yaw grows towards -X, to the left.
	var bearing := atan2(-to.x, -to.z)
	return wrapf(deg_to_rad(yaw_degrees) - bearing, -PI, PI)
