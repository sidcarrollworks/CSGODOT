extends SceneTree

## Turns the per-shot mouse moves of Artanis-RCS (MIT) into spray pattern
## files in degrees, one per gun, named by CS2 class, written by
## RecoilPattern as every pattern file is.
##
##   godot --headless --path . --script scripts/convert_rcs_patterns.gd -- <Artanis-RCS checkout>
##
## Artanis-RCS is a recoil compensation tool: each row of its patterns/<gun>.csv
## is the mouse move, in counts at sensitivity 1, that pulls the aim back onto
## the target before the next shot (dx right, dy down, then a delay in ms). It
## multiplies each by 2.45 and divides by the in-game sensitivity; CS2 turns a
## count into 0.022 degrees times the sensitivity (m_yaw and m_pitch). So a
## row is 2.45 x 0.022 degrees of mouse, and the bullet had drifted the other
## way by as much. Summing the rows gives where each shot lands, from the
## first.
##
## The files are then put on the scale of the repo's own ak47.csv, which
## assumes the AK-47 climbs 16 degrees: the one factor that lays the source's
## AK-47 best over ours (least squares, all 30 shots), applied to every gun,
## so one recoil_scale corrects them all together as it does the two rifles.

const DEGREES_PER_ROW_UNIT := 2.45 * 0.022

## Source file -> [CS2 class, name CS2 gives it].
const GUNS := {
	"ak47": ["weapon_ak47", "AK-47"],
	"m4a4": ["weapon_m4a1", "M4A4"],
	"m4a1": ["weapon_m4a1_silencer", "M4A1-S"],
	"galil": ["weapon_galilar", "Galil AR"],
	"famas": ["weapon_famas", "FAMAS"],
	"sg553": ["weapon_sg556", "SG 553"],
	"aug": ["weapon_aug", "AUG"],
	"p90": ["weapon_p90", "P90"],
	"bizon": ["weapon_bizon", "PP-Bizon"],
	"ump45": ["weapon_ump45", "UMP-45"],
	"mac10": ["weapon_mac10", "MAC-10"],
	"mp5sd": ["weapon_mp5sd", "MP5-SD"],
	"mp7": ["weapon_mp7", "MP7"],
	"mp9": ["weapon_mp9", "MP9"],
	"m249": ["weapon_m249", "M249"],
	"negev": ["weapon_negev", "Negev"],
	"cz75": ["weapon_cz75a", "CZ75-Auto"],
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: godot --headless --path . --script scripts/convert_rcs_patterns.gd -- <Artanis-RCS checkout>")
		quit(1)
		return
	var checkout := args[0]
	var source_dir := checkout.path_join("patterns")
	var output := []
	if OS.execute("git", ["-C", checkout, "log", "-1", "--format=%H %cs"], output) != 0:
		printerr("Not a git checkout: %s" % checkout)
		quit(1)
		return
	var commit := (output[0] as String).strip_edges().split(" ")
	var source_ak := read_source(source_dir.path_join("ak47.csv"))
	var scale := fit_scale(source_ak, RecoilPattern.load_from(RecoilPattern.PATTERN_DIR.path_join("ak47.csv")))
	var climb := 0.0
	for shot in source_ak:
		climb = maxf(climb, shot[1])
	print("scale onto ak47.csv: %.4f (the source's AK-47 climbs %.2f degrees)" % [scale, climb])
	for source_name: String in GUNS:
		var weapon_class: String = GUNS[source_name][0]
		var shots := read_source(source_dir.path_join("%s.csv" % source_name))
		var note := "\n".join([
			"%s (%s): %d shots." % [GUNS[source_name][1], weapon_class, shots.size()],
			"From Artanis-RCS (MIT), github.com/ArtanisInc/Artanis-RCS,",
			"patterns/%s.csv at %s (%s). Converted by" % [source_name, commit[0].left(7), commit[1]],
			"scripts/convert_rcs_patterns.gd: the mouse moves summed and turned",
			"into degrees (2.45 x 0.022 per unit), then x%.4f onto ak47.csv's" % scale,
			"scale. Not measured here. See README.md for how far to trust it.",
		])
		var pattern := PackedVector2Array()
		for shot in shots:
			pattern.append(Vector2(shot[0] * scale, shot[1] * scale))
		var path := RecoilPattern.PATTERN_DIR.path_join("%s.csv" % weapon_class)
		if RecoilPattern.save_to(path, pattern, note) != OK:
			printerr("Could not write %s" % path)
			quit(1)
			return
	quit(0)


## Where each shot of a source file lands, in degrees from the first: the
## mouse moves summed, the other way, as [x, y] pairs of 64-bit floats so
## the sum drifts no more than the source's own figures do.
static func read_source(path: String) -> Array[PackedFloat64Array]:
	var shots: Array[PackedFloat64Array] = []
	var x := 0.0
	var y := 0.0
	for line in FileAccess.get_file_as_string(path).trim_prefix("\ufeff").split("\n"):
		var fields := line.strip_edges().split(",")
		if fields.size() < 3:
			continue
		x -= float(fields[0]) * DEGREES_PER_ROW_UNIT
		y -= float(fields[1]) * DEGREES_PER_ROW_UNIT
		shots.append(PackedFloat64Array([x, y]))
	return shots


## The one factor that lays source best over ours, by least squares.
static func fit_scale(source: Array[PackedFloat64Array], ours: PackedVector2Array) -> float:
	var dot := 0.0
	var norm := 0.0
	for i in mini(source.size(), ours.size()):
		dot += source[i][0] * ours[i].x + source[i][1] * ours[i].y
		norm += source[i][0] * source[i][0] + source[i][1] * source[i][1]
	return dot / norm
