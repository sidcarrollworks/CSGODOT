# Godot 4.7: UI and HUD

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: building or changing the HUD (`src/ui/`), the buy menu, the scoreboard (item 15), the console, menus and settings (item 26), or anything drawn with Control nodes, or when checking how the UI looks at 4K.

## Rules for this project

- The HUD and menus only read the simulation, per frame (`_process`, `_draw`). They never change game state except by sending a command (`game.command`), as the buy menu does.
- Every Control laid over the game view that is not meant to be clicked gets `mouse_filter = MOUSE_FILTER_IGNORE`. The default `MOUSE_FILTER_STOP` (0) takes the mouse events it is clicked on and marks them handled, so they never reach `_unhandled_input` (`classes/class_control.rst`). In `MOUSE_MODE_CAPTURED` every mouse event sits at the window's centre (`tutorials/inputs/mouse_and_input_coordinates.rst`). A Control with `STOP` under the crosshair would therefore take clicks before `PlayerController` sees them (inferred from those two facts). Defaults differ by class: `Label` is `IGNORE` (2), `TextureRect` is `PASS` (1), and `Control`, `ColorRect`, `Panel` and `Button` are `STOP` (0).
- Buttons in in-game menus get `focus_mode = FOCUS_NONE`, as the buy menu's do. A focused Button fires on `ui_accept`, which includes Space (the jump key) (`tutorials/ui/gui_navigation.rst`, inferred for Space from the default input map).
- Design the HUD at the 1920x1080 base size. Stretch mode `canvas_items` scales all 2D, including font sizes and `_draw()` line widths, to the window: x2 at 4K. Do not compute pixel sizes from `get_viewport().size` by hand (`tutorials/rendering/multiple_resolutions.rst`).
- Put HUD layers on a `CanvasLayer` with `layer >= 1`. Never give two CanvasLayers the same `layer`: "Which CanvasLayer is drawn in front is non-deterministic" (`classes/class_canvaslayer.rst`).
- Set font sizes on the node (theme override `font_size`) or in a `LabelSettings`, never on the font. Since 4.0, fonts carry no size (`tutorials/ui/gui_using_fonts.rst`).
- For long or often-appended text (console, kill feed, chat), use `RichTextLabel.append_text()` or `push_*()`/`pop()`, not `text +=`. Escape player-typed text with `text.replace("[", "[lb]")` before appending (`tutorials/ui/bbcode_in_richtextlabel.rst`).
- Test by headless checks what can be tested headless: text, visibility, layout rectangles. Cloud agents cannot see the result. A change to what the HUD looks like needs a screenshot or play on Sid's machine (Local), and the pull request should say whether it had one.
- 2D is blended in linear light: `project.godot` sets `rendering/viewport/hdr_2d`. CS2's Panorama composites its HUD in linear light (measured on `reference/cs2 _screenshots/In_game_ui.webp`: the health's gold adds the same linear amount over the dark sleeve and the bright pavement, and the alert's rgba(0,0,0,0.5) darkens by half in linear), so colours and alphas from CS2's CSS go in as written and look as they do there. It costs 0.02 ms of GPU at 4K and leaves the 3D picture unchanged (measured 2026-09-25). Anything that is not CS2's HUD and was tuned in sRGB converts its alpha (`FlashOverlay.linear_share`).
- A script that saves the root viewport's picture (`get_texture().get_image()`) gets linear values under `hdr_2d` and must convert them: in float, per pixel, `Color.linear_to_srgb()`. `Image.linear_to_srgb()` works only on 8-bit images and crushes the darks. Render-calibration shots taken before 2026-09-25 were sRGB.
- The HUD's fonts are multichannel signed distance fields with the printable ASCII drawn at import (`scripts/write_import_settings.gd` for the extracted Stratum2, the committed `.import` files for the bundled Rajdhani): one set of glyphs for every size and window, so a number's first appearance rasterizes nothing.
- A HUD panel that blurs the world behind it, as Panorama's `world-blur` does, draws its shape in `HudElement._draw_blur()`. The element copies only that part of the screen first (a `BackBufferCopy` in rect mode) and reads it from Godot's blurred screen mipmaps (`src/ui/hud_blur.gdshader`); the automatic whole-screen copy cost 0.5 ms at 4K, the element's own 0.03 ms each. Godot 4.7 took a copy's rect, under a Control, as the viewport's pixels whatever the transforms above it (black at 4K otherwise), so `HudElement._fit_copy` gives it pixels and a transform that undoes its parent's.

