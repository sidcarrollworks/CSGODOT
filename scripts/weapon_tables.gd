extends SceneTree

## Writes reference/weapons/models.md, sounds.md and timings.md (with
## timings.csv) from what scripts/extract_assets.sh extracted, so the code that
## picks a gun's model, clips and sounds, and times its draw and reload, can be
## written on a machine without the assets.
##
##   godot --headless --path . --script scripts/weapon_tables.gd
##
## (scripts/extract_assets.sh weapons and sounds run this for you.) The
## class-to-folder table below is the one fact written by hand: CS2's folder
## and file names do not follow the class names (weapon_m4a1 is the M4A4, in
## m4a4/, and its sounds share m4a1/ with the M4A1-S). Everything else is
## listed from disk, so a CS2 update that renames a file shows up here as a
## gap rather than as a path that no longer exists. CS2_VERSION, if set, is
## recorded as the build the files came from.

const WEAPONS_ROOT := "res://assets/weapons/weapons/models"
const FIRST_PERSON_ROOT := "res://assets/characters/animation/anims/viewmodel"
const THIRD_PERSON_ROOT := "res://assets/characters/animation/anims/world"
const SKELETONS_ROOT := "res://assets/characters/animation/skeletons/weapons"
const SOUNDS_ROOT := "res://assets/sounds/sounds/weapons"
## The first-person clips' own data (lengths and events), dumped by the
## weapon-animations step.
const CLIP_DATA := "res://assets/characters/animation/anims/viewmodel/clip_data.txt"
const OUT_DIR := "res://reference/weapons"

