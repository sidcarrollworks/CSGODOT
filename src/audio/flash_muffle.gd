class_name FlashMuffle
extends RefCounted

## What a flashbang does to your ears: the ring, and the muffle over
## everything else while it lasts (reference/research/audio-gameplay.md 4.3).
##
## - The ring is Flashbang.Ring.Short, .Medium or .Long, one of three by how
##   long the blind lasts. Which length goes with which is in no file read
##   (Local check L4); ring_for() takes the ring whose own length (its time
##   curve's end: 2.0, 3.0, 4.18 s) is nearest the blind's.
## - The muffle is CS2's DSP preset core.flashbang.muffle.short, .medium or
##   .long, the same strength as the ring. Their only differing numbers are
##   0.2/0.7, 0.4/1.4 and 1.4/5.5, read as a fade and a length in seconds
##   (inferred). The presets are a diffusor with a 3000 Hz wobble, which
##   Godot's buses have no match for: here the muffle is a low-pass and a
##   dip, full for the length less the fade, then easing out over the fade.
##   How far down it cuts and dips (CUTOFF_HZ, DIP_DB) is set by ear, not
##   read: provisional until the Local listen beside CS2.
## - It is heard on every bus a mixgroup with DSP plays on, as far as that
##   mixgroup's dsp takes it (the UI's 0.1 barely, the music's 0 not at all),
##   and on the Unmixed bus, where the sounds not yet on SoundEvents play
##   (the guns, steps, hits and bullet impacts). The ring is the one event
##   CS2 marks dsp_bypass, so SoundEvents plays it on its mixgroup bus's
##   twin, which the muffle leaves alone.
## - Dying clears both (Valve, 2023-03-30), as does a new round's reset.

const RINGS := {
	"Short": "Flashbang.Ring.Short",
	"Medium": "Flashbang.Ring.Medium",
	"Long": "Flashbang.Ring.Long",
}
## Each strength's muffle: [its length, the fade at its end], in seconds,
## from DSP presets 136, 135 and 134.
const PRESETS := {
	"Short": [0.7, 0.2],
	"Medium": [1.4, 0.4],
	"Long": [5.5, 1.4],
}
## Where the low-pass sits at the muffle's full, and how far the level dips:
## by ear (provisional).
const CUTOFF_HZ := 1200.0
const OPEN_HZ := 20500.0
const DIP_DB := -8.0
## The bus the older sound views play on.
const UNMIXED_BUS := &"Unmixed"

## Which strength, and when it started (seconds on the caller's clock);
## "" for none.
var strength := ""
var started := 0.0
## The buses it has put its effects on: {bus name: [low-pass index,
## amplify index, dsp share]}.
var _effects := {}


## The strength of ring and muffle for a blind this many seconds long: the
## ring whose own length is nearest it (inferred).
static func ring_for(blind_duration: float) -> String:
	var best := "Short"
	var best_gap := INF
	for name: String in RINGS:
		var gap := absf(ring_length(name) - blind_duration)
		if gap < best_gap:
			best = name
			best_gap = gap
	return best


## How long a ring sounds: where its time curve ends.
static func ring_length(name: String) -> float:
	var event := SoundEvents.find(RINGS[name])
	if event == null or event.time_curve.is_empty():
		return 0.0
	return float((event.time_curve[event.time_curve.size() - 1] as Array)[0])


## How far a muffle of a strength is on, seconds after it began: 1 until
## its fade, then down to 0 at its length.
static func amount_at(p_strength: String, since: float) -> float:
	if not PRESETS.has(p_strength) or since < 0.0:
		return 0.0
	var length: float = PRESETS[p_strength][0]
	var fade: float = PRESETS[p_strength][1]
	if since >= length:
		return 0.0
	if since <= length - fade:
		return 1.0
	return (length - since) / fade


## The buses a muffle reaches and how far: {bus: dsp share}. Each bus in
## the layout whose mixgroup has DSP, and the Unmixed bus in full.
static func muffled_buses() -> Dictionary:
	var result := {UNMIXED_BUS: 1.0}
	var mixgroups: Dictionary = SoundEvents.table().get("mixgroups", {})
	for i in range(1, AudioServer.bus_count):
		var bus := AudioServer.get_bus_name(i)
		var share := float((mixgroups.get(String(bus), {}) as Dictionary).get("dsp", 0.0))
		if share > 0.0 and bus != UNMIXED_BUS:
			result[bus] = share
	return result


## The bus the layout leaves out, added once while the game runs: the
## older views'. It plays straight into Master at its own level, so it
## changes nothing about how loud they are.
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(UNMIXED_BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, UNMIXED_BUS)
		AudioServer.set_bus_send(index, &"Master")


## The bus a sound view not yet on SoundEvents plays on, made if need be.
static func unmixed_bus() -> StringName:
	ensure_buses()
	return UNMIXED_BUS


## A flash of this strength starts now.
func flash(p_strength: String, now: float) -> void:
	strength = p_strength
	started = now


func clear() -> void:
	strength = ""


## How far it is on at now.
func amount(now: float) -> float:
	return amount_at(strength, now - started) if strength != "" else 0.0


## Puts the muffle on the buses as far as it is on at now.
func apply(now: float) -> void:
	var on := amount(now)
	if on <= 0.0 and _effects.is_empty():
		return
	if _effects.is_empty():
		_add_effects()
	for bus: StringName in _effects:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var entry: Array = _effects[bus]
		var share := on * float(entry[2])
		var low_pass := AudioServer.get_bus_effect(index, entry[0]) as AudioEffectLowPassFilter
		var dip := AudioServer.get_bus_effect(index, entry[1]) as AudioEffectAmplify
		if low_pass != null:
			low_pass.cutoff_hz = lerpf(OPEN_HZ, CUTOFF_HZ, share)
		if dip != null:
			dip.volume_db = DIP_DB * share
		AudioServer.set_bus_effect_enabled(index, entry[0], share > 0.0)
		AudioServer.set_bus_effect_enabled(index, entry[1], share > 0.0)


## Takes its effects off the buses again.
func remove() -> void:
	for bus: StringName in _effects:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var entry: Array = _effects[bus]
		# The later one first, so the earlier index still holds.
		AudioServer.remove_bus_effect(index, entry[1])
		AudioServer.remove_bus_effect(index, entry[0])
	_effects.clear()


func _add_effects() -> void:
	ensure_buses()
	var buses := muffled_buses()
	for bus: StringName in buses:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var low_pass := AudioEffectLowPassFilter.new()
		low_pass.cutoff_hz = OPEN_HZ
		var dip := AudioEffectAmplify.new()
		var first := AudioServer.get_bus_effect_count(index)
		AudioServer.add_bus_effect(index, low_pass)
		AudioServer.add_bus_effect(index, dip)
		AudioServer.set_bus_effect_enabled(index, first, false)
		AudioServer.set_bus_effect_enabled(index, first + 1, false)
		_effects[bus] = [first, first + 1, float(buses[bus])]
