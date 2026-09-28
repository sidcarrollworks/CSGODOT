class_name NmGraph
extends RefCounted

## One of CS2's animation graphs (AnimGraph 2, .vnmgraph), read from the
## text Source 2 Viewer decodes it to (-b DATA; scripts/extract_assets.sh
## animgraphs dumps them all). AnimGraph 2 is the animation graph of
## Esoterica (github.com/BobbyAnguelov/Esoterica, MIT) under Valve's names:
## CNmTransitionNode::CDefinition is Esoterica's TransitionNode::Definition,
## field for field, so Esoterica's source says what each node does.
## reference/animgraph2.md has the rest.
##
## A compiled graph is a flat list of node definitions that point at each
## other by index. The first are the control parameters, the values the game
## sets every frame (move_speed_x, action, aim_angle_pitch...); then come
## the nodes that compute from them, and the pose nodes that play and blend
## clips. Each node keeps the path it had in Valve's editor
## (SM/Ground/Standing/Move/run_ne). This names the parts: a node's kind and
## path, the clip or graph a slot holds, a condition or value written out as
## an expression, and each state machine's states and transitions.

## How far an expression is written out before it is cut short.
const DEEPEST := 8

var data: Dictionary = {}
## Every node's path in Valve's editor, by node index.
var paths := PackedStringArray()
## The control parameters, which are nodes 0 onwards.
var parameters := PackedStringArray()
## The parameters the graph computes itself, and the node that computes each.
var virtual_parameters := PackedStringArray()
var virtual_parameter_nodes := PackedInt32Array()
## What the graph's slots hold: clips, and for the graph slots, other graphs.
var resources := PackedStringArray()
var nodes := {}


## Reads one graph's DATA text (a value of read_dump()).
static func from_text(text: String) -> NmGraph:
	var graph := NmGraph.new()
	var parsed: Variant = parse_kv3(text)
	if parsed is Dictionary:
		graph._load(parsed)
	return graph


## Every resource in a dump of Source 2 Viewer's DATA blocks (-b DATA over
## many files, each block after its "[i/n] path" line), by path: the block's
## text, from its opening brace.
static func read_dump(dump_path: String) -> Dictionary:
	var blocks := {}
	var file := FileAccess.open(dump_path, FileAccess.READ)
	if file == null:
		return blocks
	var header := RegEx.create_from_string("^\\[\\d+/\\d+\\] (\\S+)$")
	var current := ""
	var lines := PackedStringArray()
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("["):
			var found := header.search(line)
			if found != null:
				_add_block(blocks, current, lines)
				current = found.get_string(1)
				lines = PackedStringArray()
				continue
		if not current.is_empty():
			lines.append(line)
	_add_block(blocks, current, lines)
	return blocks


static func _add_block(blocks: Dictionary, block_path: String, lines: PackedStringArray) -> void:
	var start := lines.find("{")
	if not block_path.is_empty() and start >= 0:
		blocks[block_path] = "\n".join(lines.slice(start))


## The variation a compiled graph is, from its name: "rifle" for
## worldmodel_locomotion.vnmgraph+rifle.vnmgraph_c, empty for the graph's own.
## A variation is the same graph with other clips in its slots.
static func variation_of(graph_path: String) -> String:
	var file := graph_path.get_file()
	var plus := file.find(".vnmgraph+")
	if plus < 0:
		return ""
	return file.substr(plus + 10).get_slice(".", 0)


## A graph's name without its folder, variation or extension.
static func base_name(graph_path: String) -> String:
	return graph_path.get_file().get_slice(".", 0)


## Source 2 Viewer's KV3 text: objects of key = value, arrays of values,
## strings, typed strings (resource:"...", which give the string), numbers,
## true, false and null.
static func parse_kv3(text: String) -> Variant:
	return _Kv3.new(text).value()


