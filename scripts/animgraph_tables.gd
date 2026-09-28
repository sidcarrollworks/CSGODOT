extends SceneTree

## Writes reference/animgraph/ from CS2's animation graphs (AnimGraph 2), as
## scripts/extract_assets.sh animgraphs dumps them: every graph and its
## variations (graphs.md); the parameters the game sets and every value the
## graphs test them for (parameters.md); the third-person graph, its
## locomotion and the first-person gun's laid out, layers, state machines,
## states and the conditions between them (worldmodel.md, locomotion.md,
## viewmodel.md); and the locomotion's blend spaces as data, each clip at the
## speed it is authored for (locomotion.json).
##
##   godot --headless --path . --script scripts/animgraph_tables.gd
##
## (scripts/extract_assets.sh animgraphs runs this for you.) Everything is
## read from the graphs; reference/animgraph2.md says what the pieces are.
## CS2_VERSION, if set, is recorded as the build the graphs came from.

const DUMP := "res://assets/characters/animation/graphs/graph_data.txt"
const OUT_DIR := "res://reference/animgraph"
const WORLD := "animation/graphs/worldmodel/worldmodel.vnmgraph_c"
const LOCOMOTION := "animation/graphs/worldmodel/worldmodel_locomotion.vnmgraph"
const LOCOMOTION_SHOWN := "rifle"
const VIEW := "animation/graphs/viewmodel/viewmodel.vnmgraph_c"
const VIEW_GUN := "animation/graphs/viewmodel/viewmodel_gun.vnmgraph"
const VIEW_GUN_SHOWN := "ak47"
## How much of a long description a table cell keeps.
const CELL := 400

var _blocks := {}
var _graphs := {}
var _gaps := PackedStringArray()


func _initialize() -> void:
	_blocks = NmGraph.read_dump(DUMP)
	if _blocks.is_empty():
		print("animation graph tables: nothing at %s (scripts/extract_assets.sh animgraphs)" % DUMP)
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var version := OS.get_environment("CS2_VERSION")
	var source := "CS2 %s" % version if not version.is_empty() else "CS2"
	var date := Time.get_date_string_from_system()
	_write(OUT_DIR.path_join("graphs.md"), _graphs_page(source, date))
	_write(OUT_DIR.path_join("parameters.md"), _parameters_page(source, date))
	_write(OUT_DIR.path_join("worldmodel.md"), _layout_page(
		source, date, WORLD, "The third-person graph",
		"The player as the others see them: `worldmodel.vnmgraph`, over the world rig (`animation/skeletons/characters/worldmodel.vnmskel`). It runs the locomotion (`locomotion.md`) and the weapon graphs through graph slots, so its own states name which graph plays rather than clips."
	))
	_write(OUT_DIR.path_join("locomotion.md"), _layout_page(
		source, date, "%s+%s.vnmgraph_c" % [LOCOMOTION, LOCOMOTION_SHOWN], "The third-person locomotion",
		"`worldmodel_locomotion.vnmgraph`, which the third-person graph runs for the legs and body: idle, starts, moving, turning on the spot, the air and ladders. Its clips are shown for the %s variation; the pistol and knife ones swap in their own sets, and the blend spaces are the same in all three (`locomotion.json` has each variation's clips)." % LOCOMOTION_SHOWN
	))
	_write(OUT_DIR.path_join("viewmodel.md"), _layout_page(
		source, date, "%s+%s.vnmgraph_c" % [VIEW_GUN, VIEW_GUN_SHOWN], "The first-person gun",
		"`viewmodel_gun.vnmgraph`, the graph that plays a gun's first-person clips (`viewmodel.vnmgraph` runs it, and the knife's, grenade's and the inspects' graphs, by what is in hand). Its clips are shown for the %s; every gun but the CZ75-Auto, the Dual Berettas and the R8 Revolver, which have graphs of their own, is a variation of it." % VIEW_GUN_SHOWN
	))
	_write(OUT_DIR.path_join("locomotion.json"), JSON.stringify(_locomotion_data(source), "\t") + "\n")
	print("animation graph tables: %d graphs, %d gaps, written to %s" % [_blocks.size(), _gaps.size(), OUT_DIR])
	for gap in _gaps:
		print("  missing: ", gap)
	quit(0)