## Per class: the sheet row, the model's folder, the first-person and
## third-person clip sets (under viewmodel/ and world/), the skeleton, the
## sound folder, and for a folder two guns share, the files that are this
## one's.
const GUNS := [
	["weapon_glock", "Glock-18", "glock18", "pistol/pistol_glock18", "pistol/pistol_glock", "glock18", "glock18", ""],
	["weapon_hkp2000", "P2000", "hkp2000", "pistol/pistol_hkp2000", "pistol/pistol_hkp2000", "hkp2000", "hkp2000", ""],
	["weapon_usp_silencer", "USP-S (no silencer)", "usp_silencer", "pistol/_default_pistol", "pistol/pistol_usp", "usp_silencer", "usp", ""],
	["weapon_elite", "Dual Berettas", "elite", "pistol/pistol_elite", "pistol/pistol_elite", "elite", "elite", ""],
	["weapon_p250", "P250", "p250", "pistol/pistol_p250", "pistol/pistol_p250", "p250", "p250", ""],
	["weapon_tec9", "Tec-9", "tec9", "pistol/pistol_tec9", "pistol/pistol_tec9", "tec9", "tec9", ""],
	["weapon_fiveseven", "Five-SeveN", "fiveseven", "pistol/pistol_fiveseven", "pistol/pistol_fiveseven", "fiveseven", "fiveseven", ""],
	["weapon_cz75a", "CZ75 Auto", "cz75a", "pistol/pistol_cz75a", "pistol/pistol_cz75a", "cz75a", "cz75a", ""],
	["weapon_deagle", "Desert Eagle", "deagle", "pistol/pistol_deagle", "pistol/pistol_deagle", "deagle", "deagle", ""],
	["weapon_revolver", "R8 Revolver", "revolver", "pistol/pistol_revolver", "pistol/pistol_revolver", "revolver", "revolver", ""],
	["weapon_nova", "Nova", "nova", "rifle/rifle_nova", "rifle/rifle_nova", "nova", "nova", ""],
	["weapon_xm1014", "XM1014", "xm1014", "rifle/rifle_xm1014", "rifle/rifle_xm1014", "xm1014", "xm1014", ""],
	["weapon_sawedoff", "Sawed-Off", "sawedoff", "rifle/rifle_sawedoff", "rifle/rifle_sawedoff", "sawedoff", "sawedoff", ""],
	["weapon_mag7", "Mag-7", "mag7", "rifle/rifle_mag7", "rifle/rifle_mag7", "mag7", "mag7", ""],
	["weapon_mac10", "MAC-10", "mac10", "rifle/rifle_mac10", "rifle/rifle_mac10", "mac10", "mac10", ""],
	["weapon_mp9", "MP9", "mp9", "rifle/rifle_mp9", "rifle/rifle_mp9", "mp9", "mp9", ""],
	["weapon_mp7", "MP7", "mp7", "rifle/rifle_mp7", "rifle/rifle_mp7", "mp7", "mp7", ""],
	["weapon_mp5sd", "MP5-SD", "mp5sd", "rifle/rifle_mp5sd", "rifle/rifle_mp5sd", "mp5sd", "mp5", ""],
	["weapon_ump45", "UMP-45", "ump45", "rifle/rifle_ump45", "rifle/rifle_ump45", "ump45", "ump45", ""],
	["weapon_p90", "P90", "p90", "rifle/rifle_p90", "rifle/rifle_p90", "p90", "p90", ""],
	["weapon_bizon", "PP-Bizon", "bizon", "rifle/rifle_bizon", "rifle/rifle_bizon", "bizon", "bizon", ""],
	["weapon_galilar", "Galil AR", "galilar", "rifle/rifle_galilar", "rifle/rifle_galilar", "galil", "galilar", ""],
	["weapon_famas", "FAMAS", "famas", "rifle/rifle_famas", "rifle/rifle_famas", "famas", "famas", ""],
	["weapon_ak47", "AK-47", "ak47", "rifle/rifle_ak", "rifle/rifle_ak", "ak47", "ak47", ""],
	["weapon_m4a1", "M4A4", "m4a4", "rifle/rifle_m4a4", "rifle/rifle_m4a4", "m4a4", "m4a1", "^m4a1_(0[0-9]|addammo|bolt|clip|distant|draw)"],
	["weapon_m4a1_silencer", "M4A1-S (no silencer)", "m4a1_silencer", "rifle/_default_rifle", "rifle/rifle_m4a1_silencer", "m4a1_silencer", "m4a1", "^m4a1_(silencer|us_|addammo|clip|draw)"],
	["weapon_sg556", "SG 553", "sg556", "rifle/rifle_sg556", "rifle/rifle_sg556", "sg556", "sg556", ""],
	["weapon_aug", "AUG", "aug", "rifle/rifle_aug", "rifle/rifle_aug", "aug", "aug", ""],
	["weapon_m249", "M249", "m249", "rifle/rifle_m249", "rifle/rifle_m249", "m249", "m249", ""],
	["weapon_negev", "Negev", "negev", "rifle/rifle_negev", "rifle/rifle_negev", "negev", "negev", ""],
	["weapon_ssg08", "SSG 08", "ssg08", "rifle/rifle_ssg08", "rifle/rifle_ssg08", "ssg08", "ssg08", ""],
	["weapon_awp", "AWP", "awp", "rifle/rifle_awp", "rifle/rifle_awp", "awp", "awp", ""],
	["weapon_g3sg1", "G3SG1", "g3sg1", "rifle/rifle_g3sg1", "rifle/rifle_g3sg1", "g3sg1", "g3sg1", ""],
	["weapon_scar20", "SCAR-20", "scar20", "rifle/rifle_scar20", "rifle/rifle_scar", "scar20", "scar20", ""],
]

## A sound's role, by what its file is called; the first that matches.
const ROLES := [
	["distant", "distant"],
	["draw", "draw"],
	["zoom", "zoom"],
	["silencer", "silencer_(on|off|screw)"],
	["inspect", "inspect|lookat|taunt|clean"],
	["mode", "element|auto_semiauto"],
	["reload", "clip|bolt|slide|pump|shell|box|cover|chain|addammo|catch|handle|hammer|prepare|side|reload|mech|hit|jangle"],
	["fire", "(_0[0-9]|-1|-1_0[0-9]|_unsilenced_0[0-9]|_us_0[0-9]|_silencer_01)$"],
]
const ROLE_ORDER := ["fire", "distant", "draw", "reload", "silencer", "zoom", "mode", "inspect"]

