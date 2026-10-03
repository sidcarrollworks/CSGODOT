class_name GrenadeThrowState
extends RefCounted

## Held strength, delayed release and movement-finish jump parameters.
## Simulation microseconds only; the hand's animation is separate.
var strength := 1.0
var holding := false
var next_hold_tick := 0
var pending_class := ""
var due_usec := -1
var jump_throw := false
var stash_usec := -1
var snapshot: Dictionary = {}


func hold(left: bool, right: bool, tick: int) -> void:
	if tick < next_hold_tick:
		return
	var target := GrenadeRules.strength_for(left, right)
	strength = move_toward(strength, target, GrenadeRules.STRENGTH_STEP) if holding else target
	holding = true
	next_hold_tick = tick + 1


func release(weapon_class: String, now_usec: int) -> void:
	holding = false
	pending_class = weapon_class
	due_usec = now_usec + GrenadeRules.RELEASE_DELAY_USEC
	jump_throw = jump_eligible(now_usec)


func consume(now_usec: int) -> String:
	if pending_class.is_empty() or now_usec <= due_usec:
		return ""
	if not jump_throw and jump_eligible(now_usec, GrenadeRules.RELEASE_DELAY_USEC):
		due_usec = now_usec + GrenadeRules.RELEASE_DELAY_USEC
		jump_throw = true
		return ""
	var weapon_class := pending_class
	pending_class = ""
	due_usec = -1
	return weapon_class


func jumped(at_usec: int, movement_usec: int) -> void:
	stash_usec = at_usec + movement_usec + GrenadeRules.RELEASE_DELAY_USEC
	snapshot.clear()


func finish_movement(now_usec: int, parameters: Dictionary) -> void:
	if stash_usec >= 0 and now_usec >= stash_usec and snapshot.is_empty():
		snapshot = parameters.duplicate()


func jump_eligible(now_usec: int, offset_usec: int = 0) -> bool:
	var age := now_usec + offset_usec - stash_usec
	return stash_usec >= 0 and age > 0 and age <= GrenadeRules.SNAPSHOT_AGE_USEC


func launch(now_usec: int, live: Dictionary) -> Dictionary:
	return snapshot.duplicate() if not snapshot.is_empty() and jump_eligible(now_usec) else live


func cancel_hold() -> void:
	holding = false
	next_hold_tick = 0


func reset() -> void:
	cancel_hold()
	pending_class = ""
	due_usec = -1
	jump_throw = false
	stash_usec = -1
	snapshot.clear()
