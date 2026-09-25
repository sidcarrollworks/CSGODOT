# Godot 4.7: input

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: changing `PlayerInput`, the bind table (`reference/binds.md`, roadmap 12a), mouse look and sensitivity, menus that take keys, the console, or anything that reads a key, a mouse button or the wheel.

## Rules for this project

- Only the command builder (`PlayerInput`, the future bind dispatcher) and an open menu read input. The simulation reads `UserCmd`s. `Input`'s state is global and is **not** changed by `set_input_as_handled()` or `accept_event()` (`classes/class_input.rst`), so a system that polls `Input` sees keys a menu already took. `tests/run_contract_checks.gd` and `tests/run_economy_checks.gd` already ban `Input.` in simulation files. Keep it that way.
- Aim with `InputEventMouseMotion.screen_relative`, not `relative`. `relative` is scaled by the content scale factor that `display/window/stretch/mode` sets. This project uses `canvas_items` on a 1920x1080 base, so at 4K `relative` is half the real mouse movement and CS2's sensitivity numbers come out half as fast. The class ref says to use `screen_relative` for `MOUSE_MODE_CAPTURED` aiming "regardless of the project's stretch mode" (`classes/class_inputeventmousemotion.rst`). See "Where the code already does this" for the current bug.
- Bind game keys by `physical_keycode`: it is the key's position on a US QWERTY board, "meant for game input, such as WASD" (`classes/class_inputeventkey.rst`). Use `keycode` only for shortcuts named by their letter, and `key_label` only for showing a key to the player.
- A key goes to one place. When a node has acted on an event, it calls `get_viewport().set_input_as_handled()`. Nothing else stops the event reaching every other `_unhandled_input` (`tutorials/inputs/inputevent.rst`). Binds.md's dispatcher needs this.
- Menus that must take keys first use `_input()` (it runs before the GUI and before every unhandled callback). Gameplay uses `_unhandled_input()` or `_unhandled_key_input()`, so an open menu wins (`tutorials/inputs/inputevent.rst`).
- Record press and release events from the event callbacks. Hold state can come from polling in the command builder. A press and release inside one frame never shows in `Input.is_action_pressed()` at the tick, but it does arrive as two events. (`Input.is_action_just_pressed()` does keep it; see its note in Class notes.)
- Do not use the built-in `ui_*` actions for gameplay: "Because these actions are used for focus they should not be used for any gameplay code" (`tutorials/ui/gui_navigation.rst`). `ui_accept` includes Space and Enter, so a focused `Button` fires on the jump key.
- Treat the mouse wheel as button presses: `MOUSE_BUTTON_WHEEL_UP` and `MOUSE_BUTTON_WHEEL_DOWN` are separate `InputEventMouseButton` events (`tutorials/inputs/input_examples.rst`). There is no hold state to poll.

## How an event travels (`tutorials/inputs/inputevent.rst`, `classes/class_viewport.rst`)

The DisplayServer reads OS events and feeds them to the root `Window`. Its `Viewport` then does these steps, in order, and stops as soon as something marks the event handled:

1. Embedded-window management, when the viewport embeds windows (moving and resizing them).
2. If an embedded `Window` has focus, the event goes to it and is treated as handled.
3. `Node._input(event)` on every node that overrides it and has not turned it off with `set_process_input(false)`.
4. The GUI: `Control._gui_input(event)` and the `gui_input` signal on the Control under the mouse, or on the focused Control for keys and joypad buttons. `Control.accept_event()` stops the event. `mouse_filter` decides which Controls get mouse events and whether the event bubbles.
5. `Node._shortcut_input(event)`, only for `InputEventKey`, `InputEventShortcut` and `InputEventJoypadButton`.
6. `Node._unhandled_key_input(event)`, only for `InputEventKey`. Mouse motion is filtered out, so it is cheaper than `_unhandled_input` for key-only handlers.
7. `Node._unhandled_input(event)`, for every event type.
8. Physics object picking, if `Viewport.physics_object_picking` is on (default `false`; at most 64 pickable objects, picked in no fixed order).

