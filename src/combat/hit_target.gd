class_name HitTarget
extends Node3D

## Something that can be shot: health, armour and a set of hitboxes.
##
## Builds its own hitboxes rather than loading a scene, so the proportions are
## visible as numbers you can check against a player hull rather than buried in
## a scene file. Or not: a body with a skeleton wears the model's own hitboxes
## (SkinnedHitboxes) and hands them over with adopt.

signal damaged(amount: float, zone: StringName, remaining: float)
signal died

@export var max_health: float = 100.0
@export var armor: float = 100.0

## Off for a target whose hitboxes come from elsewhere; the crude body that
## goes with them stays away too, or on its own for a target that has a
## body already.
@export var build_own_hitboxes: bool = true
@export var build_visual: bool = true

## Standing player proportions, in Source units. The hull is 32 wide and 72
## tall; these split that vertically the way CS does.
const ZONES := {
	&"head": {"size": Vector3(13.0, 11.0, 13.0), "centre": 66.5},
	&"chest": {"size": Vector3(32.0, 22.0, 20.0), "centre": 50.0},
	&"stomach": {"size": Vector3(32.0, 17.0, 20.0), "centre": 30.5},
	&"leg": {"size": Vector3(30.0, 22.0, 18.0), "centre": 11.0},
}

var health: float
var alive: bool = true

## The hitbox the last damage came through, or null: for whoever wants to
## know which side was hit.
var last_hitbox: Hitbox

var _hitboxes: Array[Hitbox] = []


func _ready() -> void:
	health = max_health
	if build_own_hitboxes:
		_build_hitboxes()
		if build_visual:
			_build_visual()


## Takes a hitbox built elsewhere as one of this target's.
func adopt(hitbox: Hitbox) -> void:
	hitbox.target = self
	_hitboxes.append(hitbox)


func _build_hitboxes() -> void:
	for zone in ZONES:
		var spec: Dictionary = ZONES[zone]
		var hitbox := Hitbox.new()
		hitbox.name = "Hitbox_%s" % zone
		hitbox.zone = zone
		hitbox.target = self
		hitbox.position = Vector3(0.0, spec["centre"], 0.0)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec["size"]
		collision.shape = shape
		hitbox.add_child(collision)

		add_child(hitbox)
		_hitboxes.append(hitbox)


## A crude body so there is something to aim at. Replaced by a real player
## model once one has been extracted.
func _build_visual() -> void:
	for zone in ZONES:
		var spec: Dictionary = ZONES[zone]
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec["size"]
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, spec["centre"], 0.0)

		var material := StandardMaterial3D.new()
		# The head reads differently at a glance, which is the point of it.
		material.albedo_color = (
			Color(0.75, 0.45, 0.35) if zone == &"head"
			else Color(0.40, 0.45, 0.52)
		)
		mesh_instance.material_override = material
		add_child(mesh_instance)


func hitboxes() -> Array[Hitbox]:
	return _hitboxes


## The hitboxes' physics ids, for a shooter to leave its own out of a trace.
func rids() -> Array[RID]:
	var out: Array[RID] = []
	for hitbox in _hitboxes:
		out.append(hitbox.get_rid())
	return out


## Turns the hitboxes on or off together: off, the target cannot be shot.
func set_active(active: bool) -> void:
	for hitbox in _hitboxes:
		hitbox.collision_layer = Hitbox.LAYER if active else 0


## Applies damage already reduced for range and hitbox. Armour absorbs a share
## and degrades as it does.
func apply_damage(amount: float, zone: StringName, armor_penetration: float, hitbox: Hitbox = null) -> float:
	if not alive:
		return 0.0
	last_hitbox = hitbox

	var dealt := amount
	if armor > 0.0 and zone != &"leg":
		# Legs are not covered by kevlar in CS, which is why leg shots do not
		# get the armour reduction.
		dealt = amount * armor_penetration
		armor = maxf(armor - (amount - dealt) * 0.5, 0.0)

	health -= dealt
	damaged.emit(dealt, zone, health)

	if health <= 0.0:
		health = 0.0
		alive = false
		died.emit()
	return dealt


func reset() -> void:
	health = max_health
	armor = 100.0
	alive = true