class _Kv3:
	static var _token: RegEx
	var tokens := PackedStringArray()
	var at := 0

	func _init(text: String) -> void:
		if _token == null:
			_token = RegEx.create_from_string(r'[{}\[\],=]|"(?:[^"\\]|\\.)*"|[A-Za-z_]+:"(?:[^"\\]|\\.)*"|#\[[^\]]*\]|[^\s,=\[\]{}"]+')
		for found in _token.search_all(text):
			tokens.append(found.get_string())

	func value() -> Variant:
		if at >= tokens.size():
			return null
		var token := tokens[at]
		at += 1
		if token == "{":
			var object := {}
			while at < tokens.size() and tokens[at] != "}":
				if tokens[at] == ",":
					at += 1
					continue
				var key := tokens[at]
				at += 2
				object[key] = value()
			at += 1
			return object
		if token == "[":
			var array := []
			while at < tokens.size() and tokens[at] != "]":
				if tokens[at] == ",":
					at += 1
					continue
				array.append(value())
			at += 1
			return array
		return _scalar(token)

	static func _scalar(token: String) -> Variant:
		if token.begins_with("\""):
			return _unquote(token)
		var colon := token.find(":\"")
		if colon > 0:
			return _unquote(token.substr(colon + 1))
		if token == "true":
			return true
		if token == "false":
			return false
		if token == "null":
			return null
		if token.is_valid_int():
			return token.to_int()
		if token.is_valid_float():
			return token.to_float()
		return token

	static func _unquote(token: String) -> String:
		return token.substr(1, token.length() - 2).replace("\\\"", "\"").replace("\\\\", "\\")


func _load(parsed: Dictionary) -> void:
	data = parsed
	paths = PackedStringArray(parsed.get("m_nodePaths", []))
	parameters = PackedStringArray(parsed.get("m_controlParameterIDs", []))
	virtual_parameters = PackedStringArray(parsed.get("m_virtualParameterIDs", []))
	virtual_parameter_nodes = PackedInt32Array(parsed.get("m_virtualParameterNodeIndices", []))
	resources = PackedStringArray(parsed.get("m_resources", []))
	for definition: Dictionary in parsed.get("m_nodes", []):
		nodes[int(definition.get("m_nNodeIdx", -1))] = definition


func is_empty() -> bool:
	return nodes.is_empty()


func root() -> int:
	return int(data.get("m_nRootNodeIdx", -1))


func node(index: int) -> Dictionary:
	return nodes.get(index, {})


func path(index: int) -> String:
	return paths[index] if index >= 0 and index < paths.size() else ""


## A node's name: the last part of its path.
func name_of(index: int) -> String:
	return path(index).get_file()


## A node's kind, the class less Valve's wrapping: "StateMachine" for
## CNmStateMachineNode::CDefinition.
func kind(index: int) -> String:
	return String(node(index).get("_class", "")).trim_prefix("CNm").trim_suffix("::CDefinition").trim_suffix("Node")


