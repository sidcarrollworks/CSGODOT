# CS2 Panorama and our UI foundation

Sid asked for a system that makes new screens easy and consistent. This audit
reads the **installed CS2's shipped UI**, rather than designing from screenshots
alone. It covers composition, layout, style, data, input, lifetime, animation,
assets and rendering. It is a source-level architecture audit; it does not
claim to have recovered the closed Panorama engine or every screen's native
gameplay behavior.

## Evidence and reproduction

Installed `steam.inf`: ClientVersion 2000924, PatchVersion 1.41.8.8,
SourceRevision 11076591, VersionDate Oct 02 2026, VersionTime 14:45:21.
`pak01_dir.vpk` SHA-256:
`a391c450b7b93389aa2b0a1ba1a0a70e2da6eedf9570e90a3b1bdfe062aad1eb`.
Source 2 Viewer CLI 20.0.0.0 reconstructed **287 XML layouts, 240 CSS stylesheets
and 231 JavaScript files** from the installed archive on October 4.
The [source manifest](panorama-ui-2026-10-04.json) records hashes of the 16
reconstructed files closely read, without redistributing their contents.

The extracted material remains ignored under `.godot/panorama-audit/current`
in the reconciliation checkout. Nothing of Valve's source/assets is added to
the repository. Reproduce with Source2Viewer-CLI, substituting your install:

```powershell
Source2Viewer-CLI -i '<CS2>/game/csgo/pak01_dir.vpk' `
  -f 'panorama/layout/,panorama/styles/,panorama/scripts/' `
  -o '.godot/panorama-audit/current' --vpk_decompile
```

Files closely read, relative to `panorama/`:

- `layout/mainmenu.xml`, `layout/hud/hud.xml`, `layout/teamselectmenu.xml`,
  `layout/buymenu.xml`, `layout/scoreboard.xml` and their corresponding styles.
- `styles/csgostyles.css` (tokens, fonts, utility classes and interaction states).
- `scripts/mainmenu.js`, `scripts/teamselectmenu.js`,
  `scripts/hud/hudwinpanel.js`, `scripts/common/scheduler.js`,
  `scripts/popups/popup_accept_match.js` (events, state, binding and cleanup).