var _gaps: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var version := OS.get_environment("CS2_VERSION")
	var source := "CS2 %s" % version if not version.is_empty() else "CS2"
	var date := Time.get_date_string_from_system()
	_write(OUT_DIR.path_join("models.md"), _models_page(source, date))
	_write(OUT_DIR.path_join("sounds.md"), _sounds_page(source, date))
	var clips := read_clip_data(CLIP_DATA)
	if clips.is_empty():
		_gaps.append("clip timings: %s" % CLIP_DATA)
	else:
		_write(OUT_DIR.path_join("timings.md"), _timings_page(source, date, clips))
		_write(OUT_DIR.path_join("timings.csv"), _timings_csv(clips))
		# Godot takes any CSV for a table of translations and writes one file
		# per column beside it; this one is data, kept as it is, like the sheet.
		_write(OUT_DIR.path_join("timings.csv.import"), "[remap]\n\nimporter=\"keep\"\n\n[deps]\n\nsource_file=\"%s\"\n" % OUT_DIR.path_join("timings.csv"))
	print("weapon tables: %d guns, %d gaps, written to %s" % [GUNS.size(), _gaps.size(), OUT_DIR])
	for gap in _gaps:
		print("  missing: ", gap)
	quit(0)


func _models_page(source: String, date: String) -> String:
	var lines := PackedStringArray([
		"# Every gun's files",
		"",
		"Written by `scripts/weapon_tables.gd` on %s from what `scripts/extract_assets.sh weapons` extracted out of %s. Do not edit by hand: re-run the extraction, or the script on its own. Paths are relative to the roots below; a dash is something the extraction did not produce." % [date, source],
		"",
		"- Models: `%s/<folder>/`, one glTF for the gun and one for its magazine." % WEAPONS_ROOT,
		"- First person: `%s/<set>/`, one glTF per clip, each carrying the arms' and the gun's skeletons. The shared `_default_` sets are the M4A1-S's (`rifle/_default_rifle`) and the USP-S's (`pistol/_default_pistol`); SMGs, shotguns, snipers and machine guns are all `rifle/` sets." % FIRST_PERSON_ROOT,
		"- Third person: `%s/<set>/`, the gun's own draw, idle, reload and fire, standing and crouched, over the shared locomotion of `rifle/_default_rifle` or `pistol/_default_pistol`." % THIRD_PERSON_ROOT,
		"- Skeletons: `%s/<name>.vnmskel`." % SKELETONS_ROOT,
		"",
		"| Class | Sheet row | Folder | Model | Magazine | First person | Third person | Skeleton |",
		"|---|---|---|---|---|---|---|---|",
	])
	var clip_lines := PackedStringArray()
	for gun in GUNS:
		var model_dir := WEAPONS_ROOT.path_join(gun[2])
		var model := ""
		var magazine := ""
		# Each model comes with a _physics glTF of its collision beside it.
		for file in _files(model_dir, "gltf"):
			if file.get_basename().ends_with("_physics") or not file.begins_with("weapon_"):
				continue
			if file.get_basename().ends_with("_mag"):
				magazine = file
			else:
				model = file
		if model.is_empty():
			_gaps.append("%s model in %s" % [gun[0], model_dir])
		var first := _clips(FIRST_PERSON_ROOT.path_join(gun[3]))
		var third := _clips(THIRD_PERSON_ROOT.path_join(gun[4]))
		if first.is_empty():
			_gaps.append("%s first-person set %s" % [gun[0], gun[3]])
		if third.is_empty():
			_gaps.append("%s third-person set %s" % [gun[0], gun[4]])
		var skeleton: String = gun[5] if FileAccess.file_exists(SKELETONS_ROOT.path_join(gun[5] + ".vnmskel")) else ""
		if skeleton.is_empty():
			_gaps.append("%s skeleton %s" % [gun[0], gun[5]])
		lines.append("| `%s` | %s | `%s` | %s | %s | %s (%d) | %s (%d) | %s |" % [
			gun[0], gun[1], gun[2], _code(model), _code(magazine),
			_code(gun[3]) if not first.is_empty() else "-", first.size(),
			_code(gun[4]) if not third.is_empty() else "-", third.size(), _code(skeleton),
		])
		clip_lines.append("| `%s` | %s | %s |" % [gun[0], ", ".join(first) if not first.is_empty() else "-", ", ".join(third) if not third.is_empty() else "-"])
	lines.append_array(PackedStringArray([
		"",
		"## The clips in each set",
		"",
		"By the name the file carries, less the set's suffix (`draw_ak` is `draw`). `shoot1` is the firing clip; `lookat01` the inspect; a pistol's `_empty` clips are for the last round, with the slide back.",
		"",
		"| Class | First person | Third person |",
		"|---|---|---|",
	]))
	lines.append_array(clip_lines)
	return "\n".join(lines) + "\n"


