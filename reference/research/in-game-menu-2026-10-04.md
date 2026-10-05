# CS2 Escape menu and our first in-match settings screen

This follows the [Panorama foundation audit](panorama-ui-2026-10-04.md).
The purpose is a useful Escape menu built on the shared UI system, with actual
settings and predictable gameplay input, rather than unsupported menu actions.

## Evidence and reproduction

The installed CS2 used for this source audit is ClientVersion/ServerVersion
2000924, PatchVersion 1.41.8.8, SourceRevision 11076591, built October 2, 2026
at 14:45:21. Source 2 Viewer CLI 20.0.0.0 reconstructed the shipped Panorama
resources from `game/csgo/pak01_dir.vpk`. Its directory SHA-256 is
`a391c450b7b93389aa2b0a1ba1a0a70e2da6eedf9570e90a3b1bdfe062aad1eb`.

The ignored extraction is `.godot/panorama-audit/current` in the reconciliation
checkout. Reproduce with the command in the foundation audit. No Valve source
or assets are redistributed by this change. The
[existing manifest](panorama-ui-2026-10-04.json) records `layout/mainmenu.xml`,
`scripts/mainmenu.js`, `styles/mainmenu.css` and `styles/csgostyles.css`.
The [additional manifest](in-game-menu-2026-10-04.json) records the settings
and vote files read for this pass, including the two settings styles read
for the October 5 screenshot follow-up. Paths below are relative to `panorama/`.

## Confirmed shipped structure and behavior

`layout/mainmenu.xml` uses one native `CSGOMainMenu` shell for the main menu
and Escape menu. `scripts/mainmenu.js::_OnShowPauseMenu()` adds
`MainMenuRootPanel--PauseMenuMode`, adjusts action eligibility and returns
navigation Home; `_OnHidePauseMenu()` removes the mode and clears mission UI.
This is not evidence for a separate centered paused-game dialog.

The in-match world is provided by `CSGOBackbufferImagePanel#PauseMenuBackground`.
The shared top navigation includes Settings. `#JsMainMenuNavBar` is a horizontal
in-match action bar with Resume, Switch Teams, Vote, Report Server and
Exit/Disconnect actions. `CSGOScoreboardContainer#Scoreboard` sits below it.
The source uses localization tokens; these action names describe their roles.
Switch Teams is hidden for queued matchmaking and GOTV, Vote for GOTV, and
Report Server except community servers. The in-match Exit button dispatches
`CSGOMainMenuDisconnect`, while the main-menu Quit button opens a confirmation
before issuing `quit`. Their native execution and disconnect prompts are not
implemented in the visible script.

`styles/mainmenu.css::.pausemenu-navbar-container` centers the action bar at
96 logical pixels from the top. `.pausemenu-navbar` flows right; its buttons
are 64 pixels tall with 18 pixels of horizontal padding, 32-pixel icons,
12-pixel icon/text separation and 24-pixel labels with 1-pixel tracking.
`.mainmenu-content--open` collapses the action bar, scoreboard and mission
panel while a content page is open. The shared blur regions, nearly transparent
`blurBackgroundColor` and low-opacity dot texture create a translucent surface.
State transitions generally take 0.15 to 0.25 seconds. These are source values,
not measurements of our rendered output.

The root cancel handler calls `MainMenu.OnEscapeKeyPressed()`: with a content
tab open, Escape returns Home; at Home it issues `gameui_hide`. Opening content
calls `SetFocus()`. Native popup, context-menu and tooltip managers are separate
children of the shell; opaque popups suppress the underlying input panel with
`HiddenByPopup`. Native focus arbitration and key propagation remain unknown.

`layout/settings/settings.xml` declares category navigation and one content
host. `scripts/settingsmenu.js::NavigateToTab()` creates and reuses category
panels, sets their active state and focuses Search's text entry. Hiding Settings
writes configuration through `host_writeconfig`. `settingsmenu_shared.js`
refreshes native controls and exposes explicit Apply/Discard operations for
video settings. This does not establish Apply/Cancel draft behavior for every
CS2 settings category: ordinary native sliders bind directly to convars.

`layout/settings/settings_kbmouse.xml` binds its mouse sensitivity slider to
`sensitivity`, with a displayed range of 0.1 to 8.0 and two-decimal precision.
`layout/settings/settings_audio.xml` exposes master music and eight competitive
cue sliders on a 0 to 1 range: menu, round start, round action, round end, MVP,
map objective, ten-second warning and death camera. The source also has music
profiles for other modes. Native audio-gain slider mapping is not recovered
here. Our existing [audio audit](audio-round.md) supplies the music-event and
default-value evidence already used by `AudioSettings`.

## Simulation and native unknowns

There is no match-simulation pause instruction in the visible Escape-menu
JavaScript. `OnHomeButtonPressed()` calls `vanityPanel.Pause()` for the background
vanity model, not the match world. `context_menus/context_menu_vote.js` reads
`FriendsListAPI.IsGamePaused()` and separately offers `PauseMatch`,
`UnpauseMatch` and timeout vote issues. Menu visibility and match pause are
therefore distinct source concepts. This does not recover native offline-server
scheduling, command capture, disconnect handling or the exact blur implementation.

## Implemented project subset and explicit policies

Our Escape menu offers **Resume**, **Settings** and **Quit to desktop** in a
source-informed horizontal action bar over a translucent world backdrop.
Quit uses the reusable confirmation dialog. It is a supported project action,
not a claim that CS2's in-match Disconnect button quits the application.
Native-menu visual parity and exact native blur kernels are not claimed.
The shared theme, layout, input scope and dialog handle presentation
and lifetime consistently with the foundation.

