class_name UiStyle
extends RefCounted

## Shared menu theme: Panorama's common stylesheet becomes a native Theme,
## named type variations become reusable classes, and scenes own layout.
## Colours/fonts reuse HudStyle; spacing below is our menu design policy.
const BACKDROP := Color(0.02, 0.02, 0.03, 0.92)
const TEXT := Color(0.8, 0.8, 0.8)
const MUTED := Color(1, 1, 1, 0.55)
const DISABLED := Color8(130, 130, 130)
const GAP := 24
const INSET := 28
const HUD_LAYER := 1
const MENU_LAYER := 10
const MODAL_LAYER := 20
const FADE_SECONDS := 0.15

static var _menu: Theme


static func menu() -> Theme:
	if _menu != null:
		return _menu
	_menu = Theme.new()
	_menu.default_font = HudStyle.face(&"regular")
	_menu.default_font_size = 22
	for spec: Array in [["UiTitle", 44, &"bold_tf", Color.WHITE],
		["UiHeading", 36, &"bold_tf", Color.WHITE],
		["UiBody", 22, &"regular", TEXT], ["UiMuted", 22, &"regular", MUTED]]:
		_menu.set_type_variation(spec[0], &"Label")
		_menu.set_font(&"font", spec[0], HudStyle.face(spec[2]))
		_menu.set_font_size(&"font_size", spec[0], spec[1])
		_menu.set_color(&"font_color", spec[0], spec[3])
	_menu.set_type_variation(&"UiButton", &"Button")
	_menu.set_type_variation(&"UiCard", &"PanelContainer")
	_menu.set_stylebox(&"panel", &"UiCard", StyleBoxEmpty.new())
	_menu.set_type_variation(&"UiSurface", &"PanelContainer")
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color8(38, 38, 38)
	surface.set_content_margin_all(INSET)
	_menu.set_stylebox(&"panel", &"UiSurface", surface)
	_menu.set_font(&"font", &"UiButton", HudStyle.face(&"bold_tf"))
	_menu.set_font_size(&"font_size", &"UiButton", 28)
	_menu.set_color(&"font_color", &"UiButton", Color.WHITE)
	_menu.set_color(&"font_disabled_color", &"UiButton", DISABLED)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.12 if state in ["hover", "pressed"] else 0.04)
		box.border_color = Color(1, 1, 1, 0.25)
		box.set_border_width_all(2)
		box.content_margin_left = INSET
		box.content_margin_right = INSET
		box.content_margin_top = 18
		box.content_margin_bottom = 18
		_menu.set_stylebox(state, &"UiButton", box)
	_menu.set_type_variation(&"UiMenuBarButton", &"UiButton")
	_menu.set_font_size(&"font_size", &"UiMenuBarButton", 24)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bar_box := _menu.get_stylebox(state, &"UiButton").duplicate() as StyleBoxFlat
		bar_box.content_margin_left = 18
		bar_box.content_margin_right = 18
		bar_box.content_margin_top = 12
		bar_box.content_margin_bottom = 12
		_menu.set_stylebox(state, &"UiMenuBarButton", bar_box)
	# Settings reuse Panorama's 48px rows, compact right-aligned sliders and
	# 80px value boxes rather than stretching every control across the page.
	_menu.set_type_variation(&"UiSettingsSurface", &"PanelContainer")
	var settings_surface := StyleBoxEmpty.new()
	settings_surface.set_content_margin_all(INSET)
	_menu.set_stylebox(&"panel", &"UiSettingsSurface", settings_surface)
	_menu.set_type_variation(&"UiSettingsRow", &"PanelContainer")
	var row := StyleBoxFlat.new()
	row.bg_color = Color.TRANSPARENT
	row.border_color = Color(1, 1, 1, 0.08)
	row.border_width_bottom = 1
	row.content_margin_top = 4
	row.content_margin_bottom = 4
	_menu.set_stylebox(&"panel", &"UiSettingsRow", row)
	_menu.set_type_variation(&"UiSettingsTitle", &"UiTitle")
	_menu.set_font_size(&"font_size", &"UiSettingsTitle", 32)
	_menu.set_type_variation(&"UiSettingsHeading", &"UiHeading")
	_menu.set_font_size(&"font_size", &"UiSettingsHeading", 28)
	_menu.set_type_variation(&"UiSettingsValue", &"UiBody")
	_menu.set_font_size(&"font_size", &"UiSettingsValue", 20)
	var value_box := StyleBoxFlat.new()
	value_box.bg_color = Color(1, 1, 1, 0.015)
	value_box.border_color = Color(0.8, 0.8, 0.8, 0.08)
	value_box.set_border_width_all(2)
	value_box.set_content_margin_all(5)
	_menu.set_stylebox(&"normal", &"UiSettingsValue", value_box)
	_menu.set_type_variation(&"UiSettingsInput", &"LineEdit")
	_menu.set_stylebox(&"normal", &"UiSettingsInput", value_box)
	var focused_box := value_box.duplicate() as StyleBoxFlat
	focused_box.border_color = Color(0.51, 0.85, 1, 0.6)
	_menu.set_stylebox(&"focus", &"UiSettingsInput", focused_box)
	_menu.set_color(&"font_color", &"UiSettingsInput", TEXT)
	_menu.set_type_variation(&"UiSettingsSlider", &"HSlider")
	for part: String in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.8, 0.8, 0.8, 0.2 if part == "slider" else 0.75)
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		_menu.set_stylebox(part, &"UiSettingsSlider", track)
	var thumb := GradientTexture2D.new()
	thumb.width = 16
	thumb.height = 12
	thumb.gradient = Gradient.new()
	thumb.gradient.colors = PackedColorArray([TEXT, TEXT])
	_menu.set_icon(&"grabber", &"UiSettingsSlider", thumb)
	_menu.set_icon(&"grabber_highlight", &"UiSettingsSlider", thumb)
	_menu.set_constant(&"separation", &"VBoxContainer", GAP)
	_menu.set_constant(&"separation", &"HBoxContainer", GAP)
	return _menu


## Store translated, plain text in native Labels. No markup interpretation.
static func label(value: String, variant: StringName = &"UiBody") -> Label:
	var result := Label.new()
	result.theme = menu()
	result.theme_type_variation = variant
	result.text = value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result