func _sounds_page(source: String, date: String) -> String:
	var lines := PackedStringArray([
		"# Every gun's sounds",
		"",
		"Written by `scripts/weapon_tables.gd` on %s from what `scripts/extract_assets.sh sounds` extracted out of %s. Do not edit by hand." % [date, source],
		"",
		"Each is a file stem under `%s/<folder>/`, decompiled to the audio it holds (`.wav`, a few `.mp3`); variants of one sound are numbered, and `SoundBank` plays a set from the stem they share. The roles are read off the names, so a name that says nothing (`zoom`) is filed by what it does say. The M4A4 and the M4A1-S share the `m4a1` folder: the M4A4 fires `m4a1_0N`, the M4A1-S `m4a1_silencer_01` silenced and `m4a1_us_0N` without. The USP-S fires `usp_0N` silenced and `usp_unsilenced_0N` without." % SOUNDS_ROOT,
		"",
		"Beside the folders, sounds every gun shares: %s." % ", ".join(_stems(SOUNDS_ROOT, "")),
		"",
		"| Class | Folder | " + " | ".join(_headings()) + " |",
		"|---|---|" + "---|".repeat(ROLE_ORDER.size()),
	])
	for gun in GUNS:
		var folder: String = gun[6]
		var stems := _stems(SOUNDS_ROOT.path_join(folder), gun[7])
		if stems.is_empty():
			_gaps.append("%s sounds in %s" % [gun[0], folder])
		var by_role := {}
		for stem in stems:
			var role := _role(stem)
			# A packed array is a value: append to it and put it back.
			var in_role: PackedStringArray = by_role.get(role, PackedStringArray())
			in_role.append(stem)
			by_role[role] = in_role
		var cells := PackedStringArray()
		for role in ROLE_ORDER:
			cells.append(", ".join(by_role.get(role, PackedStringArray())) if by_role.has(role) else "-")
		lines.append("| `%s` | `%s` | %s |" % [gun[0], folder, " | ".join(cells)])
	return "\n".join(lines) + "\n"