## Resolution and scaling (`tutorials/rendering/multiple_resolutions.rst`, `classes/class_projectsettings.rst`)

- The base size (`display/window/size/viewport_width/height`, here 1920x1080) is a design size. Godot never changes the monitor's resolution.
- `display/window/stretch/mode` (default `"disabled"`) takes `"canvas_items"` or `"viewport"`. With `"canvas_items"` the base size is stretched over the window and 2D is rendered at the target resolution. 3D is unaffected: it renders at the window size. Here it is `canvas_items`.
- `display/window/stretch/aspect` defaults to `"keep"` and letterboxes a window whose aspect differs from 16:9. `"expand"` is the default only for projects **created** in 4.7. It keeps the aspect ratio but grows the viewport in the long direction. The docs recommend it for desktop games, with Controls anchored to their corners. This project leaves it unset, so it is `keep`. On a 21:9 or 16:10 monitor the game gets black bars.
- The content scale factor (`Window.content_scale_factor`, set at runtime via `get_tree().root`) multiplies 2D on top of the stretch. It is the player-facing "UI scale" option. `display/window/stretch/scale_mode` `"integer"` is for pixel art. Leave it `fractional`.
- `gui/theme/default_theme_scale` (1.0) is read only at startup. At runtime use `ThemeDB.fallback_base_scale` or, better, the content scale factor.
- The docs recommend `WINDOW_MODE_EXCLUSIVE_FULLSCREEN` over `WINDOW_MODE_FULLSCREEN` for games. It "allows Windows to reduce jitter and input lag". Plain `FULLSCREEN` leaves a 1-pixel line so Windows does not treat it as exclusive. Either mode resizes the window to the monitor without changing the video mode (`classes/class_displayserver.rst`).
  - `project.godot` starts the game in `WINDOW_MODE_EXCLUSIVE_FULLSCREEN` (`display/window/size/mode=4`), as the docs recommend for games; `display/window/size/mode` also decides the editor's game embedding, which works only windowed, so Play runs the game in its own fullscreen window. `PlayerView` caps the frame rate just under the screen's refresh (`frame_cap`) unless Max FPS is set. Godot's `--fullscreen` command-line flag asks for `WINDOW_MODE_FULLSCREEN` even so (measured in 4.7.2: the window came up plain fullscreen with it, exclusive without), so the drawing profilers are run without it.
- A 3D resolution scale apart from the UI is `Viewport.scaling_3d_scale` (resolution scaling). See the rendering page, not here.
- The stretch also scales input: `InputEventMouseMotion.relative` is scaled by the content scale factor. See `input.md`.

## Anchors, offsets and position (`tutorials/ui/size_and_anchors.rst`, `classes/class_control.rst`)

- Each side has an anchor (0 to 1 of the parent rect: the parent Control's rect, or the viewport's when the parent is not a Control) and an offset in pixels from that anchor. For a control anchored bottom-right, positive offsets go right and down, so offsets into the screen are negative.
- `set_anchors_preset(preset, keep_offsets=false)` sets anchors only. `set_offsets_preset(preset, resize_mode=0, margin=0)` sets offsets. `set_anchors_and_offsets_preset(preset, resize_mode=0, margin=0)` does both. Use the last for `PRESET_FULL_RECT` overlays.
- `position` is the rect's top-left relative to the parent. Setting it changes offsets, keeping anchors. `set_position(pos, keep_offsets=true)` moves the anchors instead. `size` is also derived from the offsets.
- To centre a control, set all four anchors to 0.5 and offsets to plus or minus half its size. Or use `grow_horizontal`/`grow_vertical = GROW_DIRECTION_BOTH` with `PRESET_CENTER`, as the buy menu panel does, so it grows both ways from the centre when its minimum size changes.
- Anchoring places the **top-left** of the rect, so a text glyph "centred" by anchors sits half its box off-centre. This is the bug `src/ui/crosshair.gd` records. Draw centred things in `_draw()` from `size * 0.5` of a full-rect Control.
- `custom_minimum_size` is a floor. The effective minimum is the larger of it and the content's minimum (`get_combined_minimum_size()`). `custom_maximum_size` beats it. `_get_minimum_size()` is only called on plain Control, Container and Panel scripts, not on Label or Button subclasses.
- Wrapping: a `Label` with `autowrap_mode` set needs a maximum width (`custom_maximum_size`, or a parent with `propagate_maximum_size`) to wrap. The same goes for `RichTextLabel` with `fit_content`.

