extends UiScreen

## Run this scene to review shared components before using them in a screen.
const VIEW := preload("res://maps/ui_gallery/ui_gallery_view.tscn")
const CARD := preload("res://src/ui/components/choice_card.tscn")
var _status: Label


func _ready() -> void:
	super._ready()
	var view := mount(VIEW)
	_status = view.get_node("%Status") as Label
	var cards := view.get_node("%Cards") as VBoxContainer
	for spec: Array in [["A reusable choice", "Shared font, padding and hover style.", false, true],
		["Selected choice", "Selection changes only this card, never the shared Theme.", true, true],
		["Unavailable choice", "Disabled actions keep their text readable and cannot activate.", false, false]]:
		var card := CARD.instantiate() as UiChoiceCard
		cards.add_child(card)
		card.bind(spec[0], spec[1], spec[2], spec[3])
		card.activated.connect(func() -> void: _status.text = "Choice activated")
	view.get_node("%Popup").pressed.connect(_popup)


func _popup() -> void:
	var dialog := UiDialog.new()
	dialog.title = "Shared confirmation dialog"
	dialog.message = "This popup owns input until you close it. Enter confirms; Escape cancels. The screen beneath stays open."
	dialog.confirmed.connect(func() -> void: _status.text = "Confirmed")
	dialog.cancelled.connect(func() -> void: _status.text = "Cancelled")
	add_child(dialog)