func _graph(resource: String) -> NmGraph:
	if not _graphs.has(resource):
		_graphs[resource] = NmGraph.from_text(String(_blocks.get(resource, "")))
		if (_graphs[resource] as NmGraph).is_empty():
			_gaps.append(resource)
	return _graphs[resource]


## The graphs in a folder of animation/graphs/, by base name: each its
## resources, the graph's own first.
func _families(folder: String) -> Dictionary:
	var families := {}
	var names := _blocks.keys()
	names.sort()
	for resource: String in names:
		if resource.get_base_dir().get_file() != folder:
			continue
		var family := NmGraph.base_name(resource)
		var members: PackedStringArray = families.get(family, PackedStringArray())
		if NmGraph.variation_of(resource).is_empty():
			members.insert(0, resource)
		else:
			members.append(resource)
		families[family] = members
	return families


func _graphs_page(source: String, date: String) -> String:
	var lines := PackedStringArray([
		"# CS2's animation graphs",
		"",
		"Written by `scripts/animgraph_tables.gd` on %s from the %d graphs under `animation/graphs/` in %s, as `scripts/extract_assets.sh animgraphs` decodes them. Do not edit by hand. `reference/animgraph2.md` says what a graph is and how to read these." % [date, _blocks.size(), source],
		"",
		"A graph with variations is one graph compiled again with other clips in its slots, named `<graph>.vnmgraph+<variation>`; the nodes, blends and conditions are the same in each. Nodes counts every node, the parameters and the conditions among them; Runs is the graphs it plays through its graph slots.",
	])
	for folder in ["worldmodel", "viewmodel", "chicken", "ui"]:
		var families := _families(folder)
		lines.append_array(PackedStringArray([
			"",
			"## %s" % folder,
			"",
			"| Graph | Variations | Nodes | Parameters | Skeleton | Runs |",
			"|---|---|---|---|---|---|",
		]))
		for family: String in families:
			var members: PackedStringArray = families[family]
			var graph := _graph(members[0])
			var variations := PackedStringArray()
			for member in members:
				if not NmGraph.variation_of(member).is_empty():
					variations.append(NmGraph.variation_of(member))
			var runs := PackedStringArray()
			for slot: Dictionary in graph.data.get("m_referencedGraphSlots", []):
				var runs_graph := NmGraph.base_name(graph.resource(int(slot.get("m_dataSlotIdx", -1))))
				if not runs_graph.is_empty() and runs_graph not in runs:
					runs.append(runs_graph)
			lines.append("| `%s` | %s | %d | %d | %s | %s |" % [
				family, ", ".join(variations) if not variations.is_empty() else "-", graph.nodes.size(), graph.parameters.size(),
				String(graph.data.get("m_skeleton", "")).get_file().get_basename(), ", ".join(runs) if not runs.is_empty() else "-",
			])
	return "\n".join(lines) + "\n"


