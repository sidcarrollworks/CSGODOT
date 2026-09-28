extends "res://tests/check_suite.gd"

## Cached damping terms must preserve the old spring response, including
## live tuning, explicit-ratio calls, clamped values and resource copies.
class UncachedData:
	extends WeaponData

	func punch_peak_ratio() -> float:
		var z := _damping_ratio()
		var ringing := sqrt(1.0 - z * z)
		return exp(-z * atan(ringing / z) / ringing)

	func punch_frequency_for(recovery: float, ratio: float = -1.0) -> float:
		var z := _damping_ratio(ratio)
		var ringing := sqrt(1.0 - z * z)
		var peak := ringing * punch_peak_ratio()
		return -log(SETTLE_FRACTION * peak) / maxf(z * recovery, 0.0001)


func _initialize() -> void:
	var cached := WeaponData.new()
	var reference := UncachedData.new()
	# Reuse the same resources while tuning so a stale cache cannot pass.
	for damping in [0.6, 0.2, 0.95, 0.0, 1.2, 0.6]:
		cached.punch_damping_ratio = damping
		reference.punch_damping_ratio = damping
		var equal := cached.punch_peak_ratio() == reference.punch_peak_ratio()
		for recovery in [0.0, -0.1, 0.05, 0.35, 0.644, 2.0]:
			for override_ratio in [-1.0, 0.0, 0.3, 1.0]:
				equal = equal and cached.punch_frequency_for(recovery, override_ratio) == reference.punch_frequency_for(recovery, override_ratio)
				equal = equal and cached.punch_damping_for(recovery, override_ratio) == reference.punch_damping_for(recovery, override_ratio)
				equal = equal and cached.punch_spring_for(recovery, override_ratio) == reference.punch_spring_for(recovery, override_ratio)
		_check(equal, "spring constants stay exact while damping is tuned to %s" % damping)
	var copied := cached.duplicate(true) as WeaponData
	copied.punch_damping_ratio = 0.8
	reference.punch_damping_ratio = 0.8
	_check(copied.punch_frequency_for(0.35) == reference.punch_frequency_for(0.35), "a duplicate computes constants for its own tuning")
	_check(cached.punch_damping_ratio == 0.6, "tuning a duplicate leaves the original resource independent")
	var a := WeaponData.Punch.new()
	var b := WeaponData.Punch.new()
	var same_response := true
	for tick in 512:
		var dt: float = [1.0 / 64.0, 1.0 / 128.0, 0.031][tick % 3]
		if tick % 23 == 0:
			a.kick(Vector2(-0.3, 2.0))
			b.kick(Vector2(-0.3, 2.0))
		var recovery := 0.12 if tick % 47 < 24 else 0.7
		a.advance(dt, copied.punch_damping_for(recovery), copied.punch_spring_for(recovery), 1.0 / WeaponData.PUNCH_HZ)
		b.advance(dt, reference.punch_damping_for(recovery), reference.punch_spring_for(recovery), 1.0 / WeaponData.PUNCH_HZ)
		same_response = same_response and a.value == b.value and a.velocity == b.velocity
	_check(same_response, "repeated impulses and changing recovery times retain exactly the same integrated recoil")
	_finish("weapon-constants")