- Within each step, nodes are called in **reverse depth-first order**: the deepest node at the bottom of the tree first, the root last. `_gui_input` does not follow this order. It goes by where the mouse is, or by focus.
- GUI mouse events bubble up only through the target Control's ancestors, subject to `mouse_filter`. GUI key and joypad events do **not** bubble. If the focused Control does not handle one, it carries on as a non-GUI event to steps 5 to 7.
- `Viewport.set_input_as_handled()` stops the event at any step. `is_input_handled()` reads that flag. Neither affects `Input`'s polled state.
- `Viewport.push_input(event, in_local_coords=false)` injects an event and runs steps 3 to 7 in the same order. The docs name it for "inputs that were sent over the network or saved to a file", but this project should replay `UserCmd`s, not raw events. `push_unhandled_input` is **deprecated**.
- `Input.parse_input_event(event)` feeds an event as if the OS sent it, including `_input` calls. `Input.action_press(action)` only changes polled state and does **not** call `_input`.
- SubViewports get no events from their parent viewport unless they sit in a `SubViewportContainer`.

## Frames, ticks and accumulated input (`classes/class_input.rst`, `classes/class_inputeventmousemotion.rst`, `classes/class_projectsettings.rst`)

- `Input.use_accumulated_input` defaults to **true**. "All input events generated during a frame will be merged and emitted when the frame is done rendering", so input callbacks run at most at the render frame rate. `InputEvent.accumulate()` only merges `InputEventMouseMotion`: the later event's position and velocity are kept, `relative` is the sum of both, and both events must have the same modifiers.
- By default, `InputEventMouseMotion` is emitted "once per frame rendered at most". Set `use_accumulated_input = false` to get events "as often as possible", at a CPU cost.
- `input_devices/buffering/agile_event_flushing` (flush before every physics step) is **Android only**. On desktop, events are flushed "once per process frame, between iterations of the engine". `Input.flush_buffered_events()` forces a flush.
- What this means for sub-tick timing (inferred from the above, not stated in the docs): every event of a frame reaches `_unhandled_input` at about the same moment, before that frame's physics steps. `PlayerInput._event` stamps each event with `Time.get_ticks_usec()` **when it is handled**, not when the OS saw it. So a press's sub-tick fraction is only as precise as the frame time: about 7 ms at 144 fps, and 16.7 ms at 60 fps with V-Sync on. V-Sync is on by default (`display/window/vsync/vsync_mode = 1`). When one frame runs two or more 64 Hz ticks, all of that frame's events land in the first tick's command. `InputEvent` has no OS timestamp member in 4.7 (checked in `classes/class_inputevent.rst`). Turning accumulation off gives better resolution only if the OS delivers events between frames. Measure it on Sid's machine (Local).
- `physics/common/physics_jitter_fix` defaults to `0.5`. The docs say to set it to `0.0` when the project draws its own interpolation (it does: `SimClock`, `PlayerView`), and for network games. With jitter fix on, ticks drift from the wall clock that `PlayerInput` stamps events against.
- `Input.is_action_just_pressed()` is true "in the current frame or physics tick". Since 4.x it also stays true for a press that was released again before the query ("so as not to miss input"). During event handling, use `InputEvent.is_action_pressed()` instead (class ref note). `input_devices/compatibility/legacy_just_pressed_behavior` exists for the old behaviour.

## Keys (`classes/class_inputeventkey.rst`, `classes/class_input.rst`)

- There are three identities. `keycode` is the Latin label in the current layout, for shortcuts such as Ctrl+S. `physical_keycode` is the position on a 101/102-key US QWERTY board, for game input. `key_label` is the localized label printed on the key, for prompts. For a physical key's name as the player's layout shows it, use `OS.get_keycode_string(DisplayServer.keyboard_get_label_from_physical(event.physical_keycode))`.
- An action event should set only one of `keycode`, `physical_keycode` or `unicode`. When events are compared, they are checked in that priority order, and the first one that matches decides.
- `echo` is a repeat sent while a key is held: about 20 per second after about 0.5 s, but set by the OS and possibly off. `InputEvent.is_action_pressed(action, allow_echo=false, exact_match=false)` ignores echoes by default.
- `Input.is_physical_key_pressed(KEY_W)` is recommended over `is_key_pressed` for game input. For a "just pressed" by physical key, check it in `_input` with `not event.is_echo() and event.is_pressed() and event.physical_keycode == ...`.
- `location` (KeyLocation) tells left Shift/Ctrl/Alt from right.
- Keyboard ghosting: some key combinations do not register on keyboards without anti-ghosting, and `is_action_pressed` can then be false while the key is held (`tutorials/inputs/input_examples.rst`).

