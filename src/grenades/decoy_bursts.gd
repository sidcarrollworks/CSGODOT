class_name DecoyBursts
extends RefCounted

## When a decoy fires: bursts of its thrower's gun from the moment it lies
## still, for GrenadeRules.DECOY_SECONDS, one to DECOY_BURST_MOST rounds at
## the gun's own rate, with a pause between bursts. The lengths and pauses
## come from the decoy's seed, so every machine hears the same bursts; the
## figures are guesses until measured (G5).

var started_usec: int = 0
var seed: int = 0
## The gun's time between rounds, in seconds.
var cycle_time: float = 0.1

var _next_usec: int = 0
var _left_in_burst: int = 0
var _bursts: int = 0


func _init(at_usec: int = 0, p_seed: int = 0, p_cycle_time: float = 0.1) -> void:
	started_usec = at_usec
	seed = p_seed
	cycle_time = maxf(p_cycle_time, 0.03)
	_next_usec = at_usec
	_start_burst()


func ends_usec() -> int:
	return started_usec + int(GrenadeRules.DECOY_SECONDS * 1_000_000.0)


## Every round due by now_usec that has not been fired yet, as the
## simulation time each is due at.
func due(now_usec: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	while _next_usec <= now_usec and _next_usec < ends_usec():
		out.append(_next_usec)
		_left_in_burst -= 1
		if _left_in_burst > 0:
			_next_usec += int(cycle_time * 1_000_000.0)
		else:
			var roll := float(hash([seed, _bursts, "gap"]) % 1000) / 1000.0
			_next_usec += int(lerpf(GrenadeRules.DECOY_GAP_LEAST, GrenadeRules.DECOY_GAP_MOST, roll) * 1_000_000.0)
			_start_burst()
	return out


func _start_burst() -> void:
	_bursts += 1
	_left_in_burst = 1 + hash([seed, _bursts]) % GrenadeRules.DECOY_BURST_MOST
