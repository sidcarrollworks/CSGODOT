extends SceneTree

## Whether the Box3D GDExtension loaded: the game's physics (project.godot's
## csgodot/physics/backend), without which a match's world never ticks and a
## check waiting on one waits for ever. scripts/run_tests.sh runs it after the
## import and stops the run when it fails.
##
##   godot --headless --path . --script scripts/check_box3d.gd
##
## Runs before the class_name scripts are needed, so it names none.


func _init() -> void:
	var classes := [&"Box3DWorld", &"Box3DBody", &"Box3DContactRules"]
	var missing := classes.filter(func(name: StringName) -> bool: return not ClassDB.class_exists(name))
	if ClassDB.class_exists(&"Box3DWorld") and not ClassDB.class_has_method(&"Box3DWorld", &"shape_cast_projectile_box"):
		missing.append(&"Box3DWorld.shape_cast_projectile_box (rerun installer)")
	if missing.is_empty():
		print("BOX3D loaded")
		quit(0)
		return
	printerr("BOX3D missing (%s): the addon is not installed in this checkout, or its library cannot load here (Godot's error above says which; a Linux build needs a glibc at least as new as the system it was built on). Install it with scripts/install_box3d.sh (Linux, macOS) or scripts/install_box3d.ps1 (Windows)." % ", ".join(missing))
	quit(1)