## Mouse (`classes/class_inputeventmousemotion.rst`, `classes/class_inputeventmousebutton.rst`, `tutorials/inputs/mouse_and_input_coordinates.rst`)

- `Input.mouse_mode` takes `MOUSE_MODE_VISIBLE`=0, `HIDDEN`=1, `CAPTURED`=2, `CONFINED`=3 or `CONFINED_HIDDEN`=4. `CAPTURED` hides the cursor and locks it to the window's centre, so `event.position` is always the centre. Read the motion from `relative` or `screen_relative`.
- `relative` is the movement since the previous event, **scaled by the content scale factor** (stretch mode). `screen_relative` is the **unscaled** movement in screen coordinates. It is not affected by the content scale or by `xformed_by()`, and the docs prefer it "for mouse aiming when using MOUSE_MODE_CAPTURED, regardless of the project's stretch mode".
- `velocity` and `screen_velocity` are pixels per second and return `(0, 0)` in `CAPTURED`. `Input.get_last_mouse_velocity()` is recomputed only every 0.1 s, so it lags. Neither is usable for aim.
- A motion event can arrive with no movement. Check `relative.is_zero_approx()`. You cannot tell the mouse stopped from the events alone.
- The docs do not say whether captured motion is raw, unaccelerated counts on each OS. CS2's `m_yaw 0.022` per count assumes raw counts. Check it on Sid's Windows machine (Local): turn the mouse a measured distance at a known DPI and sensitivity against a 360 in CS2.
- The wheel sends `InputEventMouseButton` with `button_index` `MOUSE_BUTTON_WHEEL_UP` or `MOUSE_BUTTON_WHEEL_DOWN` (also `WHEEL_LEFT`/`RIGHT`). `factor` is the scroll amount for high-precision wheels on some platforms, and may be 0. A wheel notch sends a press and a release (inferred from how the input map treats it as an action; the docs do not describe the release). Act on the press only.
- `InputEventMouseButton.canceled` and `double_click` exist. `InputEventMouse.button_mask` gives the buttons held during any mouse event.
- `Input.warp_mouse(pos)` works on Windows, macOS and Linux only.

## Actions and the InputMap (`tutorials/inputs/inputevent.rst`, `classes/class_inputmap.rst`)

- `InputMap` is loaded from `project.godot`'s `[input]` section and **is not saved** when changed at runtime. A rebinding system stores its own file and re-applies it. That is binds.md step 8: a user file in CS2's `bind` syntax.
- `InputMap.add_action(action, deadzone=0.2)`, `action_add_event(action, event)`, `action_erase_event`, `action_erase_events`, `action_get_events`, `has_action`, `erase_action`, `get_actions`, and `load_from_project_settings()` (clears and reloads). The `project_settings_loaded` signal also exists.
- `Input.get_axis(neg, pos)` is `get_action_strength(pos) - get_action_strength(neg)`. `get_vector()` limits length to 1 with a circular deadzone. For keys, strength is 0 or 1.
- The `deadzone` is per action. Only analog axes care about it.
- Actions are not required. The binds.md dispatcher can map `physical_keycode` or mouse `button_index` straight to a command and skip the InputMap for game keys, keeping `ui_*` for menus.

## Controllers (`tutorials/inputs/controllers_gamepads_joysticks.rst`)

Out of scope for CS2 parity. Two facts in case a pad is ever plugged in: controller input reaches unfocused windows unless `input_devices/joypads/ignore_joypad_on_unfocused_application` is true, and Windows supports at most 4 XInput controllers.

## Class notes