## Every parameter of a folder's graphs, with its type, the graphs that take
## it, and the values the graphs compare it with.
func _parameters_page(source: String, date: String) -> String:
	var lines := PackedStringArray([
		"# What the game tells the animation graphs",
		"",
		"Written by `scripts/animgraph_tables.gd` on %s from %s's animation graphs. Do not edit by hand." % [date, source],
		"",
		"The control parameters are what the game sets on a player's graphs every frame; the graphs do the rest. An ID parameter is a name: Values lists every one the graphs test it for, which is the game's vocabulary for it (an empty one is written (none)). A float's range is for the game's code to say; the blend spaces in `locomotion.json` and the conditions in the layout pages show what values the graphs expect. Graphs names the families that take the parameter (`graphs.md`).",
	])
	for folder in ["worldmodel", "viewmodel"]:
		var types := {}
		var takers := {}
		var values := {}
		var computed := PackedStringArray()
		var families := _families(folder)
		for family: String in families:
			for member: String in families[family]:
				var graph := _graph(member)
				for parameter in graph.parameters:
					types[parameter] = graph.parameter_type(parameter)
					var family_list: PackedStringArray = takers.get(parameter, PackedStringArray())
					if family not in family_list:
						family_list.append(family)
						takers[parameter] = family_list
				var tested := graph.id_values()
				for parameter: String in tested:
					var seen: PackedStringArray = values.get(parameter, PackedStringArray())
					for id in tested[parameter] as PackedStringArray:
						var text := id if not id.is_empty() else "(none)"
						if text not in seen:
							seen.append(text)
					values[parameter] = seen
				if member == families[family][0]:
					for i in graph.virtual_parameters.size():
						computed.append("| `%s` | `%s` | %s |" % [graph.virtual_parameters[i], family, _cell(graph.expression(graph.virtual_parameter_nodes[i]))])
		lines.append_array(PackedStringArray([
			"",
			"## %s" % ("Third person (`worldmodel`)" if folder == "worldmodel" else "First person (`viewmodel`)"),
			"",
			"| Parameter | Type | Graphs | Values |",
			"|---|---|---|---|",
		]))
		var names := types.keys()
		names.sort()
		for parameter: String in names:
			var seen: PackedStringArray = values.get(parameter, PackedStringArray())
			seen.sort()
			lines.append("| `%s` | %s | %s | %s |" % [parameter, types[parameter], ", ".join(takers[parameter]), ", ".join(seen) if not seen.is_empty() else "-"])
		if not computed.is_empty():
			lines.append_array(PackedStringArray([
				"",
				"Computed by the graphs themselves (virtual parameters), from the others:",
				"",
				"| Parameter | Graph | Is |",
				"|---|---|---|",
			]))
			lines.append_array(computed)
	return "\n".join(lines) + "\n"


## One graph laid out: the chain from its root down to where it branches,
## its layers, and every state machine with its states and transitions.
func _layout_page(source: String, date: String, resource: String, title: String, about: String) -> String:
	var graph := _graph(resource)
	var lines := PackedStringArray([
		"# %s" % title,
		"",
		"Written by `scripts/animgraph_tables.gd` on %s from `%s` in %s. Do not edit by hand; `reference/animgraph2.md` says how to read it." % [date, resource, source],
		"",
		about,
		"",
		"Each node is named by its path in Valve's editor. Conditions are written out with the parameters by name (`parameters.md` has their values); a transition's blend is its length, then its easing and options where they are not the plain ones. (options is Esoterica's transition-option bit field, which Valve's version orders its own way.)",
	])
	if graph.is_empty():
		lines.append("\n(not in the dump)")
		return "\n".join(lines) + "\n"
	lines.append_array(PackedStringArray(["", "## From the root", ""]))
	var at := graph.root()
	var guard := 0
	while at >= 0 and guard < 32:
		guard += 1
		var n := graph.node(at)
		lines.append("%d. `%s` %s%s" % [guard, graph.kind(at), graph.path(at), _inputs_of(graph, at)])
		var child := int(n.get("m_nChildNodeIdx", n.get("m_nBaseNodeIdx", -1)))
		if graph.kind(at) == "StateMachine" or child < 0:
			break
		at = child

	var layer_blends := graph.nodes_of_kind("LayerBlend")
	if not layer_blends.is_empty():
		lines.append_array(PackedStringArray(["", "## Layers", ""]))
		for blend in layer_blends:
			var n := graph.node(blend)
			lines.append_array(PackedStringArray([
				"`%s`, over %s:" % [graph.path(blend), _cell(graph.summary(int(n.get("m_nBaseNodeIdx", -1))))],
				"",
				"| Layer | Plays | Weight | Bone mask | Blend | Synced |",
				"|---|---|---|---|---|---|",
			]))
			for layer: Dictionary in n.get("m_layerDefinition", []):
				var input := int(layer.get("m_nInputNodeIdx", -1))
				var weight := int(layer.get("m_nWeightValueNodeIdx", -1))
				var mask := int(layer.get("m_nBoneMaskValueNodeIdx", -1))
				lines.append("| `%s` | %s | %s | %s | %s | %s |" % [
					graph.path(input), _cell(graph.summary(input)),
					graph.expression(weight) if weight >= 0 else ("the state's" if bool(layer.get("m_bIsStateMachineLayer", false)) else "1"),
					graph.expression(mask) if mask >= 0 else "-", layer.get("m_blendMode", ""), "yes" if bool(layer.get("m_bIsSynchronized", false)) else "no",
				])
			lines.append("")

	var machines := graph.nodes_of_kind("StateMachine")
	lines.append_array(PackedStringArray(["", "## State machines (%d)" % machines.size()]))
	for machine in machines:
		lines.append_array(_machine_section(graph, machine))

	var spaces := graph.nodes_of_kind("Blend2D")
	if not spaces.is_empty():
		lines.append_array(PackedStringArray(["", "## Blend spaces", ""]))
		for space in spaces:
			var n := graph.node(space)
			var points := PackedStringArray()
			var values: Array = n.get("m_values", [])
			var sources: Array = n.get("m_sourceNodeIndices", [])
			for i in mini(values.size(), sources.size()):
				points.append("%s (%s, %s)" % [graph.short_summary(int(sources[i])), NmGraph.format_number(values[i][0]), NmGraph.format_number(values[i][1])])
			lines.append("- `%s`, on %s and %s: %s" % [
				graph.path(space), graph.expression(int(n.get("m_nInputParameterNodeIdx0", -1))), graph.expression(int(n.get("m_nInputParameterNodeIdx1", -1))), ", ".join(points),
			])
	return "\n".join(lines) + "\n"