## Containers (`tutorials/ui/gui_containers.rst`)

- A Container positions its children. Their own position and size are "ignored or invalidated the next time their parent is resized". Use `size_flags_horizontal/vertical` (`SIZE_FILL` on by default, `SIZE_EXPAND`, `SIZE_SHRINK_BEGIN/CENTER/END`) and `size_flags_stretch_ratio`.
- The types: `HBoxContainer`/`VBoxContainer` (spacing is theme constant `separation`), `GridContainer` (`columns`), `MarginContainer` (margins are theme constants `margin_left`, `margin_top` and so on, set with `add_theme_constant_override`), `PanelContainer` (draws its `panel` StyleBox and fits children inside its margins), `CenterContainer`, `ScrollContainer` (one child, usually a VBox), `TabContainer`, `HSplit/VSplitContainer`, `AspectRatioContainer`, `HFlow/VFlowContainer`, `FoldableContainer` (new), and `SubViewportContainer`.
- A custom container overrides `_notification(what)` for `NOTIFICATION_SORT_CHILDREN` and calls `fit_child_in_rect(child, rect)`. Call `queue_sort()` when a setting changes.
- Scoreboard (TAB) and buy-menu grids fit `GridContainer` or `VBox` of `HBox`. The buy menu draws its grid itself instead (a `HudElement`, below), to CS2's own sizes.

## Drawing your own (`tutorials/ui/custom_gui_controls.rst`, `classes/class_canvasitem.rst`)