The [GameTracking-CS2 snapshot](https://github.com/SteamDatabase/GameTracking-CS2/tree/c01c73dbaf67bb2838ec0039034058ae961ad9de/game/csgo/pak01_dir/panorama)
is a remotely accessible copy of shipped source, useful for future work;
the installed extraction above is this audit's authority. The existing
[round HUD audit](round-hud-bots.md) remains the detailed component reference.
The Valve developer wiki returned 403 during this audit; no engine behavior
was inferred from inaccessible documentation.

## What the shipped system does

**Composition.** XML describes typed panel trees with IDs and classes. Layouts
include common and screen-specific styles/scripts, and can include other
layouts through `Frame`. Named snippets are reusable subtrees: the team picker
defines a teammate snippet; the win panel instantiates damage and plot snippets.
The HUD groups elements into named top/bottom/left/right regions. A component
has a place to live and an interface, rather than every screen drawing
everything itself.

**Layout.** Panels use horizontal/vertical alignment, margins, padding,
`flow-children`, percentages, `fit-children` and `fill-parent-flow`. Hidden
content can collapse out of the flow. Scrolling and clipping belong to the
panel tree. Text is measured as part of layout; its baseline and wrapping
should not be guessed from a neighboring icon's dimensions. The existing
1920x1080 design canvas is our retained convention, backed by the HUD audit;
this pass does not change the game's aspect-ratio policy.

**Style and states.** `csgostyles.css` supplies common constants, font classes,
team colors, button states and utility classes. Specific styles add selectors
for a component or ancestor state. Scripts call `SetHasClass`; styles handle
appearance. `:hover`, `:focus`, `:disabled`, selection and team states are
separate concerns. Shared resources must not be mutated by one selected row.

**Binding and behavior.** Scripts read game APIs, set dialog variables, use
localization tokens, update labels and register listeners. XML variables
include ordinary dialog values, formatted time, and native game-bound values
(the teammate name uses a player slot). Native classes such as
`CSGOHudTeamCounter` expose engine/game state; these are not generic HTML tags.
Our equivalent is a view reading snapshots and emitting actions that the
simulation executes through commands. Arbitrary translated/player text stays
plain text unless markup is deliberately needed.

**Input.** `hittest` and `hittestchildren` explicitly distinguish decorative
HUD regions from interactive panels. Buttons declare activation actions;
root screens declare cancellation. Main-menu code sets focus to content and
context menus. HUD XML has distinct popup, context-menu and tooltip managers.
This is evidence for explicit UI ownership, not evidence that our stack exactly
matches Panorama's native focus arbitration. Gameplay keys must not reach
another screen accidentally; pre-game navigation and in-game movement while
buying are different policies.

**Lifetime.** Team/menu scripts unregister listeners when stopping. The common
scheduler groups jobs, cancels scheduled handles and clears a handle when a
job executes. Views and their delayed work have an owner. A screen disappearing
through scene teardown must clean up as reliably as clicking Close.

**Animation.** CSS transitions animate opacity/transforms/brightness;
keyframes animate longer sequences. Team selection has a radial timer clip.
State changes trigger those effects, rather than gameplay time being advanced
by the visual animation. Our gameplay clocks remain SimClock-based; the
pre-game chooser's countdown and visual tweens remain UI-side. Use node-bound
Tweens for short transitions and AnimationPlayer for authored sequences.

**Rendering and assets.** HUD XML declares blur targets and named blur regions;
styles request blur, gradients, additive blending, masks, shadows and clipping.
The main menu also has backbuffer, particle and 3D scene panels. These effects
are specialized renderer features, not free browser CSS. Our existing linear
HDR 2D, MSDF fonts, HudStyle icon cache, additive materials, bounded screen
copies and BuyMenuAgent SubViewport already implement useful equivalents.
The exact blur filter/masks and native widgets still need individual parity
work where a playtest finds a difference.

## Mapping to the implementation

| Panorama concern | Godot implementation |
|---|---|
| XML tree, included Frame, snippet | `.tscn` trees and instantiated PackedScenes |
| Common constants/font classes | `HudStyle` assets/colors plus `UiStyle.menu()` Theme/type variations |
| Flow, content sizing, padding | VBox/HBox/Center/Margin/PanelContainer and minimum sizes |
| Region alignment | Control anchors/offsets in the logical canvas |
| Hover/disabled/selected | Native Button state, bound component state, local style overrides |
| Dialog variables/localized labels | Plain Label text and component `bind()`; `tr()`/translations when supplied |
| Game API listeners and actions | Simulation reads, owned signals, GameSystems commands |
| Popup ownership/hit tests | `UiScreen`, `UiInputScope`, decorative IGNORE and interactive STOP |
| Transitions and keyed sequences | Node-bound Tween / AnimationPlayer |
| Dynamic HUD state | `HudElement.show_state`, redraw only on changes |
| Additive/blur/backbuffer/3D | Existing HudStyle materials, bounded copies and SubViewport |

This uses Godot's layout/input/text machinery. There is no XML/CSS interpreter
and no embedded web renderer. A complete Panorama replacement would add large
maintenance and performance costs without helping the next menu.

## Improvements delivered

- `UiStyle` caches one native menu Theme, using the same fonts/team colors as
  the HUD, named typography and shared button/card/surface styles.
- `UiScreen` supplies a screen shell, a unique canvas layer, input ownership,
  teardown cleanup and a brief node-bound reveal tween. Unused modal keys and
  scroll events do not reach unhandled gameplay callbacks. Closing the previous screen releases
  input before its result opens the next screen.
- `UiInputScope` handles nested owners and out-of-order closure, restores the
  initial cursor when the last owner exits, and restores surviving focus when
  appropriate. It keeps no per-frame callback. It is a single-window cursor
  policy; multi-window focus arbitration is future work.
- `UiChoiceCard` is a reusable scene with native pointer handling, shared
  selected/disabled styles and flow-sized text. Long descriptions grow the
  card; they cannot overlap the next row. Unchanged bound state does no style
  duplication or text assignment.
- Mode selection now instantiates those cards in a scene layout. Its keyboard,
  saved choice and chosen signal stay the same. Practice's description now
  correctly says unlimited money/grenade buys.
- Team selection uses the common shell; buying uses the common cursor scope
  and releases it even on unexpected tree exit. Their accepted visuals remain
  in their current drawing code. Buying still permits polled movement.
  The scoreboard gates its earlier input-phase Tab presses on that ownership,
  while accepting release so an intervening popup cannot latch it open.
  Routed event ownership does not stop global `Input` polling or pause the
  simulation; future in-match pause/settings screens need an explicit command
  policy, separate from the buy menu's intentional movement.
- `UiDialog` and the component gallery provide a working popup and a preview
  scene for future screens. `scripts/preview_ui.gd` renders them at an explicit
  resolution, correctly converting linear HDR captures to sRGB.

The HUD retains its cached commands and current visual effects. Cached draw
commands save CPU rebuild work; the GPU still composites them every frame and
blur still incurs copy/filter cost. Corrected the old comment implying zero
total draw cost. The menu Theme is initialized outside simulation ticks.

## Validation and remaining work

44 focused checks cover shared-resource isolation, unchanged bindings, long
text and row growth, native clicks through decorations, disabled activation,
production picker selection, key/scroll blocking, nested layering, cursor/focus
restoration, teardown, native text entry, screen handoff, configuration before
mounting and scoreboard ownership. The graphical run passed all 44, including
actual cursor capture. Reviewed rendered mode/gallery views at 1920x1080 and
the popup over the gallery at 3840x2160 with extracted fonts. The final full
`scripts/run_tests.sh` run passed **8,876 checks across 85 files**, including all
44 UI checks, with extracted assets, Box3D and the current native movement
library. The runner reports drawing-only headless skips and existing known-open
drop checks separately; no check or script failed.

Next screens can use this foundation; see [the authoring guide](../ui.md).
Roadmap 26 still includes real main/pause/host/join/settings screens. Full
localization catalogs, controller navigation, a tooltip/context-menu manager,
UI scale/safe-area options and further native-widget parity remain open. The
foundation does not mark those features complete or change world exposure,
map rendering, movement, combat or the netcode plan.