func nodes_of_kind(wanted: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for index: int in nodes:
		if kind(index) == wanted:
			out.append(index)
	out.sort()
	return out


## The node a parameter is (a control parameter's node is its index; a
## virtual one's is the node that computes it); -1 for none.
func parameter_node(parameter: String) -> int:
	var control := parameters.find(parameter)
	if control >= 0:
		return control
	var computed := virtual_parameters.find(parameter)
	return virtual_parameter_nodes[computed] if computed >= 0 and computed < virtual_parameter_nodes.size() else -1


## A control parameter's type: Float, ID, Bool, Target or Vector.
func parameter_type(parameter: String) -> String:
	var index := parameters.find(parameter)
	return kind(index).trim_prefix("ControlParameter") if index >= 0 else ""


func resource(slot: int) -> String:
	return resources[slot] if slot >= 0 and slot < resources.size() else ""


## The clip a clip or pose node plays, as a resource path; empty for none.
func clip_of(index: int) -> String:
	return resource(int(node(index).get("m_nDataSlotIdx", -1)))


## The graph a referenced-graph node runs, as a resource path.
func graph_of(index: int) -> String:
	var slots: Array = data.get("m_referencedGraphSlots", [])
	var slot := int(node(index).get("m_nReferencedGraphIdx", -1))
	if slot < 0 or slot >= slots.size():
		return ""
	return resource(int((slots[slot] as Dictionary).get("m_dataSlotIdx", -1)))


## A value or condition node written out, the parameters by name:
## "action is action_reload and not (move_crouch_amount >= 0.5)".
func expression(index: int, depth: int = 0) -> String:
	if index < 0:
		return "-"
	if index < parameters.size():
		return parameters[index]
	var computed := virtual_parameter_nodes.find(index)
	if computed >= 0 and depth > 0:
		return virtual_parameters[computed]
	if depth > DEEPEST:
		return "..."
	var n := node(index)
	match kind(index):
		"ConstFloat":
			return format_number(n.get("m_flValue", 0.0))
		"ConstID":
			return String(n.get("m_value", ""))
		"ConstBool":
			return str(n.get("m_bValue", false))
		"IDComparison":
			var ids: Array = n.get("m_comparisionIDs", n.get("m_comparisonIDs", []))
			var matches := String(n.get("m_comparison", "Matches")) == "Matches"
			var listed := ", ".join(PackedStringArray(ids.map(func(id: Variant) -> String: return String(id) if not String(id).is_empty() else "(none)")))
			var verb := ("is" if ids.size() == 1 else "is one of") if matches else ("is not" if ids.size() == 1 else "is none of")
			return "%s %s %s" % [expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1), verb, listed]
		"FloatComparison":
			var against := int(n.get("m_nComparandValueNodeIdx", -1))
			return "%s %s %s" % [
				expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1), _operator(String(n.get("m_comparison", ""))),
				expression(against, depth + 1) if against >= 0 else format_number(n.get("m_flComparisonValue", 0.0)),
			]
		"FloatRangeComparison":
			var range_value: Dictionary = n.get("m_range", {})
			return "%s in %s to %s" % [expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1), format_number(range_value.get("m_flMin", 0.0)), format_number(range_value.get("m_flMax", 0.0))]
		"And", "Or":
			var parts := PackedStringArray()
			for condition: int in n.get("m_conditionNodeIndices", []):
				var part := expression(condition, depth + 1)
				parts.append("(%s)" % part if " and " in part or " or " in part else part)
			return (" and " if kind(index) == "And" else " or ").join(parts)
		"Not":
			var inner := expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1)
			return "not (%s)" % inner if " " in inner else "not %s" % inner
		"StateCompletedCondition":
			var left := float(n.get("m_flTransitionDurationSeconds", 0.0))
			return "the state is done" if left <= 0.0 else "the state has %s s left" % format_number(left)
		"TimeCondition":
			var measure := {"ElapsedTime": "time in the state", "CurrentTime": "time in the state", "PercentageThroughState": "share of the state done", "PercentageThroughSyncEvent": "share of the sync event done"}
			var input := int(n.get("m_nInputValueNodeIdx", -1))
			return "%s %s %s" % [
				measure.get(String(n.get("m_type", "")), String(n.get("m_type", ""))), _operator(String(n.get("m_operator", ""))),
				expression(input, depth + 1) if input >= 0 else format_number(n.get("m_flComparand", 0.0)),
			]
		"IDEventCondition":
			var events: Array = n.get("m_eventIDs", [])
			return "event %s" % " or ".join(PackedStringArray(events))
		"GraphEventCondition":
			var parts := PackedStringArray()
			for condition: Dictionary in n.get("m_conditions", []):
				parts.append("%s (%s)" % [condition.get("m_eventID", ""), condition.get("m_eventTypeCondition", "")])
			return "graph event %s" % " or ".join(parts)
		"CachedFloat", "CachedBool", "CachedID", "CachedVector", "CachedTarget":
			var mode := String(n.get("m_mode", ""))
			return "%s (held from the state's %s)" % [expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1), "entry" if mode == "OnEntry" else "exit"]
		"FloatEase":
			return "%s eased over %s s" % [expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1), format_number(n.get("m_flEaseTime", 0.0))]
		"FloatSpring":
			var spring := spring_of(index)
			return "%s on a %s Hz spring, damping %s%s" % [
				expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1), format_number(spring["hertz"]), format_number(spring["damping"]),
				", from %s" % format_number(spring["start"]) if spring["uses_start"] else "",
			]
		"FloatCurve":
			var points := PackedStringArray()
			for point: Vector2 in curve_points(index):
				points.append("%s to %s" % [format_number(point.x), format_number(point.y)])
			return "a curve of %s%s" % [expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1), " (%s)" % ", ".join(points) if not points.is_empty() else ""]
		"FloatRemap":
			var from: Dictionary = n.get("m_inputRange", {})
			var to: Dictionary = n.get("m_outputRange", {})
			return "%s mapped from %s..%s to %s..%s" % [
				expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1),
				format_number(from.get("m_flBegin", 0.0)), format_number(from.get("m_flEnd", 0.0)), format_number(to.get("m_flBegin", 0.0)), format_number(to.get("m_flEnd", 0.0)),
			]
		"FloatSwitch", "IDSwitch", "BoneMaskSwitch":
			return "(%s ? %s : %s)" % [
				expression(int(n.get("m_nSwitchValueNodeIdx", -1)), depth + 1),
				_switch_side(n, "m_nTrueValueNodeIdx", "m_flTrueValue", "m_trueValue", depth), _switch_side(n, "m_nFalseValueNodeIdx", "m_flFalseValue", "m_falseValue", depth),
			]
		"FloatMath":
			var operators := {"Add": "+", "Sub": "-", "Mul": "*", "Div": "/"}
			var other := int(n.get("m_nInputValueNodeIdxB", -1))
			return "(%s %s %s)" % [
				expression(int(n.get("m_nInputValueNodeIdxA", -1)), depth + 1), operators.get(String(n.get("m_operator", "")), String(n.get("m_operator", ""))),
				expression(other, depth + 1) if other >= 0 else format_number(n.get("m_flValueB", 0.0)),
			]
		"IDToFloat":
			return "%s as a number" % expression(int(n.get("m_nInputValueNodeIdx", -1)), depth + 1)
		"CurrentSyncEventID":
			return "the state's current sync event"
		"BoneMask":
			return "mask %s" % n.get("m_boneMaskID", "")
		"BoneMaskSelector":
			var masks := PackedStringArray()
			var values: Array = n.get("m_parameterValues", [])
			var chosen: Array = n.get("m_maskNodeIndices", [])
			for i in mini(values.size(), chosen.size()):
				masks.append("%s: %s" % [values[i], expression(int(chosen[i]), depth + 1)])
			return "by %s, %s, else %s" % [expression(int(n.get("m_parameterValueNodeIdx", -1)), depth + 1), ", ".join(masks), expression(int(n.get("m_defaultMaskNodeIdx", -1)), depth + 1)]
	if computed >= 0:
		return virtual_parameters[computed]
	return "%s %s" % [kind(index), path(index)]