**Input** (`classes/class_input.rst`)
- `mouse_mode: MouseMode` (`set_mouse_mode`/`get_mouse_mode`). `use_accumulated_input: bool = true`.
- `is_action_pressed(action: StringName, exact_match: bool = false) -> bool`. `is_action_just_pressed(action, exact_match=false)`. `is_action_just_released(action, exact_match=false)`. `is_action_just_pressed_by_event(action, event, exact_match=false)` is new: it is for processing inside `_input`.
- `get_axis(negative_action, positive_action) -> float`. `get_vector(neg_x, pos_x, neg_y, pos_y, deadzone=-1.0) -> Vector2`. `get_action_strength` and `get_action_raw_strength`.
- `is_physical_key_pressed(keycode) -> bool`, `is_key_pressed`, `is_key_label_pressed`, `is_mouse_button_pressed(button)`, `get_mouse_button_mask()`.
- `parse_input_event(event)` calls `_input`. `action_press(action, strength=1.0)` and `action_release(action)` do not. `flush_buffered_events()`.
- Gotcha: its state is global and ignores `set_input_as_handled()`/`accept_event()`.

**InputEvent** (`classes/class_inputevent.rst`)
- `device: int = 0`. `DEVICE_ID_EMULATION = -1` marks mouse emulated from touch, or touch from mouse. `DEVICE_ID_KEYBOARD` and `DEVICE_ID_MOUSE` exist; project.godot's events carry device 16 and 32.
- `is_action_pressed(action, allow_echo=false, exact_match=false)`, `is_action_released(action, exact_match=false)`, `is_action(action, exact_match=false)`, `is_echo()`, `is_pressed()`, `is_released()`, `is_canceled()`, `get_action_strength`, `is_match(event, exact_match=true)` (compares configuration, not pressed state), `accumulate(with_event)`, `xformed_by(xform, local_ofs)`, `as_text()`.
- Not relevant to `InputEventMouseMotion`: `is_action_pressed` on a motion event is always false.

**InputEventKey** (`classes/class_inputeventkey.rst`)
- `keycode`, `physical_keycode`, `key_label` (all `Key`, default 0), `unicode`, `echo`, `pressed`, `location`.
- `get_physical_keycode_with_modifiers()`, `get_keycode_with_modifiers()`, `as_text_physical_keycode()`.
- Modifiers come from `InputEventWithModifiers` (`shift_pressed`, `ctrl_pressed`, `alt_pressed`, `meta_pressed`).

**InputEventMouseMotion** (`classes/class_inputeventmousemotion.rst`)
- `relative: Vector2` (scaled), `screen_relative: Vector2` (unscaled), `velocity`, `screen_velocity` (both 0 in CAPTURED), `pressure`, `tilt`, `pen_inverted`. `position` and `global_position` come from `InputEventMouse`.

**InputEventMouseButton** (`classes/class_inputeventmousebutton.rst`)
- `button_index: MouseButton` (`MOUSE_BUTTON_LEFT`, `RIGHT`, `MIDDLE`, `WHEEL_UP`, `WHEEL_DOWN`, `WHEEL_LEFT`, `WHEEL_RIGHT`, `XBUTTON1`, `XBUTTON2`). `pressed`, `factor: float = 1.0`, `double_click`, `canceled`.

**InputMap** (`classes/class_inputmap.rst`)
- See the list above. Changes are runtime-only and never written back to `project.godot`.

**Viewport (input members)** (`classes/class_viewport.rst`)
- `set_input_as_handled()`, `is_input_handled()`, `push_input(event, in_local_coords=false)`, `handle_input_locally: bool = true` (a `SubViewportContainer` sets it false on its child), `gui_disable_input: bool = false` (setter `set_disable_input`), `gui_get_focus_owner()`, `gui_release_focus()`, `physics_object_picking: bool = false`.

**Node (input callbacks)** (`classes/class_node.rst`)
- `_input(event)`, `_shortcut_input(event)`, `_unhandled_key_input(event)`, `_unhandled_input(event)`. Each is enabled automatically when overridden and can be switched off with `set_process_input`, `set_process_shortcut_input`, `set_process_unhandled_key_input` and `set_process_unhandled_input`. None is called on a node outside the tree. `process_mode` also gates them when paused (inferred from `can_process()`; the pause menu, item 26, will need `PROCESS_MODE_ALWAYS` on its UI).