## What feeds a node of Valve's own or an IK node: its parameters by name.
func _inputs_of(graph: NmGraph, index: int) -> String:
	var n := graph.node(index)
	var inputs := PackedStringArray()
	for key: String in n:
		if key.ends_with("NodeIdx") and key not in ["m_nNodeIdx", "m_nChildNodeIdx", "m_nBaseNodeIdx"] and int(n[key]) >= 0:
			inputs.append("%s: %s" % [key.trim_prefix("m_n").trim_prefix("m_").trim_suffix("NodeIdx"), graph.expression(int(n[key]))])
		elif key.begins_with("m_fl") or key.ends_with("BoneID"):
			inputs.append("%s: %s" % [key.trim_prefix("m_fl").trim_prefix("m_"), n[key]])
	return " (%s)" % "; ".join(inputs) if not inputs.is_empty() else ""


## A state machine as a table: each state, what it plays, and where it goes
## when. A transition every state has (Valve's editor's global transitions,
## which the compiler copies onto each state) is listed once, below.
func _machine_section(graph: NmGraph, machine: int) -> PackedStringArray:
	var states := graph.states(machine)
	var lines := PackedStringArray([
		"",
		"### `%s`" % graph.path(machine),
		"",
		"Starts in %s." % (states[int(graph.node(machine).get("m_nDefaultStateIndex", 0))]["name"] if not states.is_empty() else "-"),
		"",
		"| State | Plays | Goes to |",
		"|---|---|---|",
	])
	# Where each condition node leads from: the ones every state shares are
	# the machine's global transitions.
	var sources := {}
	for i in states.size():
		for transition: Dictionary in states[i]["transitions"]:
			var key := "%d>%d" % [transition["when"], transition["to"]]
			var from: PackedInt32Array = sources.get(key, PackedInt32Array())
			from.append(i)
			sources[key] = from
	var shared := PackedStringArray()
	var listed := {}
	for i in states.size():
		var state: Dictionary = states[i]
		var goes := PackedStringArray()
		for transition: Dictionary in state["transitions"]:
			var key := "%d>%d" % [transition["when"], transition["to"]]
			var line := "%s when %s (%s%s)" % [
				states[transition["to"]]["name"], graph.expression(transition["when"]), graph.transition_blend(transition["node"]),
				", can interrupt" if transition["forced"] else "",
			]
			if (sources[key] as PackedInt32Array).size() > 1 and states.size() > 2:
				if not listed.has(key):
					listed[key] = true
					shared.append("- to %s, from %s" % [line, _state_names(states, sources[key])])
				continue
			goes.append(line)
		var entry := int(state["entry"])
		lines.append("| %s | %s | %s |" % [
			state["name"] + (" (starts here when %s)" % graph.expression(entry) if entry >= 0 else ""),
			_cell(graph.summary(state["plays"])), "<br>".join(goes) if not goes.is_empty() else "-",
		])
	if not shared.is_empty():
		lines.append_array(PackedStringArray(["", "From more than one state:", ""]))
		lines.append_array(shared)
	return lines