func _switch_side(n: Dictionary, index_key: String, float_key: String, id_key: String, depth: int) -> String:
	var index := int(n.get(index_key, -1))
	if index >= 0:
		return expression(index, depth + 1)
	if n.has(float_key):
		return format_number(n[float_key])
	return String(n.get(id_key, ""))


static func _operator(name: String) -> String:
	return {
		"LessThan": "<", "LessThanEqual": "<=", "GreaterThan": ">", "GreaterThanEqual": ">=",
		"NearEqual": "=", "Equal": "=", "NotEqual": "!=",
	}.get(name, name)


static func format_number(value: Variant) -> String:
	var number := float(value)
	return str(int(number)) if is_equal_approx(number, roundf(number)) and absf(number) < 1e9 else str(snappedf(number, 0.001))


## A pose node in a few words: what it plays or how it mixes what it plays.
func summary(index: int) -> String:
	var n := node(index)
	match kind(index):
		"Clip":
			if clip_of(index).is_empty():
				return "no clip (the slot is empty in this variation)"
			var notes := PackedStringArray()
			if bool(n.get("m_bAllowLooping", false)):
				notes.append("loops")
			if not is_equal_approx(float(n.get("m_flSpeedMultiplier", 1.0)), 1.0):
				notes.append("at %sx" % format_number(n.get("m_flSpeedMultiplier", 1.0)))
			if int(n.get("m_nPlayInReverseValueNodeIdx", -1)) >= 0:
				notes.append("backwards when %s" % expression(int(n["m_nPlayInReverseValueNodeIdx"])))
			return "clip %s%s" % [clip_of(index).get_file().get_basename(), " (%s)" % ", ".join(notes) if not notes.is_empty() else ""]
		"AnimationPose":
			var clip := clip_of(index).get_file().get_basename()
			return "%s %s" % ["a pose from %s" % clip if not clip.is_empty() else "a pose", pose_time_words(index)]
		"ZeroPose":
			return "the zero pose"
		"ReferencedGraph":
			var runs := graph_of(index)
			if runs.is_empty():
				return "a graph from the caller"
			return "the %s graph%s" % [base_name(runs), " (%s)" % variation_of(runs) if not variation_of(runs).is_empty() else ""]
		"StateMachine":
			return "state machine %s (%d states)" % [path(index), (n.get("m_stateDefinitions", []) as Array).size()]
		"Blend1D":
			return "a 1D blend on %s of %s" % [expression(int(n.get("m_nInputParameterValueNodeIdx", -1))), ", ".join(_blend1d_points(index))]
		"Blend2D":
			return "a 2D blend on %s, %s of %d" % [
				expression(int(n.get("m_nInputParameterNodeIdx0", -1))), expression(int(n.get("m_nInputParameterNodeIdx1", -1))),
				(n.get("m_sourceNodeIndices", []) as Array).size(),
			]
		"LayerBlend":
			return "%s, with %d layers" % [summary(int(n.get("m_nBaseNodeIdx", -1))), (n.get("m_layerDefinition", []) as Array).size()]
		"Selector", "ClipSelector":
			var options := PackedStringArray()
			var conditions: Array = n.get("m_conditionNodeIndices", [])
			var choices: Array = n.get("m_optionNodeIndices", [])
			for i in mini(conditions.size(), choices.size()):
				options.append("%s if %s" % [summary(int(choices[i])), expression(int(conditions[i]))])
			return "the first of: %s" % "; ".join(options)
		"ParameterizedSelector", "ParameterizedClipSelector":
			var options := PackedStringArray()
			for choice: int in n.get("m_optionNodeIndices", []):
				options.append(summary(choice))
			return "by %s, one of: %s" % [expression(int(n.get("m_parameterNodeIdx", -1))), "; ".join(options)]
		"IDBasedSelector", "IDBasedClipSelector":
			var options := PackedStringArray()
			var ids: Array = n.get("m_optionIDs", [])
			var choices: Array = n.get("m_optionNodeIndices", [])
			for i in mini(ids.size(), choices.size()):
				options.append("%s: %s" % [ids[i], summary(int(choices[i]))])
			var fallback := int(n.get("m_nFallbackNodeIdx", -1))
			return "by %s, %s%s" % [expression(int(n.get("m_nParameterNodeIdx", -1))), "; ".join(options), ", else %s" % summary(fallback) if fallback >= 0 else ""]
		"DurationScale":
			var wanted := int(n.get("m_nInputValueNodeIdx", -1))
			return "%s, made to last %s s" % [summary(int(n.get("m_nChildNodeIdx", -1))), expression(wanted) if wanted >= 0 else format_number(n.get("m_flDefaultInputValue", 1.0))]
		"SpeedScale":
			var scale_by := int(n.get("m_nInputValueNodeIdx", -1))
			return "%s, at %s times the speed" % [summary(int(n.get("m_nChildNodeIdx", -1))), expression(scale_by) if scale_by >= 0 else format_number(n.get("m_flDefaultInputValue", 1.0))]
	var child := int(n.get("m_nChildNodeIdx", -1))
	if child >= 0:
		return "%s over %s" % [kind(index), summary(child)]
	return "%s %s" % [kind(index), path(index)]


