class_name Hitbox
extends Area3D

## One damage zone on a target.
##
## Separate areas rather than one capsule, because where you hit decides the
## damage and that is most of what makes CS shooting feel fair: a head is worth
## four chests, and the player has to believe the game agreed with them about
## which one they hit.

## The physics layer hitboxes live on. Kept off the world layer so a trace can
## tell the difference between hitting a wall and hitting a person.
const LAYER := 4

@export var zone: StringName = &"chest"

## The thing that takes the damage. Set by whoever builds the hitboxes.
var target: HitTarget


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
