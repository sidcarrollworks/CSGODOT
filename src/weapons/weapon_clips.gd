class_name WeaponClips
extends RefCounted

## What the game's first-person clips say about a gun's timing, as
## reference/weapons/timings.csv carries them (written by
## scripts/weapon_tables.gd from `scripts/extract_assets.sh
## weapon-animations`): each clip's length and the events marked in it.
##
## Read once, when the guns are built (WeaponLibrary), never in a tick.

const PATH := "res://reference/weapons/timings.csv"

## {class: {clip: {event: [at, for]}}}, the events that are IDs only.
static var _events := {}


## A gun that loads a shell at a time: its reload clip's intro, each
## shell's loop, how far into the loop the shell goes in, and the outro, in
## seconds (WeaponData.shell_intro and the rest). Empty where the clip does
## not mark all four.
static func shell_reload(weapon_class: String) -> PackedFloat32Array:
	var reload: Dictionary = (events().get(weapon_class, {}) as Dictionary).get("reload", {})
	for event in ["WPN_RELOAD_INTRO", "WPN_RELOAD_LOOP", "WPN_RELOAD_ADD_AMMO", "WPN_RELOAD_OUTRO"]:
		if not reload.has(event):
			return PackedFloat32Array()
	var loop: Array = reload["WPN_RELOAD_LOOP"]
	return PackedFloat32Array([
		loop[0], loop[1], reload["WPN_RELOAD_ADD_AMMO"][0] - loop[0], reload["WPN_RELOAD_OUTRO"][1],
	])


## Puts a gun's shell-by-shell reload timing on data, where it has one.
static func apply(data: WeaponData) -> void:
	if not data.reloads_single_shells:
		return
	var parts := shell_reload(data.item_class)
	if parts.is_empty():
		push_warning("No shell reload timing for %s in %s; the Nova's stands in" % [data.item_class, PATH])
		return
	data.shell_intro = parts[0]
	data.shell_loop = parts[1]
	data.shell_in = parts[2]
	data.shell_outro = parts[3]


static func events() -> Dictionary:
	if _events.is_empty():
		_events = read(FileAccess.get_file_as_string(PATH))
	return _events


## The ID events of a timings.csv's text: {class: {clip: {event: [at, for]}}}.
## The first of an event in a clip is the one kept.
static func read(text: String) -> Dictionary:
	var out := {}
	for row in text.split("\n"):
		var fields := row.strip_edges().split(",")
		if fields.size() < 7 or fields[3] != "ID":
			continue
		if not out.has(fields[0]):
			out[fields[0]] = {}
		var clips: Dictionary = out[fields[0]]
		if not clips.has(fields[1]):
			clips[fields[1]] = {}
		var clip: Dictionary = clips[fields[1]]
		if not clip.has(fields[4]):
			clip[fields[4]] = [fields[5].to_float(), fields[6].to_float()]
	return out
