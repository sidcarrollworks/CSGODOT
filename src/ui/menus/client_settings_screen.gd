class_name ClientSettingsScreen
extends UiScreen

## Native controls edit an independent draft. The host decides how an
## accepted result is applied and saved; this screen never writes live state.
signal applied(value: ClientPreferences)
signal cancelled

var preferences: ClientPreferences
var draft: ClientPreferences
var _sensitivity: SpinBox
const VIEW := preload("res://src/ui/menus/client_settings_view.tscn")
const MUSIC_FIELDS := {
	"MusicVolume": &"music_volume",
	"RoundStart": &"round_start",
	"RoundAction": &"round_action",
	"RoundEnd": &"round_end",
	"Mvp": &"mvp",
	"MapObjective": &"map_objective",
	"TenSecondWarning": &"ten_second_warning",
	"DeathCamera": &"death_camera",
	"MenuMusic": &"menu_music",
}


func _ready() -> void:
	super._ready()
	draft = (preferences if preferences != null else ClientPreferences.new()).copy()
	var view := mount(VIEW)
	_sensitivity = view.get_node("%Sensitivity") as SpinBox
	_sensitivity.get_line_edit().theme_type_variation = &"UiSettingsInput"
	_sensitivity.set_value_no_signal(draft.sensitivity)
	_sensitivity.value_changed.connect(_set_sensitivity)
	for control_name: String in MUSIC_FIELDS:
		var field: StringName = MUSIC_FIELDS[control_name]
		var slider := view.get_node("%" + control_name) as HSlider
		var readout := view.get_node("%" + control_name + "Value") as Label
		var percent := float(draft.audio.get(field)) * 100.0
		slider.set_value_no_signal(percent)
		readout.text = "%d%%" % roundi(slider.value)
		slider.value_changed.connect(_set_music.bind(field, readout))
	view.get_node("%Apply").pressed.connect(apply)
	view.get_node("%Cancel").pressed.connect(cancel)


func _set_sensitivity(value: float) -> void:
	draft.sensitivity = value


func _set_music(percent: float, field: StringName, readout: Label) -> void:
	draft.audio.set(field, percent / 100.0)
	readout.text = "%d%%" % roundi(percent)


func apply() -> void:
	if _closing or is_queued_for_deletion():
		return
	# Commit text that has been edited but not submitted with Enter yet.
	_sensitivity.apply()
	close_screen()
	applied.emit(draft)
	queue_free()


func cancel() -> void:
	if _closing or is_queued_for_deletion():
		return
	close_screen()
	cancelled.emit()
	queue_free()


func handle_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return false
	cancel()
	return true