func _state_names(states: Array, indices: PackedInt32Array) -> String:
	if indices.size() >= states.size() - 1:
		return "any state"
	var names := PackedStringArray()
	for i in indices:
		names.append(states[i]["name"])
	return ", ".join(names)


## The locomotion's blend spaces as data: for each, its inputs and its
## points, each with its position (the speeds the clip is authored for, in
## units a second, forward and to the left of the body), its clip in every
## variation, its playback speed and, where it is made to last a set time,
## that time; and the triangles the space is cut into. Then the graph's
## curves, springs and poses (values: NmGraph.value_nodes()), which pose
## the landing by the height above the ground.
func _locomotion_data(source: String) -> Dictionary:
	var variations := {}
	for resource: String in _blocks:
		if resource.begins_with(LOCOMOTION):
			var variation := NmGraph.variation_of(resource)
			variations[variation if not variation.is_empty() else "default"] = _graph(resource)
	var shown: NmGraph = variations.get(LOCOMOTION_SHOWN, null)
	var spaces := []
	if shown == null:
		_gaps.append("the %s locomotion graph" % LOCOMOTION_SHOWN)
		return {"source": LOCOMOTION, "cs2": source, "blend_spaces": spaces}
	for space in shown.nodes_of_kind("Blend2D"):
		var n := shown.node(space)
		var points := []
		var values: Array = n.get("m_values", [])
		var sources: Array = n.get("m_sourceNodeIndices", [])
		for i in mini(values.size(), sources.size()):
			var at := int(sources[i])
			var lasts := -1.0
			if shown.kind(at) == "DurationScale" and int(shown.node(at).get("m_nInputValueNodeIdx", -1)) < 0:
				lasts = float(shown.node(at).get("m_flDefaultInputValue", 1.0))
				at = int(shown.node(at).get("m_nChildNodeIdx", -1))
			var clips := {}
			for variation: String in variations:
				clips[variation] = (variations[variation] as NmGraph).clip_of(at).trim_suffix(".vnmclip")
			points.append({
				"name": shown.name_of(at), "node": at, "kind": shown.kind(at), "x": float(values[i][0]), "y": float(values[i][1]),
				"speed": float(shown.node(at).get("m_flSpeedMultiplier", 1.0)), "lasts": lasts, "clips": clips,
			})
		var triangles := []
		var indices: Array = n.get("m_indices", [])
		for i in range(0, indices.size() - 2, 3):
			triangles.append([int(indices[i]), int(indices[i + 1]), int(indices[i + 2])])
		spaces.append({
			"node": space, "path": shown.path(space),
			"inputs": [shown.expression(int(n.get("m_nInputParameterNodeIdx0", -1))), shown.expression(int(n.get("m_nInputParameterNodeIdx1", -1)))],
			"points": points, "triangles": triangles,
		})
	return {"source": LOCOMOTION, "cs2": source, "variations": variations.keys(), "blend_spaces": spaces, "values": shown.value_nodes()}


static func _cell(text: String) -> String:
	return text if text.length() <= CELL else text.substr(0, CELL) + "..."


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("could not write %s" % path)
		return
	file.store_string(text)