**DisplayServer (input side)** (`classes/class_displayserver.rst`)
- `mouse_set_mode(mode)`, the same as `Input.mouse_mode`. `keyboard_get_keycode_from_physical(physical)` and `keyboard_get_label_from_physical(physical)` are for showing binds.

## Where the code already does this

- `src/player/player_input.gd`: `handle_event` turns mouse motion into yaw and pitch, and action events into timestamped `ButtonEvent`s. `build_command` polls held buttons with `Input.is_action_pressed` (:233) and movement with `Input.get_axis` (:236-237). `ensure_actions()` adds actions to the `InputMap` at runtime with `physical_keycode`.
- `src/player/player_controller.gd:52` captures the mouse. `:71` `_unhandled_input` toggles capture on `ui_cancel` and forwards to `PlayerInput` only while captured. It never calls `set_input_as_handled()` (binds.md system point 5).
- `src/economy/buy_menu.gd:72` uses `_input` to take B, Escape and every key press while open, calling `set_input_as_handled()`, and saves and restores `mouse_mode`.
- `src/ui/game_hud.gd:112` and `src/modes/competitive.gd:325` use `_unhandled_key_input` for F3 and F5.
- `maps/test_range/test_range.gd:205` and `maps/test_range/grenade_lane.gd:98` handle range actions in `_unhandled_input`, and the range's `BOMB_KIT_KEY` by `physical_keycode`.
- `scripts/setup_input_map.gd` writes the input map with physical keycodes. `project.godot` `[input]` binds every key by `physical_keycode` with `keycode` 0.

Looks at odds with the docs (not verified in play):
- `src/player/player_input.gd:130-131` aims with `motion.relative`. `project.godot:22` sets `window/stretch/mode="canvas_items"` on a 1920x1080 base, so `relative` is divided by the content scale factor: 2 in a 3840x2160 window. Sensitivity is then half of CS2's at 4K and exact only at 1080p. The docs say to use `screen_relative`. A fix is `motion.screen_relative`, plus a check that feeds an event with a known `screen_relative`.
- `src/player/player_input.gd:159-161` stamps events with `Time.get_ticks_usec()` at dispatch, and dispatch happens once per frame (above). Sub-tick fractions are frame-quantised and are all near the end of the stretch covered. This is not wrong, but it is coarser than the comments suggest. Measure it at Sid's frame rate.
- `src/ui/game_hud.gd:114` (F3) and `src/modes/competitive.gd:327` (F5) compare `key.keycode`, not `physical_keycode`, against binds.md point 6. Harmless for F keys, but inconsistent with the bind table.
- `src/player/player_controller.gd:72` uses the built-in `ui_cancel` for gameplay, against `tutorials/ui/gui_navigation.rst`'s warning. It is the Escape key, and binds.md keeps it "until item 26's pause menu".
- `project.godot` does not set `physics/common/physics_jitter_fix`, so it is `0.5`. The docs say `0.0` for custom interpolation and for network games.
- Held buttons are polled (`player_input.gd:233`), so while the buy menu has "taken" the keyboard, held R, E, Space, Ctrl and Shift still reach the command. Only the mouse buttons are gated, by `has_mouse`. This may be intended, since CS2 lets you move in the buy menu, but binds.md's "an open menu takes keys first" is only true for event-driven binds.

## Not covered here

- Touch, gestures, pen and MIDI: `classes/class_inputeventscreentouch.rst` and the related class pages.
- Custom cursors (menus): `tutorials/inputs/custom_mouse_cursor.rst`.
- Quit requests and window close (`NOTIFICATION_WM_CLOSE_REQUEST`), needed for the menus' quit: `tutorials/inputs/handling_quit_requests.rst`.
- Controller motion sensors, vibration and LEDs: `tutorials/inputs/controller_features.rst`.
- Focus navigation and `ui_*` actions for menus: see `ui.md`, and `tutorials/ui/gui_navigation.rst`.
- Stretch mode and 4K UI scaling: see `ui.md`, and `tutorials/rendering/multiple_resolutions.rst`.
