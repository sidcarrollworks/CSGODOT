# Building a UI

New screens use the same fonts, colors, components and input lifecycle as
existing screens. The [Panorama audit](research/panorama-ui-2026-10-04.md)
explains the source evidence and the mapping. Read [Godot UI](godot/ui.md)
before adding engine-specific behavior.

## Choose the kind of view

Use `HudElement` for a compact, frequently updated HUD component whose exact
geometry is already known. Read state per frame and call `show_state()` or
`redraw()` only on change; animate only while needed. Keep noninteractive
nodes `MOUSE_FILTER_IGNORE`. Preserve bounded blur regions and additive
materials where the CS2 component uses them.

Use native scene trees for menus, dialogs, forms and text-driven lists. Put
structure in `.tscn`, appearance in the shared Theme and behavior in a small
view script. Use containers for text/list flow rather than computing each
label's baseline and click rectangle independently. Don't rebuild a list
every frame. Reuse rows, update changed fields and disconnect external event
listeners on exit. Game-state changes are commands, never direct writes from
the view.

## Start a screen

Extend `UiScreen` and call `super._ready()`. Mount a full-rect Control scene:

```gdscript
extends UiScreen
const VIEW := preload("res://path/to/view.tscn")

func _ready() -> void:
    super._ready()
    var view := mount(VIEW)
    view.get_node("%Close").pressed.connect(_close)

func _close() -> void:
    close_screen() # releases ownership before a result opens another screen
    queue_free()
```

`mount()` applies the cached Theme, blocks backdrop mouse/scroll input and
plays a 0.15-second reveal. Its Tween is bound to the view and dies with it.
The shell owns keys until closed; override `handle_key(event)` for explicit
shortcuts and return false for keys a focused native field should receive.
Unused keys are blocked after the GUI phase, including shortcut handlers;
focus from an underlying screen is released and restored on close.
Mouse actions belong to Button signals or `_gui_input`. Do not
consume them in `_input` before the GUI receives them. Do not independently
capture/restore the mouse: the shell does it, including `_exit_tree` cleanup.
The reusable `UiDialog` uses Enter/Escape and emits `confirmed`/`cancelled`.

The layer convention is HUD 1, menus from 10, popups from 20. Nested screens
receive distinct higher layers. Creating a screen, closing a screen and
removing it from the tree are separate operations; release ownership before
emitting a result and guard against resolving twice.

For an existing in-game custom-drawn menu, acquire a `UiInputScope` only while
open. Release it on close and exit; consult `is_top()`/`available_to(self)`
before processing input. This is how `BuyMenu` preserves its drawing and
polled movement while sharing popup cursor ownership.
Other legacy `_input` readers must consult `available_to(self)` too: that
phase runs before GUI controls can consume the event. `Scoreboard` gates new
Tab presses this way and always accepts release to avoid a latched board.

Event ownership does not pause the simulation or suppress Godot's global
`Input` polling. `PlayerInput` deliberately polls movement while buying.
A future in-match pause/settings host must explicitly choose whether gameplay
commands continue or are neutralized; add checks for that policy. Do not assume
`set_input_as_handled()` stops a polled action.

## Layout and styles

Design in the existing 1920x1080 logical canvas. Godot's canvas stretch scales
it to 4K; do not multiply font sizes or mouse coordinates by the monitor
resolution. The current keep-aspect policy letterboxes other aspect ratios.
An aspect/UI-scale change is a separate feature, with its own visual checks.

- Anchor screen roots and backdrops full-rect. Anchor compact HUD elements
  to their corner/center region.
- Use VBox/HBox containers with `UiStyle.GAP`, and margins from `UiStyle.INSET`.
  A Container owns child positions; use minimum sizes and size flags.
- Set `theme_type_variation` to `UiTitle`, `UiHeading`, `UiBody`, `UiMuted`,
  `UiButton`, `UiCard` or `UiSurface`. The Theme uses HudStyle's font cache.
- Use `UiChoiceCard` for a heading/description choice. Instantiate
  `src/ui/components/choice_card.tscn`, connect `activated` and call
  `bind(title, description, selected, enabled)`. Its native Button handles
  pointer hit testing while decorative children ignore the mouse. Binding
  before mounting preserves the configured selection/disabled state.
- Share resources, but duplicate an instance's changed StyleBox. Never alter
  the shared Theme or its StyleBoxes to select one card.
- Labels show plain text. Supply translated strings with `tr()` when a
  catalog exists. Do not enable markup for untrusted player text.
- In-game buttons use FOCUS_NONE to avoid default Space/jump activation.
  Explicit screen shortcuts do not depend on default `ui_accept`. Future
  controller navigation needs an intentional focus/action policy.

Put new shared typography/colors in `UiStyle` or `HudStyle` with provenance.
Component-specific dimensions remain in its scene/script. Preserve an accepted
CS2 HUD's measured spacing instead of imposing menu padding on it.

## Preview and check

Run `maps/ui_gallery/ui_gallery.tscn` with F6 for the shared component gallery.
Its button opens a real confirmation dialog. No map extraction is needed;
fonts fall back to the bundled Rajdhani where CS2's Stratum2 isn't extracted.

```powershell
godot --path . --script scripts/preview_ui.gd -- --screen gallery
godot --path . --script scripts/preview_ui.gd -- --screen mode --size 1920x1080 `
  --capture res://.godot/mode-preview.png
godot --path . --script scripts/preview_ui.gd -- --screen gallery --popup `
  --size 3840x2160 --capture res://.godot/dialog-preview.png
```

The preview defaults to a 1080p window and needs a graphical renderer for
captures. Captures convert linear HDR 2D to sRGB without first quantizing it.
Save generated images under ignored `.godot/`.

Add behavior/layout checks alongside the component. Run
`scripts/run_tests.sh ui_foundation map_mode economy hud`, then the full suite
before opening a PR. Review screenshots at 1080p and 4K, long labels, selected
and disabled states, pointer activation and nested popup closure. A static
screen should have no new `_process` polling loop after its transition ends.
Cached commands still cost GPU compositing; profile blur, 3D previews and
large lists separately when adding them.