## A float curve node's points, (input, output) in the order the graph keeps
## them. CS2 stores the curve as a CPiecewiseCurve (its m_spline, with
## m_tangents beside it; DumpSource2's schema, GameTracking-CS2 of
## 2026-09-25); how a point is written inside m_spline is not in the schema,
## so this takes an [x, y] list, a {m_vPos} or other object whose first two
## numbers are x and y, or a flat list of numbers in pairs.
func curve_points(index: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var curve: Variant = node(index).get("m_curve", {})
	var spline: Array = (curve as Dictionary).get("m_spline", []) if curve is Dictionary else []
	if not spline.is_empty() and (spline[0] is float or spline[0] is int):
		for i in range(0, spline.size() - 1, 2):
			out.append(Vector2(float(spline[i]), float(spline[i + 1])))
		return out
	for point: Variant in spline:
		var numbers := _numbers_in(point)
		if numbers.size() >= 2:
			out.append(Vector2(numbers[0], numbers[1]))
	return out


## The first numbers in a value, depth first: [x, y] itself, or an object's
## values in order.
static func _numbers_in(value: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if value is float or value is int:
		out.append(float(value))
	elif value is Array:
		for item: Variant in value:
			out.append_array(_numbers_in(item))
			if out.size() >= 2:
				break
	elif value is Dictionary:
		for key: Variant in value:
			if String(key) == "_class":
				continue
			out.append_array(_numbers_in(value[key]))
			if out.size() >= 2:
				break
	return out


## A float spring node's settings: how fast it follows (hertz), how much it
## overshoots (damping, 1 for none), and the value it starts from if it
## uses one. Unset fields take the schema's defaults (4 Hz, 0.7).
func spring_of(index: int) -> Dictionary:
	var n := node(index)
	return {
		"hertz": float(n.get("m_flHertz", 4.0)), "damping": float(n.get("m_flDampingRatio", 0.7)),
		"start": float(n.get("m_flStartValue", 0.0)), "uses_start": bool(n.get("m_bUseStartValue", false)),
	}


## An animation pose node's time: the value node that sets it (-1 for
## none, when it stands at the user time), the input range that maps to the
## clip's start and end, whether the input counts frames rather than the
## share of the clip, and the fixed time.
func pose_time_of(index: int) -> Dictionary:
	var n := node(index)
	var remap: Dictionary = n.get("m_inputTimeRemapRange", {})
	return {
		"input": int(n.get("m_nPoseTimeValueNodeIdx", -1)), "from": float(remap.get("m_flMin", 0.0)), "to": float(remap.get("m_flMax", 1.0)),
		"frames": bool(n.get("m_bUseFramesAsInput", false)), "fixed": float(n.get("m_flUserSpecifiedTime", 0.0)),
	}


func pose_time_words(index: int) -> String:
	var time := pose_time_of(index)
	if int(time["input"]) < 0:
		return "at %s" % format_number(time["fixed"])
	return "at the %s given by %s%s" % [
		"frame" if time["frames"] else "share of the clip", expression(int(time["input"])),
		" (%s to %s)" % [format_number(time["from"]), format_number(time["to"])] if not (is_zero_approx(float(time["from"])) and is_equal_approx(float(time["to"]), 1.0)) else "",
	]


## The graph's curves, springs and poses as data, for locomotion.json:
## each FloatCurve node's points, each FloatSpring's settings and each
## AnimationPose's time, by node, with its path and what feeds it.
func value_nodes() -> Array:
	var out := []
	for index in nodes_of_kind("FloatCurve"):
		var points := []
		for point: Vector2 in curve_points(index):
			points.append([point.x, point.y])
		out.append({
			"node": index, "path": path(index), "kind": "FloatCurve", "input": expression(int(node(index).get("m_nInputValueNodeIdx", -1))),
			"input_node": int(node(index).get("m_nInputValueNodeIdx", -1)), "points": points,
			"tangents": (node(index).get("m_curve", {}) as Dictionary).get("m_tangents", []),
		})
	for index in nodes_of_kind("FloatSpring"):
		var entry := spring_of(index)
		entry.merge({"node": index, "path": path(index), "kind": "FloatSpring", "input": expression(int(node(index).get("m_nInputValueNodeIdx", -1))), "input_node": int(node(index).get("m_nInputValueNodeIdx", -1))})
		out.append(entry)
	for index in nodes_of_kind("AnimationPose"):
		var entry := pose_time_of(index)
		entry.merge({"node": index, "path": path(index), "kind": "AnimationPose", "clip": clip_of(index).trim_suffix(".vnmclip"), "time": pose_time_words(index)})
		entry["input_node"] = entry["input"]
		entry.erase("input")
		out.append(entry)
	return out


## A 1D blend's inputs, each at the parameter value it is fully in at.
func _blend1d_points(index: int) -> PackedStringArray:
	var n := node(index)
	var sources: Array = n.get("m_sourceNodeIndices", [])
	var at := {}
	for blend_range: Dictionary in (n.get("m_parameterization", {}) as Dictionary).get("m_blendRanges", []):
		var values: Dictionary = blend_range.get("m_parameterValueRange", {})
		at[int(blend_range.get("m_nInputIdx0", 0))] = float(values.get("m_flMin", 0.0))
		at[int(blend_range.get("m_nInputIdx1", 0))] = float(values.get("m_flMax", 0.0))
	var out := PackedStringArray()
	for i in sources.size():
		out.append("%s at %s" % [short_summary(int(sources[i])), format_number(at.get(i, 0.0))])
	return out


## A pose node in a word or two, for lists: its clip, or its name.
func short_summary(index: int) -> String:
	var clip := clip_of(index).get_file().get_basename()
	if not clip.is_empty():
		return clip
	var child := int(node(index).get("m_nChildNodeIdx", -1))
	if kind(index) in ["DurationScale", "SpeedScale"] and child >= 0:
		return short_summary(child)
	return name_of(index) if not name_of(index).is_empty() else kind(index)


## Every value the graph tests an ID parameter for, by parameter: the
## game's vocabulary for it (action_reload, flinch_head_north...). An empty
## ID, which some tests look for, is kept as "".
func id_values() -> Dictionary:
	var out := {}
	for index: int in nodes:
		var n: Dictionary = nodes[index]
		var input := -1
		var ids: Array = []
		match kind(index):
			"IDComparison":
				input = int(n.get("m_nInputValueNodeIdx", -1))
				ids = n.get("m_comparisionIDs", n.get("m_comparisonIDs", []))
			"IDToFloat":
				input = int(n.get("m_nInputValueNodeIdx", -1))
				ids = n.get("m_IDs", [])
			"IDBasedSelector", "IDBasedClipSelector":
				input = int(n.get("m_nParameterNodeIdx", -1))
				ids = n.get("m_optionIDs", [])
			"BoneMaskSelector":
				input = int(n.get("m_parameterValueNodeIdx", -1))
				ids = n.get("m_parameterValues", [])
		if input < 0 or input >= parameters.size():
			continue
		var seen: PackedStringArray = out.get(parameters[input], PackedStringArray())
		for id: Variant in ids:
			if String(id) not in seen:
				seen.append(String(id))
		out[parameters[input]] = seen
	return out


## A state machine's states, in order: each {"name", "node" (the state
## node), "plays" (the pose node under it), "entry" (the condition that
## sends the machine straight to it on entry, -1 for none), "transitions"}.
## Each transition is {"to" (a state's index in the list), "when" (the
## condition node), "node" (the transition node), "forced" (whether it can
## interrupt a transition under way)}.
func states(machine: int) -> Array:
	var out := []
	for definition: Dictionary in node(machine).get("m_stateDefinitions", []):
		var state := int(definition.get("m_nStateNodeIdx", -1))
		var transitions := []
		for transition: Dictionary in definition.get("m_transitionDefinitions", []):
			transitions.append({
				"to": int(transition.get("m_nTargetStateIdx", -1)),
				"when": int(transition.get("m_nConditionNodeIdx", -1)),
				"node": int(transition.get("m_nTransitionNodeIdx", -1)),
				"forced": bool(transition.get("m_bCanBeForced", false)),
			})
		out.append({
			"name": name_of(state), "node": state, "plays": int(node(state).get("m_nChildNodeIdx", -1)),
			"entry": int(definition.get("m_nEntryConditionNodeIdx", -1)), "transitions": transitions,
		})
	return out


## A transition's blend in words: "0.2 s", "0.2 s, EaseInOut, synced".
func transition_blend(index: int) -> String:
	var n := node(index)
	var parts := PackedStringArray()
	var override := int(n.get("m_nDurationOverrideNodeIdx", -1))
	parts.append("%s s" % format_number(n.get("m_flDuration", 0.0)) if override < 0 else "%s s" % expression(override))
	var easing := String(n.get("m_blendWeightEasing", "Linear"))
	if easing != "Linear":
		parts.append(easing)
	var flags := int((n.get("m_transitionOptions", {}) as Dictionary).get("m_flags", 0))
	if flags != 0:
		parts.append("options %d" % flags)
	return ", ".join(parts)