## The first-person timings: per gun, the draw, the reload to the rounds going
## in and to ready, the firing clip, and what else the set's clips mark.
func _timings_page(source: String, date: String, clips: Dictionary) -> String:
	var lines := PackedStringArray([
		"# Every gun's timings",
		"",
		"Written by `scripts/weapon_tables.gd` on %s from the first-person clips of %s, as `scripts/extract_assets.sh weapon-animations` reads them. Do not edit by hand. `timings.csv` beside this has every clip's length and every event in it, sounds included, one row each." % [date, source],
		"",
		"These are the game's own animation data, not measurements. Each clip is authored at 30 frames a second and carries events at points through it; the ones that matter here:",
		"",
		"- `WPN_RELOAD_ADD_AMMO`: the moment a reload puts the rounds in. A reload cancelled before it keeps the old magazine.",
		"- The clip's end: the gun is ready again. The reload clips' lengths are CS2's reload times as they are quoted (AK-47 2.43 s, AWP 3.67 s, Glock 2.27 s).",
		"- `WPN_RELOAD_INTRO`, `_LOOP`, `_OUTRO`: the shotguns that load a shell at a time mark the one clip's three parts; the loop repeats per shell.",
		"- `WPN_SILENCER_ATTACH`, `_DETACH`: the moment the silencer is on or off, part way through the clip.",
		"",
		"The firing clip is how long the gun model moves after a round, not how often it fires (the sheet's fire rate is that); the AK's 0.767 s against the 0.644 s its model was seen to settle in, the clip's last frames holding still.",
		"",
		"| Class | Set | Draw | Reload: rounds in, ready | Empty reload: rounds in, ready | Firing clip | Also |",
		"|---|---|---|---|---|---|---|",
	])
	for gun in GUNS:
		var named := _set_clips(clips, gun[3])
		if named.is_empty():
			_gaps.append("%s clip timings for %s" % [gun[0], gun[3]])
			continue
		var fire: String = "shoot1" if named.has("shoot1") else ("shoot_right1" if named.has("shoot_right1") else "")
		var also := PackedStringArray()
		var reload: Dictionary = named.get("reload", {})
		var intro := _event_at(reload, "WPN_RELOAD_LOOP")
		var outro := _event_at(reload, "WPN_RELOAD_OUTRO")
		if intro >= 0.0 and outro >= 0.0:
			also.append("shells: first at %s, then one every %s, the round in %s into each; the finish %s" % [
				_seconds(intro), _seconds(outro - intro), _seconds(_event_at(reload, "WPN_RELOAD_ADD_AMMO") - intro),
				_seconds(float(reload["duration"]) - outro),
			])
		for clip in ["silencer_attach", "silencer_detach"]:
			if named.has(clip):
				var switch := _event_at(named[clip], "WPN_SILENCER_ATTACH" if clip == "silencer_attach" else "WPN_SILENCER_DETACH")
				also.append("%s: %s, done %s" % [clip.replace("_", " "), _seconds(switch) if switch >= 0.0 else "-", _seconds(named[clip]["duration"])])
		for clip in ["prepare_shoot", "draw2", "draw_silenced"]:
			if named.has(clip):
				also.append("%s %s" % [clip.replace("_", " "), _seconds(named[clip]["duration"])])
		lines.append("| `%s` | `%s` | %s | %s | %s | %s | %s |" % [
			gun[0], gun[3],
			_seconds(named["draw"]["duration"]) if named.has("draw") else "-",
			_reload_cell(named.get("reload", {})), _reload_cell(named.get("reload_empty", {})),
			_seconds(named[fire]["duration"]) if not fire.is_empty() else "-",
			"; ".join(also) if not also.is_empty() else "",
		])
	return "\n".join(lines) + "\n"


func _timings_csv(clips: Dictionary) -> String:
	var lines := PackedStringArray(["class,clip,duration,kind,event,at,for"])
	for gun in GUNS:
		var named := _set_clips(clips, gun[3])
		var names := named.keys()
		names.sort()
		for clip in names:
			var data: Dictionary = named[clip]
			lines.append("%s,%s,%.4f,,,," % [gun[0], clip, data["duration"]])
			for event in data["events"]:
				lines.append("%s,%s,%.4f,%s,%s,%.4f,%.4f" % [gun[0], clip, data["duration"], event["kind"], event["name"], event["at"], event["for"]])
	return "\n".join(lines) + "\n"


## A set's clips from the parsed data, by their short names.
func _set_clips(clips: Dictionary, clip_set: String) -> Dictionary:
	var prefix := "animation/anims/viewmodel/%s/" % clip_set
	var paths := PackedStringArray()
	for path in clips:
		if String(path).begins_with(prefix) and not String(path).trim_prefix(prefix).contains("/"):
			paths.append(path)
	var suffix := RigModel.common_suffix(paths)
	var named := {}
	for path in paths:
		named[String(path).get_file().get_basename().trim_suffix("_" + suffix)] = clips[path]
	return named


static func _event_at(clip: Dictionary, name: String) -> float:
	for event in clip.get("events", []):
		if event["name"] == name:
			return event["at"]
	return -1.0


static func _reload_cell(clip: Dictionary) -> String:
	if clip.is_empty():
		return "-"
	var in_at := _event_at(clip, "WPN_RELOAD_ADD_AMMO")
	return "%s, %s" % [_seconds(in_at) if in_at >= 0.0 else "-", _seconds(clip["duration"])]


static func _seconds(value: float) -> String:
	return "%.2f s" % value


