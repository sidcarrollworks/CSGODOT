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
The [additional manifest](in-game-menu-2026-10-04.json) records the six settings
and vote files read for this pass. Paths below are relative to `panorama/`.

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
Full background blur, backbuffer capture and native-menu visual parity are not
claimed. The shared theme, layout, input scope and dialog handle presentation
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

## Validation

The graphical renderer passed 154 checks across `run_game_menu_checks.gd` (56),
`run_menu_input_checks.gd` (54) and `run_ui_foundation_checks.gd` (44). These cover
menu/settings navigation, native field entry, confirmation cancellation, cursor
and focus restoration, draft Apply/Cancel and persistence, blocked local commands
with held-control release, bot handoff, continued world/bomb ticks, HUD visibility
and preserved buy-menu movement.

Reviewed menu and settings captures at 1920x1080 and 3840x2160 under
`.godot/menu-audit/`; the Dust2 capture uses the supplied T-spawn position
`(-1163.7, 77.8, -299.7)`, yaw 270.2, pitch 11.8. An additional graphical
smoke run on extracted Dust2 clicked the actual Settings, Apply, Quit, Cancel
and Resume controls and checked active values and isolated-file persistence.
The existing simulation suite passed 283 checks, including 7,178 movement
steps compared between native/script implementations and ten hitbox rays.
The full `scripts/run_tests.sh` run passed 8,986 checks across 87 files with
the extracted assets and native addons available. Render-only cases retained
their normal headless skips; the graphical UI checks above ran separately.
