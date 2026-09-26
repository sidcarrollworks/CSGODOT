extends SceneTree

## Writes reference/sounds/sound_events.json and sound_events.md, and the
## project's bus layout (default_bus_layout.tres), from CS2's own sound
## event, sound stack and mixer files as SteamDatabase's GameTracking-CS2
## publishes them in text:
##
##   scripts/sound_events.sh          fetches GameTracking-CS2 and runs this
##   godot --headless --path . --script scripts/sound_event_tables.gd -- <GameTracking-CS2 checkout> [commit]
##
## Needs no extracted assets and no copy of CS2, so a cloud thread can run
## it. What it keeps:
##
## - Every event in EVENT_FILES, its `base` resolved, with the fields that
##   differ from its type's defaults. Curves keep each point's distance (or
##   time) and value; the slopes and tangent modes are dropped, since
##   straight lines between the points are within a dB or two of them
##   (reference/research/audio-engine.md 1.2).
## - Each type's defaults, from the `public` operator of its stack
##   (soundstacks/*.vsndstck): what an event that leaves a field out gets.
## - Every mixgroup's parent, and its vol, lvl and dsp in Default_Mix
##   (scripts/soundmixers.txt); a group Default_Mix leaves out is at 1.0
##   (inferred).
## - The mix layers (the ducking), for the views that drive them later.
##
## The bus layout has one bus for each mixgroup an event here uses, at
## Default_Mix's vol, each sending straight to Master (CS2's All). Whether
## CS2 multiplies a group's vol by its parent's is not in the files (the
## research reads them as each group's own level), so the buses are flat.

const OUT_JSON := "res://reference/sounds/sound_events.json"
const OUT_PAGE := "res://reference/sounds/sound_events.md"
const OUT_BUSES := "res://default_bus_layout.tres"

const SOUNDEVENTS := "game/csgo/pak01_dir/soundevents/"
const STACKS := "game/csgo/pak01_dir/soundstacks/"
const MIXERS := "game/csgo/pak01_dir/scripts/soundmixers.txt"
const STEAM_INF := "game/csgo/steam.inf"

## The event files the game plays from, by path under soundevents/. The
## weapons, the grenades and the bomb; players (hits, deaths, the radio's
## beeps); physics (impacts, bounces); footsteps; the world; the UI (the
## round's beeps, the buy menu); the announcer; the default music kit; and
## dust2's ambience. Another kit or map is one more line.
const EVENT_FILES := [
	"game_sounds_weapons.vsndevts",
	"game_sounds_player.vsndevts",
	"game_sounds_physics.vsndevts",
	"game_sounds_footsteps.vsndevts",
	"game_sounds_world.vsndevts",
	"game_sounds_ui.vsndevts",
	"vo/announcer/game_sounds_cs2_classic.vsndevts",
	"music/valve_cs2_01/game_sounds_music.vsndevts",
	"ambience/game_sounds_amb_common.vsndevts",
	"ambience/game_sounds_dust2.vsndevts",
]

