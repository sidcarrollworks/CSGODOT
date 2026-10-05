class_name UiChoiceCard
extends PanelContainer

## A reusable scene, like a Panorama layout snippet. Native containers
## measure its text; this same component is instantiated by the mode picker.
signal pointed
signal activated
@export var heading := ""
@export_multiline var description := ""
@export var accent := HudStyle.T_COLOUR
var selected := false
var disabled := false
var _bound := false
var _bound_accent: Color


func _ready() -> void:
	theme = UiStyle.menu()
	theme_type_variation = &"UiCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	%Action.mouse_entered.connect(func() -> void: pointed.emit())
	%Action.pressed.connect(func() -> void: activated.emit())
	bind(heading, description, selected, not disabled)


func bind(title: String, detail: String, lit: bool, enabled := true) -> void:
	if _bound and heading == title and description == detail and selected == lit and disabled == not enabled and _bound_accent == accent:
		return
	heading = title
	description = detail
	selected = lit
	disabled = not enabled
	if not is_node_ready():
		return
	_bound = true
	_bound_accent = accent
	%Action.disabled = disabled
	%Heading.text = heading
	%Description.text = description
	%Heading.add_theme_color_override(&"font_color", UiStyle.DISABLED if disabled else accent if selected else Color.WHITE)
	%Description.add_theme_color_override(&"font_color", UiStyle.DISABLED if disabled else UiStyle.TEXT)
	# The Theme is shared. Duplicate only this card's selected styles.
	for state: String in ["normal", "hover", "pressed"]:
		if not selected:
			%Action.remove_theme_stylebox_override(state)
			continue
		var box := theme.get_stylebox(state, &"UiButton").duplicate() as StyleBoxFlat
		box.border_color = accent
		box.bg_color = Color(1, 1, 1, 0.12)
		%Action.add_theme_stylebox_override(state, box)
