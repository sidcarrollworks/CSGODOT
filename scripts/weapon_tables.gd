extends SceneTree

## Writes reference/weapons/models.md, sounds.md, timings.md (with
## timings.csv) and vdata.md (with vdata.csv) from what scripts/extract_assets.sh
## extracted, so the code that picks a gun's model, clips and sounds, times its
## draw and reload, and reads what the weapon sheet lacks, can be written on a
## machine without the assets.
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
## The equipment icons and the scope overlay, from the hud step.
const ICONS_ROOT := "res://assets/hud/panorama/images/icons/equipment"
const SCOPE_ROOT := "res://assets/hud/panorama/images/hud/scope"
## The first-person clips' own data (lengths and events), dumped by the
## weapon-animations step.
const CLIP_DATA := "res://assets/characters/animation/anims/viewmodel/clip_data.txt"
## The game's weapon tuning, decoded by the weapon-data step.
const VDATA := "res://assets/scripts/weapons.vdata.txt"

## The sheet's mode rows that are the second value of the game's two-valued
## fields (scoped, or silenced), by the main row.
const SECOND_VALUE_ROWS := {
	"USP-S (no silencer)": "USP-S (silencer)", "M4A1-S (no silencer)": "M4A1-S (silencer)",
	"AUG": "AUG (scoped)", "SG 553": "SG 553 (scoped)", "AWP": "AWP (scoped)", "SSG 08": "SSG 08 (scoped)",
	"G3SG1": "G3SG1 (scoped)", "SCAR-20": "SCAR-20 (scoped)",
}
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
		_write(OUT_DIR.path_join("timings.csv.import"), _keep_import(OUT_DIR.path_join("timings.csv")))
	var vdata := read_vdata(VDATA)
	if vdata.is_empty():
		_gaps.append("weapon tuning: %s" % VDATA)
	else:
		_write(OUT_DIR.path_join("vdata.md"), _vdata_page(source, date, vdata))
		_write(OUT_DIR.path_join("vdata.csv"), _vdata_csv(vdata))
		_write(OUT_DIR.path_join("vdata.csv.import"), _keep_import(OUT_DIR.path_join("vdata.csv")))
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
		"- Icons: `%s/<class less weapon_>.svg`, from `scripts/extract_assets.sh hud`; the M4A1-S and USP-S have `_off` icons for the silencer off." % ICONS_ROOT,
		"- The sniper scope's overlay: `%s/`, %s; the game composes it in code: the mask's opening over the lens's tint, with the cross drawn in the soft line." % [SCOPE_ROOT, ", ".join(Array(_files(SCOPE_ROOT, "png")).map(func(f: String) -> String: return "`%s`" % f)) if not _files(SCOPE_ROOT, "png").is_empty() else "not extracted"],
		"",
		"| Class | Sheet row | Folder | Model | Magazine | First person | Third person | Skeleton | Icon |",
		"|---|---|---|---|---|---|---|---|---|",
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
		var icon: String = String(gun[0]).trim_prefix("weapon_") + ".svg"
		if not FileAccess.file_exists(ICONS_ROOT.path_join(icon)):
			_gaps.append("%s icon %s" % [gun[0], icon])
			icon = ""
		lines.append("| `%s` | %s | `%s` | %s | %s | %s (%d) | %s (%d) | %s | %s |" % [
			gun[0], gun[1], gun[2], _code(model), _code(magazine),
			_code(gun[3]) if not first.is_empty() else "-", first.size(),
			_code(gun[4]) if not third.is_empty() else "-", third.size(), _code(skeleton), _code(icon),
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


## Godot takes any CSV for a table of translations and writes one file per
## column beside it; these are data, kept as they are, like the sheet.
static func _keep_import(path: String) -> String:
	return "[remap]\n\nimporter=\"keep\"\n\n[deps]\n\nsource_file=\"%s\"\n" % path


## The game's own tuning: what the sheet lacks (the zoom levels, deploy time,
## the reload's lockout, spread, the second recovery, muzzle, tracers, burst),
## and a check of every value the two share.
func _vdata_page(source: String, date: String, vdata: Dictionary) -> String:
	var lines := PackedStringArray([
		"# The game's own weapon tuning",
		"",
		"Written by `scripts/weapon_tables.gd` on %s from `scripts/weapons.vdata_c` in %s, as `scripts/extract_assets.sh weapon-data` decodes it. Do not edit by hand. `vdata.csv` beside this has every field of every gun, resolved through the file's inheritance (each gun's entry has a `_base`, its prefab, which has its class's, and so on up to `weapon_base`), one row each." % [date, source],
		"",
		"This is what the weapon sheet (`cs2_weapon_sheet.csv`) is transcribed from, less what the sheet leaves out. Two-valued fields are `[normal, alternate]`: unscoped and scoped for the scoped guns, silencer off and on for the M4A1-S and USP-S. Inaccuracy is in radians of the tangent (the sheet's figures are these x 1000); spread is separate from inaccuracy, and the sheet's figures include it.",
		"",
		"## Scopes",
		"",
		"The zoom levels L5 of `TODO.md` asked for. A level's FOV is CS's horizontal degrees at 4:3, like `fov`; the zoom times are how long each step takes (0 into level 1, 1 into level 2, 2 back out).",
		"",
		"| Class | Levels | FOV 1 | FOV 2 | Zoom times | Unzooms after a shot | Hides the view model | Speed, scoped |",
		"|---|---|---|---|---|---|---|---|",
	])
	for gun in GUNS:
		var fields: Dictionary = vdata.get(gun[0], {})
		if int(_vd(fields, "m_nZoomLevels")) <= 0:
			continue
		lines.append("| `%s` | %d | %d | %s | %s, %s, %s s | %s | %s | %s |" % [
			gun[0], int(_vd(fields, "m_nZoomLevels")), int(_vd(fields, "m_nZoomFOV1")),
			str(int(_vd(fields, "m_nZoomFOV2"))) if int(_vd(fields, "m_nZoomLevels")) > 1 else "-",
			_vd(fields, "m_flZoomTime0"), _vd(fields, "m_flZoomTime1"), _vd(fields, "m_flZoomTime2"),
			_yes(_vd(fields, "m_bUnzoomsAfterShot")), _yes(_vd(fields, "m_bHideViewModelWhenZoomed")),
			_vd(fields, "m_flMaxSpeed", 1),
		])
	lines.append_array(PackedStringArray([
		"",
		"## What the sheet does not have",
		"",
		"- Deploy: seconds from drawing the gun to firing it (the draw clips in `timings.md` are the same lengths, or close).",
		"- Reload lockout: seconds after starting a reload that the gun cannot fire, which is shorter than the clip: the tail of a reload can be cut short by firing.",
		"- Spread: the gun's own cone, inside the inaccuracy; normal, alternate.",
		"- Recovery, final: a second, slower recovery time the firing penalty falls by from the round the transition starts at to the one it ends at, blended; stand and crouch.",
		"- Muzzle: where the muzzle flash and tracers start, in the model's units (x forward).",
		"- Tracers: one round in so many draws one; 0 is none.",
		"- Burst: the cycle time in burst mode and the time between a burst's rounds.",
		"",
		"| Class | Deploy | Reload lockout | Spread | Recovery, final (stand, crouch; rounds) | Muzzle | Tracers | Burst |",
		"|---|---|---|---|---|---|---|---|",
	]))
	for gun in GUNS:
		var fields: Dictionary = vdata.get(gun[0], {})
		if fields.is_empty():
			_gaps.append("%s in the weapon tuning" % gun[0])
			continue
		var spread := "%s, %s" % [_vd(fields, "m_flSpread", 0), _vd(fields, "m_flSpread", 1)]
		var burst := "-"
		if _vd(fields, "m_bHasBurstMode") == 1.0:
			burst = "%s s cycle, %s s apart" % [_vd(fields, "m_flCycleTimeWhenInBurstMode"), _vd(fields, "m_flTimeBetweenBurstShots")]
		lines.append("| `%s` | %s s | %s s | %s | %s, %s; %d to %d | %s | %s | %s |" % [
			gun[0], _vd(fields, "m_flDeployDuration"), snappedf(float(_vd(fields, "m_flDisallowAttackAfterReloadStartDuration")), 0.001),
			spread, _vd(fields, "m_flRecoveryTimeStandFinal"), _vd(fields, "m_flRecoveryTimeCrouchFinal"),
			int(_vd(fields, "m_nRecoveryTransitionStartBullet")), int(_vd(fields, "m_nRecoveryTransitionEndBullet")),
			String(fields.get("m_vecMuzzlePos0", "-")), int(_vd(fields, "m_nTracerFrequency")), burst,
		])
	lines.append_array(_cross_check(vdata))
	return "\n".join(lines) + "\n"


## Every value the sheet and the game share, compared: the sheet's main row
## against the first of a two-valued field, its scoped or silenced row
## against the second.
func _cross_check(vdata: Dictionary) -> PackedStringArray:
	# Sheet column, the game's value for it, and how close is the same.
	var checks := [
		["Price", func(f: Dictionary, i: int) -> float: return _vd(f, "m_nPrice", i), 0.5],
		["Kill Award", func(f: Dictionary, i: int) -> float: return _vd(f, "m_nKillAward", i), 0.5],
		["Damage", func(f: Dictionary, i: int) -> float: return _vd(f, "m_nDamage", i), 0.5],
		["Bullets", func(f: Dictionary, i: int) -> float: return _vd(f, "m_nNumBullets", i), 0.5],
		["Armor Penetration", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flArmorRatio", i) * 0.5, 0.0006],
		["Damage Falloff @ 500U", func(f: Dictionary, i: int) -> float: return 1.0 - _vd(f, "m_flRangeModifier", i), 0.0006],
		["Headshot Multiplier", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flHeadshotMultiplier", i), 0.01],
		["Fire Rate (RPM)", func(f: Dictionary, i: int) -> float: return 60.0 / _vd(f, "m_flCycleTime", i), 0.6],
		["Penetration Power", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flPenetration", i), 0.006],
		["Magazine Size", func(f: Dictionary, i: int) -> float: return _vd(f, "m_iMaxClip1", i), 0.5],
		["Mobility", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flMaxSpeed", i), 0.5],
		["Bullet Range", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flRange", i), 0.5],
		["Standing Inaccuracy", func(f: Dictionary, i: int) -> float: return (_vd(f, "m_flInaccuracyStand", i) + _vd(f, "m_flSpread", i)) * 1000.0, 0.02],
		["Crouching Inaccuracy", func(f: Dictionary, i: int) -> float: return (_vd(f, "m_flInaccuracyCrouch", i) + _vd(f, "m_flSpread", i)) * 1000.0, 0.02],
		["Running Inaccuracy", func(f: Dictionary, i: int) -> float: return (_vd(f, "m_flInaccuracyMove", i) + _vd(f, "m_flInaccuracyStand", i) + _vd(f, "m_flSpread", i)) * 1000.0, 0.02],
		["Inaccuracy at Jump Apex", func(f: Dictionary, i: int) -> float: return (_vd(f, "m_flInaccuracyJump", i) + _vd(f, "m_flInaccuracyStand", i) + _vd(f, "m_flSpread", i)) * 1000.0, 0.02],
		["Inaccuracy From Firing", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flInaccuracyFire", i) * 1000.0, 0.02],
		["Recovery TimeCrouch", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flRecoveryTimeCrouch", i), 0.0005],
		["Recovery TimeStand", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flRecoveryTimeStand", i), 0.0005],
		["Recoil Amount", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flRecoilMagnitude", i), 0.05],
		["Recoil Angle Variance", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flRecoilAngleVariance", i), 0.05],
		["Recoil Amount Variance", func(f: Dictionary, i: int) -> float: return _vd(f, "m_flRecoilMagnitudeVariance", i), 0.05],
	]
	var agree := 0
	var differ := PackedStringArray()
	for gun in GUNS:
		var fields: Dictionary = vdata.get(gun[0], {})
		if fields.is_empty() or not WeaponSheet.has(gun[1]):
			continue
		var rows := [[gun[1], ""]]
		if SECOND_VALUE_ROWS.has(gun[1]):
			rows.append([gun[1], SECOND_VALUE_ROWS[gun[1]]])
		for index in rows.size():
			for check in checks:
				var text := WeaponSheet.text_for_mode(rows[index][0], rows[index][1], check[0]) if not rows[index][1].is_empty() \
					else WeaponSheet.raw(rows[index][0], check[0])
				if text.strip_edges().is_empty() or text.strip_edges() == "-":
					continue
				var sheet := WeaponSheet.parse_number(text)
				if is_nan(sheet):
					continue
				var game: float = (check[1] as Callable).call(fields, index)
				if absf(game - sheet) <= float(check[2]) + 1e-9:
					agree += 1
				else:
					# A mode row's "-" means "as the main row"; where the game
					# gives the mode a value of its own, that is what differs.
					var inherited: bool = not rows[index][1].is_empty() and WeaponSheet.raw(rows[index][1], check[0]).strip_edges() in ["", "-"]
					differ.append("| %s | %s | %s%s | %s |" % [
						rows[index][1] if not rows[index][1].is_empty() else rows[index][0], check[0], text,
						" (the sheet's \"-\": as unscoped)" if inherited else "", snappedf(game, 0.0001),
					])
	var lines := PackedStringArray([
		"",
		"## Against the sheet",
		"",
		"%d values the two share agree; %d do not. The sheet's running and jump-apex figures are its own sums, standing inaccuracy + spread + the movement's own term, and are compared that way; its ladder and landing figures are composites of another kind (landing scales the game's term by the fall) and are left out. The sheet was last updated for 18 March 2026; where the two differ, the game is the newer." % [agree, differ.size()],
		"",
	])
	if not differ.is_empty():
		lines.append_array(PackedStringArray(["| Sheet row | Column | Sheet | Game |", "|---|---|---|---|"]))
		lines.append_array(differ)
	return lines


func _vdata_csv(vdata: Dictionary) -> String:
	var lines := PackedStringArray(["class,field,value"])
	for gun in GUNS:
		var fields: Dictionary = vdata.get(gun[0], {})
		var keys := fields.keys()
		keys.sort()
		for key in keys:
			var value := String(fields[key]).replace("\"", "").replace("resource_name:", "").replace("resource:", "")
			value = value.trim_prefix("[").trim_suffix("]").strip_edges().replace(", ", "|").replace(",", "|")
			lines.append("%s,%s,%s" % [gun[0], key, value])
	return "\n".join(lines) + "\n"


## A field's value: a number (true and false as 1 and 0), or its text if it is
## not one. A two-valued field gives its index-th value, the last if short.
static func _vd(fields: Dictionary, key: String, index: int = 0) -> Variant:
	var text := String(fields.get(key, "")).strip_edges()
	if text.begins_with("["):
		var parts := text.trim_prefix("[").trim_suffix("]").split(",", false)
		text = parts[mini(index, parts.size() - 1)].strip_edges() if not parts.is_empty() else ""
	text = text.replace("resource_name:", "").replace("\"", "")
	if text == "true":
		return 1.0
	if text == "false":
		return 0.0
	return float(text) if text.is_valid_float() else (text if not text.is_empty() else 0.0)


static func _yes(value: Variant) -> String:
	return "yes" if value == 1.0 else "no"


## Reads the decoded weapons.vdata: per top-level entry (weapon_awp,
## weapon_awp_prefab, sniper_rifle...), its fields as the text after " = ",
## merged over its _base's, and theirs, so a gun's entry has everything.
## Only one-line values are kept: numbers, strings, flags and [ a, b ] pairs.
static func read_vdata(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var own := {}
	var current := ""
	var entry := RegEx.create_from_string("^\t([A-Za-z_0-9]+) = ?$")
	var field := RegEx.create_from_string("^\t\t([A-Za-z_0-9]+) = (.+)$")
	while not file.eof_reached():
		var line := file.get_line()
		var found := entry.search(line)
		if found != null:
			current = found.get_string(1)
			own[current] = {}
			continue
		if current.is_empty():
			continue
		found = field.search(line)
		if found != null and not found.get_string(2).strip_edges().is_empty():
			(own[current] as Dictionary)[found.get_string(1)] = found.get_string(2).strip_edges()
	var resolved := {}
	for name in own:
		resolved[name] = _resolved(own, name, [])
	return resolved


static func _resolved(own: Dictionary, name: String, seen: Array) -> Dictionary:
	var fields: Dictionary = own.get(name, {})
	var base := String(fields.get("_base", "")).replace("\"", "")
	var merged := {}
	if not base.is_empty() and base not in seen:
		merged = _resolved(own, base, seen + [name])
	merged.merge(fields, true)
	return merged


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