## Reads a Source2Viewer-CLI dump of clips' DATA blocks ("-b DATA" over many
## .vnmclip_c files): per clip path, its length in seconds and its events,
## each {"kind": ID, Sound or Particle, "name": the ID, the sound event or the
## particle's config, "at" and "for" in seconds}. The file stores event times
## as fractions of the clip; they come out in seconds.
static func read_clip_data(path: String) -> Dictionary:
	var clips := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return clips
	var header := RegEx.create_from_string("^\\[\\d+/\\d+\\] (\\S+\\.vnmclip_c)$")
	var number := RegEx.create_from_string("= (-?[0-9.eE+-]+)$")
	var quoted := RegEx.create_from_string("= (?:resource:)?\"([^\"]*)\"")
	var current := {}
	var in_events := false
	var event := {}
	var pending := ""
	while not file.eof_reached():
		var line := file.get_line()
		var found := header.search(line)
		if found != null:
			current = {"duration": -1.0, "events": []}
			clips[found.get_string(1).trim_suffix("_c").trim_suffix(".vnmclip") + ".vnmclip_c"] = current
			in_events = false
			continue
		if current.is_empty():
			continue
		if line.begins_with("\tm_flDuration = ") and float(current["duration"]) < 0.0:
			current["duration"] = float(number.search(line).get_string(1))
		elif line == "\tm_events = ":
			in_events = true
		elif in_events and line == "\t]":
			in_events = false
		elif in_events:
			var stripped := line.strip_edges()
			if stripped.begins_with("_class = "):
				var kind := quoted.search(stripped).get_string(1).trim_prefix("CNm").trim_suffix("Event")
				event = {"kind": kind, "name": "", "at": 0.0, "for": 0.0}
				(current["events"] as Array).append(event)
			elif stripped.begins_with("m_flStartTime"):
				pending = "at"
			elif stripped.begins_with("m_flDuration"):
				pending = "for"
			elif stripped.begins_with("m_flValue = ") and not pending.is_empty() and not event.is_empty():
				event[pending] = float(number.search(stripped).get_string(1)) * maxf(float(current["duration"]), 0.0)
				pending = ""
			elif not event.is_empty() and (stripped.begins_with("m_ID = ") or stripped.begins_with("m_name = ") or stripped.begins_with("m_config = ")):
				var value := quoted.search(stripped)
				if value != null and not value.get_string(1).is_empty():
					event["name"] = value.get_string(1)
	return clips


static func _headings() -> PackedStringArray:
	var out := PackedStringArray()
	for role in ROLE_ORDER:
		out.append("Reload and handling" if role == "reload" else role.capitalize())
	return out


static func _role(stem: String) -> String:
	for rule in ROLES:
		if RegEx.create_from_string(rule[1]).search(stem) != null:
			return rule[0]
	return "reload"


## The clip names in a set's folder, less the suffix most of them share
## (the set's weapon, which is not always its folder's: pistol_glock18's
## clips end in _glock).
func _clips(dir: String) -> PackedStringArray:
	var files := _files(dir, "gltf")
	var counts := {}
	for file in files:
		var last := file.get_basename().get_slice("_", file.get_basename().get_slice_count("_") - 1)
		counts[last] = counts.get(last, 0) + 1
	var suffix := ""
	for last in counts:
		if suffix.is_empty() or counts[last] > counts[suffix]:
			suffix = last
	var out := PackedStringArray()
	for file in files:
		out.append(file.get_basename().trim_suffix("_" + suffix))
	return out


## The audio file stems in a folder, those matching a filter if one is given.
func _stems(dir: String, filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	var pattern := RegEx.create_from_string(filter) if not filter.is_empty() else null
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() not in ["wav", "mp3"]:
			continue
		var stem := file.get_basename()
		if pattern == null or pattern.search(stem) != null:
			if stem not in out:
				out.append(stem)
	out.sort()
	return out


static func _files(dir: String, extension: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			out.append(file)
	out.sort()
	return out


static func _code(text: String) -> String:
	return "`%s`" % text if not text.is_empty() else "-"


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("could not write %s" % path)
		return
	file.store_string(text)
