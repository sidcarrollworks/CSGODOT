extends SceneTree

## No map required. Run with --windowed --resolution 1920x1080 --script
## scripts/preview_ui.gd -- --screen gallery|mode|team|menu|settings
## [--popup] [--size 3840x2160]
## [--capture res://.godot/ui-preview.png]. Captures convert linear HDR 2D
## to sRGB in float, and quit. Without --capture this stays interactive.
func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var screen := "gallery"
	var capture := ""
	var popup := false
	var pixels := Vector2i(1920, 1080)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--screen" and i + 1 < args.size():
			screen = args[i + 1]
		elif args[i] == "--capture" and i + 1 < args.size():
			capture = args[i + 1]
		elif args[i] == "--popup":
			popup = true
		elif args[i] == "--size" and i + 1 < args.size():
			var dimensions := args[i + 1].split("x")
			if dimensions.size() == 2:
				pixels = Vector2i(maxi(320, int(dimensions[0])), maxi(180, int(dimensions[1])))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = pixels
	DisplayServer.window_set_size(pixels)
	var view: UiScreen
	match screen:
		"mode":
			var picker := ModePicker.new()
			picker.settings_file = "user://ui-preview-mode.cfg"
			view = picker
		"team":
			view = TeamPicker.new()
		"menu":
			var menu := GameMenu.new()
			menu.context_text = "Dust II · Practice"
			view = menu
		"settings":
			var settings := ClientSettingsScreen.new()
			settings.preferences = ClientPreferences.new()
			view = settings
		"gallery":
			view = (load("res://maps/ui_gallery/ui_gallery.tscn") as PackedScene).instantiate() as UiScreen
		_:
			printerr("Unknown UI screen: ", screen)
			quit(1)
			return
	root.add_child(view)
	if popup:
		var dialog := UiDialog.new()
		dialog.title = "Shared confirmation dialog"
		dialog.message = "This popup owns input until you close it. Enter confirms; Escape cancels. The screen beneath stays open."
		view.add_child(dialog)
	if capture.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		printerr("UI capture needs a graphical renderer.")
		quit(1)
		return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var linear := root.get_texture().get_image()
	var shot := Image.create(linear.get_width(), linear.get_height(), false, Image.FORMAT_RGBA8)
	for y in linear.get_height():
		for x in linear.get_width():
			shot.set_pixel(x, y, linear.get_pixel(x, y).linear_to_srgb())
	var error := shot.save_png(capture)
	print("UI capture: ",capture," ",shot.get_size()," result ",error)
	quit(0 if error == OK else 1)