## Fields the table leaves out: the editor's own, and what only the stack's
## internals read.
const DROPPED_FIELDS := ["_system_properties", "display_broadcast"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: godot --headless --path . --script scripts/sound_event_tables.gd -- <GameTracking-CS2 checkout> [commit]")
		quit(1)
		return
	var root := args[0].trim_suffix("/") + "/"
	var commit := args[1] if args.size() > 1 else ""
	var failed := _write(root, commit)
	quit(1 if failed else 0)


func _write(root: String, commit: String) -> bool:
	var build := _steam_inf(root + STEAM_INF)
	var defaults := _stack_defaults(root + STACKS)
	var mixer: Variant = _read_kv3(root + MIXERS)
	if mixer == null:
		return true
	var events := {}
	var files_of := {}
	var counts := {}
	for file in EVENT_FILES:
		var parsed: Variant = _read_kv3(root + SOUNDEVENTS + file)
		if parsed == null:
			return true
		var label: String = file.get_file().get_basename()
		counts[label] = (parsed as Dictionary).size()
		for name in parsed:
			if not parsed[name] is Dictionary:
				continue
			events[name] = parsed[name]
			files_of[name] = label
	var missing_bases := {}
	var resolved := {}
	for name in events:
		resolved[name] = _resolve(name, events, missing_bases, 0)
	var table := {}
	var used_groups := {}
	var types_without_defaults := {}
	for name in resolved:
		var fields: Dictionary = resolved[name]
		var type := String(fields.get("type", "csgo_mega"))
		if not defaults.has(type):
			types_without_defaults[type] = true
		var type_defaults: Dictionary = defaults.get(type, {})
		var kept := {"file": files_of[name]}
		for field in fields:
			if field in DROPPED_FIELDS:
				continue
			var value: Variant = _plain(field, fields[field])
			if type_defaults.has(field) and _same(type_defaults[field], value) and field != "type":
				continue
			kept[field] = value
		table[name] = kept
		used_groups[String(fields.get("mixgroup", type_defaults.get("mixgroup", "All")))] = true
	var groups := _mixgroups(mixer)
	var layers := _mixlayers(mixer)
	var source := {
		"repository": "SteamDatabase/GameTracking-CS2",
		"commit": commit,
		"build": build.get("ClientVersion", ""),
		"patch": build.get("PatchVersion", ""),
		"date": build.get("VersionDate", ""),
		"files": counts,
	}
	var bus_groups := _bus_groups(used_groups.keys(), groups)
	if _save_json(source, defaults, groups, layers, table):
		return true
	if _save_buses(bus_groups, groups):
		return true
	_save_page(source, defaults, groups, bus_groups, table, missing_bases.keys(), types_without_defaults.keys())
	print("Wrote %d events from %d files (build %s) to %s, %d buses to %s." % [
		table.size(), EVENT_FILES.size(), source.build, OUT_JSON, bus_groups.size(), OUT_BUSES])
	return false


func _read_kv3(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		printerr("Cannot read %s" % path)
		return null
	var parsed: Variant = KV3.parse(text)
	if not parsed is Dictionary:
		printerr("Cannot parse %s" % path)
		return null
	return parsed


func _steam_inf(path: String) -> Dictionary:
	var result := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var parts := line.strip_edges().split("=", true, 1)
		if parts.size() == 2:
			result[parts[0]] = parts[1]
	return result


## Each stack's public defaults by stack name: {"csgo_mega": {"volume": 1.0, ...}}.
func _stack_defaults(directory: String) -> Dictionary:
	var result := {}
	var dir := DirAccess.open(directory)
	if dir == null:
		printerr("Cannot open %s" % directory)
		return result
	var files := dir.get_files()
	files.sort()
	for file in files:
		if not file.ends_with(".vsndstck"):
			continue
		var parsed: Variant = _read_kv3(directory + file)
		if parsed == null:
			continue
		for stack in parsed:
			var operators: Array = (parsed[stack] as Dictionary).get("operators", [])
			for operator in operators:
				if String(operator.get("name", "")) != "public":
					continue
				var fields := {}
				var variables: Dictionary = operator.get("operator_variables", {})
				for field in variables:
					var variable: Dictionary = variables[field]
					var value: Variant = _typed(String(variable.get("data_type", "")), variable.get("value", ""))
					if value != null:
						fields[field] = value
				result[stack] = fields
	return result


## A stack variable's value (always text there) as its type.
func _typed(data_type: String, value: Variant) -> Variant:
	# A list default is a block of value1, value2...: a curve's points as
	# "[x,y,slopes,modes]" text, or the words of a list (metadata).
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
		var items := []
		for key in keys:
			var item := String(value[key])
			if data_type == "float6":
				var numbers := item.trim_prefix("[").trim_suffix("]").split(",")
				if numbers.size() >= 2:
					items.append([_round(numbers[0].to_float()), _round(numbers[1].to_float())])
			else:
				items.append(item)
		return items
	if not value is String:
		return value
	var text: String = value
	match data_type:
		"float":
			return text.to_float()
		"int":
			return text.to_int()
		"bool":
			return text == "true" or text == "1"
		"float3":
			var parts := text.trim_prefix("[").trim_suffix("]").split(",")
			var numbers := []
			for part in parts:
				numbers.append(part.strip_edges().to_float())
			return numbers
		"float6":
			return []
		"vsnd":
			# sounds/common/null.vsnd: no file.
			return null
		_:
			return text


## An event's fields with its base's under them, recursively.
func _resolve(name: String, events: Dictionary, missing: Dictionary, depth: int) -> Dictionary:
	var fields: Dictionary = events[name]
	if not fields.has("base") or depth > 8:
		return fields.duplicate(true)
	var base := String(fields["base"])
	if not events.has(base):
		missing[base] = true
		return fields.duplicate(true)
	var result := _resolve(base, events, missing, depth + 1)
	for field in fields:
		if field != "base":
			result[field] = fields[field]
	return result


## A value as the table keeps it: curves as [x, y] points, a lone file as
## a list, "true" and "false" as bools.
func _plain(field: String, value: Variant) -> Variant:
	if field.ends_with("_curve") and value is Array:
		var points := []
		for point in value:
			if point is Array and point.size() >= 2:
				points.append([_round(point[0]), _round(point[1])])
		return points
	if field.begins_with("vsnd_files") and value is String:
		return [value]
	if value is String and (value == "true" or value == "false"):
		return value == "true"
	if value is float:
		return _round(value)
	if value is Array:
		var result := []
		for item in value:
			result.append(_round(item) if item is float else item)
		return result
	return value


func _round(value: float) -> float:
	return snappedf(value, 0.000001)


func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is bool and b is bool:
		return a == b
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


## {"Weapons": {"parent": "All", "vol": 0.6, "lvl": 0.3, "dsp": 1.0}, ...}
func _mixgroups(mixer: Dictionary) -> Dictionary:
	var result := {}
	for group in mixer.get("MixGroups", []):
		result[String(group.get("name", ""))] = {"parent": String(group.get("parent", "")), "vol": 1.0, "lvl": 1.0, "dsp": 1.0}
	var default_mix: Array = (mixer.get("SoundMixers", {}) as Dictionary).get("Default_Mix", [])
	for entry in default_mix:
		var name := String(entry.get("mixgroup", ""))
		if not result.has(name):
			result[name] = {"parent": "", "vol": 1.0, "lvl": 1.0, "dsp": 1.0}
		for key in ["vol", "lvl", "dsp"]:
			if entry.has(key):
				result[name][key] = _round(float(entry[key]))
	return result


## Each mix layer's groups and multipliers, and whatever else it sets.
func _mixlayers(mixer: Dictionary) -> Dictionary:
	var result := {}
	var layers: Dictionary = mixer.get("MixLayers", {})
	for name in layers:
		var layer: Dictionary = layers[name]
		var kept := {}
		for field in layer:
			if field == "Mixers":
				var mixers := {}
				for entry in layer[field]:
					mixers[String(entry.get("mixgroup", ""))] = _round(float(entry.get("vol", 1.0)))
				kept["vol"] = mixers
			else:
				kept[field] = _plain(field, layer[field])
		result[name] = kept
	return result


## The groups that get a bus: those the events use, less All (Master).
func _bus_groups(used: Array, groups: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for name in used:
		if name != "All" and not name.is_empty():
			result.append(name)
	result.sort()
	return result


func _save_json(source: Dictionary, defaults: Dictionary, groups: Dictionary, layers: Dictionary, table: Dictionary) -> bool:
	# One event to a line, sorted, so a CS2 update reads as a diff of the
	# events it changed.
	var lines := PackedStringArray()
	lines.append("{")
	lines.append("\"source\": %s," % JSON.stringify(source, "", true))
	lines.append("\"defaults\": {")
	lines.append(_lines_of(defaults))
	lines.append("},")
	lines.append("\"mixgroups\": {")
	lines.append(_lines_of(groups))
	lines.append("},")
	lines.append("\"mixlayers\": {")
	lines.append(_lines_of(layers))
	lines.append("},")
	lines.append("\"events\": {")
	lines.append(_lines_of(table))
	lines.append("}")
	lines.append("}")
	DirAccess.make_dir_recursive_absolute(OUT_JSON.get_base_dir())
	var file := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write %s" % OUT_JSON)
		return true
	file.store_string("\n".join(lines) + "\n")
	return false


func _lines_of(entries: Dictionary) -> String:
	var names: Array = entries.keys()
	names.sort()
	var lines := PackedStringArray()
	for name in names:
		lines.append("%s: %s" % [JSON.stringify(name), JSON.stringify(entries[name], "", true)])
	return ",\n".join(lines)


func _save_buses(bus_groups: PackedStringArray, groups: Dictionary) -> bool:
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	AudioServer.set_bus_volume_db(0, 0.0)
	for name in bus_groups:
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_volume_db(index, bus_db(float(groups.get(name, {}).get("vol", 1.0))))
		AudioServer.set_bus_send(index, &"Master")
	var error := ResourceSaver.save(AudioServer.generate_bus_layout(), OUT_BUSES)
	if error != OK:
		printerr("Cannot write %s (%s)" % [OUT_BUSES, error_string(error)])
		return true
	return false


## A mixgroup's vol as a bus's dB; 0 as Godot's floor.
static func bus_db(vol: float) -> float:
	return -80.0 if vol <= 0.0001 else snappedf(linear_to_db(vol), 0.0001)


func _save_page(source: Dictionary, defaults: Dictionary, groups: Dictionary, bus_groups: PackedStringArray,
		table: Dictionary, missing_bases: Array, types_without_defaults: Array) -> void:
	var events_in := {}
	for name in table:
		var group := String(table[name].get("mixgroup", defaults.get(String(table[name].get("type", "csgo_mega")), {}).get("mixgroup", "")))
		events_in[group] = int(events_in.get(group, 0)) + 1
	var lines := PackedStringArray()
	lines.append("# CS2's sound events")
	lines.append("")
	lines.append("Generated by `scripts/sound_events.sh` (`scripts/sound_event_tables.gd`); do not edit by hand.")
	lines.append("")
	lines.append("From SteamDatabase's GameTracking-CS2%s: **CS2 build %s, patch %s, %s** (`game/csgo/steam.inf`)." % [
		(" commit `%s`" % source.commit.substr(0, 7)) if not source.commit.is_empty() else "",
		source.build, source.patch, source.date])
	lines.append("")
	lines.append("`sound_events.json` beside this page holds %d events, each with its `base` resolved and only the fields that differ from its type's defaults, which it holds too (the `public` block of each stack in `soundstacks/`). Curves keep each point's position and value, not its slopes. `SoundEvents` (`src/audio/sound_events.gd`) plays from it; `default_bus_layout.tres` is written from its mixgroups." % table.size())
	lines.append("")
	lines.append("| File (under `soundevents/`) | Events |")
	lines.append("|---|---|")
	for file in EVENT_FILES:
		lines.append("| `%s` | %d |" % [file, int(source.files.get(String(file).get_file().get_basename(), 0))])
	lines.append("")
	lines.append("## Mixgroups and the buses")
	lines.append("")
	lines.append("`SoundMixers.Default_Mix` in `scripts/soundmixers.txt`. vol is the group's level and the bus's volume; lvl scales the source's own reverb and dsp the room's (audio-engine.md 2.1). A group Default_Mix leaves out is at 1.0 (inferred). Every bus sends to Master (CS2's All). Only the groups an event here uses have a bus.")
	lines.append("")
	lines.append("| Mixgroup | Parent | vol | Bus dB | lvl | dsp | Events |")
	lines.append("|---|---|---|---|---|---|---|")
	for name in bus_groups:
		var group: Dictionary = groups.get(name, {})
		lines.append("| %s | %s | %s | %s | %s | %s | %d |" % [name, group.get("parent", ""), group.get("vol", 1.0),
			bus_db(float(group.get("vol", 1.0))), group.get("lvl", 1.0), group.get("dsp", 1.0), int(events_in.get(name, 0))])
	lines.append("")
	lines.append("## What SoundEvents plays of it")
	lines.append("")
	lines.append("Read the way `csgo_mega` reads them (`reference/research/audio-engine.md` 1.3): who hears it (`localplayeronly`), blocks, instance limits, child events, delays, random volume and pitch, the distance, time and fade curves, the unfiltered-stereo curve as the panning, stealth (`suppression_*`), `self_destruct_time`, volume convars, and a sound that follows a node. Left for later: occlusion, reverb, the mix layers (in the table under `mixlayers`), doppler, the impact-speed and velocity curves, and the music stack's priorities, stop flags and sync points (issue 21).")
	lines.append("")
	lines.append("Inferred, for Local checks: a curve holds its end values past its last point (audio-engine.md A2); a mixgroup's vol is its own level, not multiplied by its parent's, so every bus sends straight to Master.")
	lines.append("")
	if not missing_bases.is_empty() or not types_without_defaults.is_empty():
		lines.append("## Gaps")
		lines.append("")
		if not missing_bases.is_empty():
			missing_bases.sort()
			lines.append("- Bases in files not read here, so their events keep only their own fields: %s." % ", ".join(missing_bases.map(func(n): return "`%s`" % n)))
		if not types_without_defaults.is_empty():
			types_without_defaults.sort()
			lines.append("- Types whose stack is not in `game/csgo` (so no defaults): %s." % ", ".join(types_without_defaults.map(func(n): return "`%s`" % n)))
		lines.append("")
	var file := FileAccess.open(OUT_PAGE, FileAccess.WRITE)
	file.store_string("\n".join(lines))