The match keeps running while this menu is open. That is our explicit policy,
not a recovered promise about every CS2 server mode. Local gameplay commands
are neutralized while the menu, settings or confirmation owns input. Held
controls must be released before they can act after Resume, so clicking a menu
button or holding movement cannot accidentally shoot or move on dismissal.
Buying retains its existing policy of allowing polled movement; the Escape
menu's gameplay block is separate from ordinary `UiInputScope` ownership.
`GameHud` keeps updating from the running match while hiding its layer beneath
blocking screens, so the clock and player cards do not show through menu
controls. It becomes visible again after dismissal.

Settings exposes persisted mouse sensitivity and the nine existing music values
in `AudioSettings`. Values edit a draft. **Apply** commits the draft and saves
it; **Cancel** or Escape discards it and returns to the in-match menu. This
explicit transaction is our authoring policy, not a wholesale clone of CS2's
native convar widgets. Music sliders continue to use the existing sound-event
volume path; bomb beeps are distinct from warning music.

Leave-to-main-menu navigation, votes, server reports, mid-match team changes,
video settings, full key rebinding, additional audio controls and other-mode
music profiles remain future work. No inactive placeholder buttons promise
those features in this menu.

## October 5 playtest follow-up

Sid supplied current CS2 main-menu, Play, settings, loading and team-select
screenshots, plus our SAS bot's opaque tan lens issue. The implemented subset
uses these as visual references without claiming the unbuilt menu pages.

`styles/settings/settings.css` defines 48px control rows and a 946px content
background. `settings_slider.css` uses a 25.5% slider, a 10px gap and an 80px
value field with a subtle border. Our native row/value/slider Theme variations
follow these proportions; the host hides pause navigation while settings are
open. `UiWorldBackdrop` reuses the HUD's explicit screen copy and shader,
with the content shell's 75% black tint. Mipmap level 5 is a visual fit for
our blur, rather than a decompiled CS2 kernel. It runs only on the open page.

The startup selector now appears after the map, collision and both local
player/presenter choices are prepared. Simulation stays at tick zero until
joining, and warmup begins then. The chosen controller, body, arms, HUD,
buy-menu agent and recipient-specific presenters retain their identity;
unused staged players/bots leave the roster. World grenade/C4 presenters are
shared. Explicit team/headless startup keeps its single-player preparation path.
An extracted Dust2 graphical run joined CT in 21,872 microseconds; this is
one local observation, not a timing guarantee or CI threshold.

The SAS lenses already use `csgo_character.vfx`, with no `F_EYEBALLS`.
The installed material resource
`characters/models/ctm_sas/materials/ctm_sas_lenses.vmat_c` contains uniform
`TextureMetalness=1` and `TextureRoughness=0.12549`. Its 4,368-byte compiled
resource has SHA-256
`fe69ff5789dcb00acbea3fda86dc7fcac5c991b9bdbe968eddec16e6ee6895f2`.
Reproduce the DATA dump with Source2Viewer-CLI:

```powershell
Source2Viewer-CLI -i <CS2>/game/csgo/pak01_dir.vpk `
  -f characters/models/ctm_sas/materials/ctm_sas_lenses.vmat_c -b DATA
```

The imported ORM instead has roughness 1 and metalness 0, producing diffuse
tan lenses under warm direct light. Runtime binding restores the authored
uniform inputs only for generated texture bindings, while retaining artist
texture channels, AO and cache. Missing, nonuniform or nonfinite values keep
the imported channels. A local Forward+ before/after render reproduced the failure and the restored dark glossy
reflection; a separate blue-environment render verifies that reflection
uses its environment. Character checks cover fallback channels and the actual
imported SAS surface. The same cached material is used in the map and menu.

The relative viewmodel jump dip is halved from scale 1 to 0.5 at Sid's request;
camera impulses, spring timing and simulation are unchanged. This is playtest
tuning, not an extracted CS2 motion value. See [jump camera](jump-camera.md).

## Validation

The graphical renderer passed 156 checks across `run_game_menu_checks.gd` (58),
`run_menu_input_checks.gd` (54) and `run_ui_foundation_checks.gd` (44). These cover
menu/settings navigation, native field entry, confirmation cancellation, cursor
and focus restoration, draft Apply/Cancel and persistence, blocked local commands
with held-control release, bot handoff, continued world/bomb ticks, HUD visibility
and preserved buy-menu movement. The current character suite also passed
46 Forward+ checks, including lens diffuse/reflection behavior and imported
SAS material binding. The startup suite passed 131 checks; the jump suite
passed 135.

Reviewed menu and settings captures at 1920x1080 and 3840x2160 under
`.godot/menu-audit/`; the Dust2 capture uses the supplied T-spawn position
`(-1163.7, 77.8, -299.7)`, yaw 270.2, pitch 11.8. An additional graphical
smoke run on extracted Dust2 clicked the actual Settings, Apply, Quit, Cancel
and Resume controls and checked active values and isolated-file persistence.
The existing simulation suite passed 283 checks, including 7,178 movement
steps compared between native/script implementations and ten hitbox rays.
The October 5 full `scripts/run_tests.sh` run completed 9,151 checks across
88 files with extracted assets and native addons available. All suites passed
except two model assertions that still expected the previous full-strength
jump dip. After correcting those expectations, all 313 local-asset model checks
passed in a focused rerun. The full run printed no script errors. Three
render-only cases retained their normal headless skips; graphical checks ran
separately as described above. The original October 4 implementation had passed
8,986 checks across 87 files.