- Override `_draw()` and call `queue_redraw()` when the data changes. `queue_redraw` draws at most once per frame, "during idle time, if visible". Draw commands are cached until the next redraw, so a static crosshair costs nothing per frame. Only call `queue_redraw()` when a value changed (the crosshair's setters do this).
- `draw_rect(rect, color, filled=true, width=-1.0, antialiased=false)`. A negative `width` draws thin two-point lines that do not scale with the CanvasItem transform. Pass a positive width for lines that should scale. `draw_arc(center, radius, start_angle, end_angle, point_count, color, width=-1.0, antialiased=false)`, and `draw_circle` also exists.
- Notifications that matter: `NOTIFICATION_RESIZED` (re-layout or redraw), `NOTIFICATION_THEME_CHANGED`, `NOTIFICATION_VISIBILITY_CHANGED`, `NOTIFICATION_MOUSE_ENTER/EXIT`, `NOTIFICATION_FOCUS_ENTER/EXIT`.
- `CanvasItem.top_level = true` detaches the transform from the parent and draws on top of non-top-level siblings.

## Input on Controls (`classes/class_control.rst`, `tutorials/inputs/inputevent.rst`)

- `_gui_input(event)` gets mouse events inside the rect (position is local to the Control) and key or joypad events when the Control has focus. `accept_event()` stops the event, including from `_unhandled_input`.
- `mouse_filter`: `STOP` (0) receives events and marks them handled, blocking controls behind. `PASS` (1) receives them, and unhandled ones bubble to the parent Control, then to `_shortcut_input`. `IGNORE` (2) receives nothing and blocks nothing. `mouse_behavior_recursive` and `focus_behavior_recursive` (new in 4.x) turn off mouse or focus for a whole subtree. Use `get_mouse_filter_with_override()` and `get_focus_mode_with_override()` to see the effective value.
- `mouse_force_pass_scroll_events` defaults to true: wheel events pass to the parent even through `STOP`. Turn it off on a menu's root if the wheel must not reach `_unhandled_input`, since the wheel is jump and weapon selection here.
- Focus: `focus_mode` is `FOCUS_NONE`, `FOCUS_CLICK` or `FOCUS_ALL`. Label defaults to none, Button to all. Menus that use the keyboard must `grab_focus.call_deferred()` on a first control, or keys do nothing (`tutorials/ui/gui_navigation.rst`). A node loses focus when hidden. `Viewport.gui_release_focus()` drops focus.

## Theme, styles and fonts (`tutorials/ui/gui_skinning.rst`, `tutorials/ui/gui_using_fonts.rst`, `classes/class_theme.rst`)

- A theme item is looked up in this order: local override (`add_theme_*_override`), then the `theme` of the Control and each Control ancestor (the chain stops at a non-Control node such as a `CanvasLayer`), then `gui/theme/custom` (project theme), then the engine default. Item types are Color, Constant, Font, Font size, Icon and StyleBox, each keyed by name and theme type (class name, then parent class names).
- Theme items are **not** properties: `get()` and `set()` do not reach them. Use `get_theme_color(name, type)` and `add_theme_color_override(name, color)`, and so on.
- Because a `CanvasLayer` breaks the chain, a HUD theme goes on the HUD's root Control under the layer, or in the project theme (inferred from the lookup rule above).
- `Theme.set_type_variation(variation, base_type)` plus `Control.theme_type_variation` gives named presets, such as a "HudBig" `Label`.
- `LabelSettings` (a Resource: font, size, colour, outline, shadow) set on `Label.label_settings` takes priority over the theme and can be shared by many labels. It is a cleaner fit for the HUD than repeated overrides.
- Outlines: theme constant `outline_size` plus colour `font_outline_color`, on most Controls. Keep `outline_size` at or below half the font size. Shadows (`font_shadow_color`, `shadow_offset_x/y`) are hard-edged and exist only on Label and RichTextLabel.
- The default font is Open Sans SemiBold. Font sizes are in pixels, not points. Dynamic fonts (TTF, OTF, WOFF, WOFF2) rasterize glyphs on the CPU per size on first use, which can hitch the first time a big size appears. Pre-render glyphs in the font's import settings. MSDF renders any size from one atlas: good for large HUD numbers, less sharp at small sizes, no LCD subpixel.
- `SystemFont` loads an installed OS font by name or alias (`sans-serif`, `monospace`, and so on) at runtime. It is not in the PCK, and it falls back to the default font on unsupported platforms. CS2's own HUD font would come from the extracted assets as a `FontFile` import. It is Valve's content, so it stays in `assets/`.
- `StyleBoxFlat`: `bg_color`, `border_width_*` (`set_border_width_all`), `border_color`, `corner_radius_*` (`set_corner_radius_all`), `corner_detail = 8`, `anti_aliasing = true`, `expand_margin_*`, `shadow_color`, `shadow_size` and `shadow_offset`, `draw_center`, `skew`. For chamfered corners (`corner_detail = 1`) set `anti_aliasing = false`.

## Text nodes (`classes/class_label.rst`, `classes/class_richtextlabel.rst`, `tutorials/ui/bbcode_in_richtextlabel.rst`)

- `Label` is plain text: `text`, `horizontal_alignment`, `vertical_alignment`, `autowrap_mode`, `clip_text`, `text_overrun_behavior`, `visible_ratio`, `label_settings` and `uppercase`. It is "not designed to display huge amounts of text".
- `RichTextLabel` needs `bbcode_enabled = true` (setter `set_use_bbcode`) for tags. `append_text(bbcode)` parses only the new text, and a tag opened in one call cannot be closed in a later one. `add_text(text)` adds raw text. `push_color()`, `push_bold()` and the rest, with `pop()`, skip parsing. `clear()` empties the tag stack. Setting `text = ""` clears too. `scroll_following` auto-scrolls. `fit_content` sizes it to its text. `threaded = true` moves text processing to a thread, which avoids the stall but does not speed it up.
- `[url]` does nothing until you connect `meta_clicked`. Never enable it for player text.
- `TextureRect` for icons (default `mouse_filter` `PASS`). `ColorRect` for flat fills (default `STOP`; the flash overlay sets `IGNORE`).

## CanvasLayer (`classes/class_canvaslayer.rst`)

- `layer: int = 1`. The default 2D canvas is 0, and higher layers draw on top. Embedded Windows sit on layer 1024.
- `visible` hides the layer's CanvasItems, but "isn't propagated to underlying layers", so a child CanvasLayer stays visible.
- `follow_viewport_enabled = false` keeps the layer fixed on screen. Leave it that way for a HUD.
- A CanvasLayer draws on one Viewport only.

## Class notes

**Control** (`classes/class_control.rst`)
- `anchor_left/top/right/bottom` (floats, default 0), `offset_*`, `set_anchor(side, anchor, keep_offset=false, push_opposite_anchor=true)`, `set_anchors_preset(preset, keep_offsets=false)`, `set_anchors_and_offsets_preset(preset, resize_mode=0, margin=0)`, `grow_horizontal/vertical` (default `GROW_DIRECTION_END` = 1), `position`, `size`, `set_position(pos, keep_offsets=false)`, `custom_minimum_size`, `mouse_filter = STOP`, `focus_mode`, `grab_focus(hide_focus=false)`, `release_focus()`, `accept_event()`, `_gui_input(event)`, `_get_minimum_size()`, `theme`, `theme_type_variation`, `add_theme_{color,constant,font,font_size,stylebox,icon}_override(name, value)`, `get_theme_*`.
- Gotcha: theme items are not Object properties.

**CanvasItem** (`classes/class_canvasitem.rst`)
- `visible`, `modulate`, `self_modulate`, `z_index`, `top_level`, `texture_filter`, `_draw()`, `queue_redraw()`, `draw_rect`, `draw_line`, `draw_arc`, `draw_circle`, `draw_texture_rect`, `draw_string(font, pos, text, ...)`.

**CanvasLayer**: see above.

**Label**, **RichTextLabel**: see above. Label theme items: `font`, `font_size`, `font_color`, `font_outline_color`, `outline_size`, `font_shadow_color`, `shadow_offset_x/y`, `line_spacing`.

**TextureRect**, **ColorRect**: `texture`, `expand_mode` and `stretch_mode` for TextureRect; `color` for ColorRect. Watch the mouse_filter defaults above.

**Container** family: see above. `Container.queue_sort()`, `fit_child_in_rect()`.

**Theme** (`classes/class_theme.rst`)
- `default_font`, `default_font_size = -1` (unset), `default_base_scale = 0.0` (use global), `set_color(name, theme_type, color)`, `set_constant`, `set_font`, `set_font_size`, `set_stylebox(name, theme_type, stylebox)`, `set_icon`, `set_type_variation(theme_type, base_type)`.

**StyleBoxFlat** (`classes/class_styleboxflat.rst`): see above.

**Font / FontFile / SystemFont / FontVariation** (`classes/class_font.rst`, `class_fontfile.rst`, `class_systemfont.rst`, `class_fontvariation.rst`)
- `FontFile.load_dynamic_font(path)` is for runtime loading from `user://` only. Imported fonts are loaded with `load()`.
- `SystemFont.font_names: PackedStringArray` (first found wins), `font_weight`, `font_italic`, `antialiasing`, `hinting`, `subpixel_positioning`, `multichannel_signed_distance_field`, `generate_mipmaps`.
- `FontVariation` gives OpenType variations and simulated bold or slant, with a font as `base_font`.

## Where the code already does this

- `src/ui/hud_element.gd`: the base of every HUD piece and the buy menu. A `Control` with no Labels or containers that draws itself in `_draw()`; its owner hands it the frame's values as one array (`show_state`), and only a change redraws it. Something that moves on its own (the money's digits rolling, the health's red copy falling, an alert opening) calls `animate()`, which runs `_process` until `_advance()` returns false and then turns it off. `mouse_filter` is `IGNORE` from `_init`. An element with `additive` set draws with Panorama's additive blend (a shared `CanvasItemMaterial`, `BLEND_MODE_ADD`); one with `_draw_under()` gets a surface drawn behind it with the ordinary blend (a panel's dark), and one with `_draw_blur()` a blurred-world surface behind that. New HUD pieces (item 15) should extend it.
- `src/ui/hud_style.gd`: CS2's colours (t-color and ct-color for the HUD's wash, color-T and color-CT for the team counter, the teammate colours of `cl_teammate_color_1` to 5), its fonts by CS2's family names (`face(&"bold_tf")` is "Stratum2 Bold TF", the HUD's numbers; `&"mono_bold"` the money's; from `assets/hud/fonts/`, else the bundled Rajdhani under the OFL in `src/ui/fonts/`) and its icons (`assets/hud/panorama/images/...`, null when not extracted, and the element draws a stand-in). `draw_text` draws a string by its left, centre or right on a baseline, with an optional text-shadow; `baseline_centred` puts it where a Panorama label with `vertical-align: center` does. Every element writes text this way instead of with a `Label`.
- The elements' sizes and places are CS2's own, from the Panorama layouts and styles decompiled out of the game (`panorama/layout/hud/*.vxml_c`, `panorama/styles/hud/*.vcss_c`), and where CS2's screenshot disagrees with the CSS (the health cluster sits 15 px off the bottom, not 18; the money's digits are 19.2 px apart, not 18) the screenshot wins and the code says so.
- `src/ui/game_hud.gd`: a `CanvasLayer` (default layer 1) holding the elements (`HealthAmmoCenter`, `MoneyPanel`, `TeamCounter`, three `HudAlert`s: the alert, a refusal's hint and the line while dead) and the crosshair, scope and damage arcs. Its `_process` reads the player, economy and match and hands each element its values. The one `Label` left is the F3 position readout.
- `src/ui/crosshair.gd`: a full-rect Control with `MOUSE_FILTER_IGNORE`, drawn in `_draw()` from the centre, redrawn on value change and on `size_changed`.
- `src/ui/scope_overlay.gd`, `src/ui/damage_indicator.gd`, `src/grenades/flash_overlay.gd` (`ColorRect`): full-rect, `IGNORE`, drawn per frame.
- `src/ui/movement_hud.gd`: its own `CanvasLayer` with one Label.
- `src/economy/buy_menu.gd`: a `HudElement` covering the screen, the whole menu drawn in one `_draw()` and hit-tested by hand in `_gui_input` (no `Button` nodes), laid out as CS2's `buymenu.xml` and `buymenu.css` lay it out, its columns in CS2's order (Equipment first; `COLUMN_ORDER` maps them onto `Loadout`'s slot order) and each as wide as CS2's for its kind. Behind it the game, lightly blurred under a dark grey, as Sid's screenshot of CS2's measures it (CS2's own `.buymenu` is 95 % black, with the game drawn back over it by the agent's panel). It sets `mouse_filter` to `STOP` only while open, and input still goes through `_input` for B, Escape and the number keys.
- `src/economy/buy_menu_agent.gd`: your agent beside the menu, a `SubViewport` with a world of its own (`own_world_3d`, `transparent_bg`) that the menu draws as a texture. Its camera, the agent's place and its light are the numbers of CS2's `ui/buy_menu` map; the agent is a `PlayerModel` body posed by CS2's buy-menu clips through an `AnimationTree` of its own (the pose, the breath added over it), the item pinned to its hand with `attach_weapon`. It renders only while the menu is open (`render_target_update_mode`), and only the strip right of the middle where the agent stands: the camera is a `PROJECTION_FRUSTUM` one whose `size` and `frustum_offset` cut the map camera's full-screen view down to that strip, so the agent lands where CS2 puts it. MSAA softens its outline against the game (FXAA and SMAA leave the alpha hard); its cost is in `reference/performance.md`.

Looks at odds with the docs (not verified in play):
- `src/ui/movement_hud.gd` is also a `CanvasLayer` on the default layer 1, like `GameHud`. Two layers with the same index draw in a non-deterministic order (`classes/class_canvaslayer.rst`). This matters only if they overlap.
- `project.godot` sets `canvas_items` without `window/stretch/aspect`, so it is `"keep"`. Non-16:9 monitors get black bars, where the docs recommend `expand` with corner anchors for desktop games.

## Not covered here

- Editor-side theme editing (`tutorials/ui/gui_using_theme_editor.rst`) and type variations in the editor (`tutorials/ui/gui_theme_type_variations.rst`).
- Control gallery and application-style UIs (`tutorials/ui/control_node_gallery.rst`, `tutorials/ui/creating_applications.rst`).
- Custom BBCode effects (`RichTextEffect`) and the full tag list: `tutorials/ui/bbcode_in_richtextlabel.rst` from "Reference" on.
- Localization and text server features (`tutorials/i18n/`).
- 2D rendering internals and `RenderingServer` canvas items (`tutorials/performance/using_servers.rst`). Canvas pipeline compilation hitches are in `tutorials/performance/pipeline_compilations.rst` and the rendering page.
- Minimap or radar in a `SubViewport`: `classes/class_subviewport.rst` and the rendering page.
