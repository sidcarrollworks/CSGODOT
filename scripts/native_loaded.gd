extends SceneTree

## Whether the game's native code is loaded and was built from the sources
## that are here. scripts/build_native.sh and .ps1 end with it, since a
## library can be built and still not load (a name the .gdextension does not
## have, a symbol left undefined), and the game would run on by the script
## and say nothing.
##
##   godot --headless --path . --script scripts/native_loaded.gd
##
## Its exit code is 0 where the native code will run the movement's step,
## and 1 where the script will.


func _initialize() -> void:
	if PlayerBody.native_built():
		print("NATIVE loaded: %s, built from the sources here (%s)" % [PlayerBody.NATIVE_CLASS, PlayerBody.native_sources().left(12)])
		quit(0)
		return
	printerr("NATIVE not loaded: %s" % PlayerBody.native_missing)
	quit(1)
