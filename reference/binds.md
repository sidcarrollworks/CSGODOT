# Binds

The plan for roadmap item 12a. Sid, 2026-09-24: "We need to add a keybind
system to the roadmap. Ideally the same keys are used everywhere even in
testing."

Written off `main` at `b354f09` (after #55). Every key below was read from
`project.godot`'s input map and the scripts that read keys themselves; none
of it was played.

## CS2's default binds

From `game/csgo/cfg/user_keys_default.vcfg` in SteamDatabase's
GameTracking-CS2 (master, read 2026-09-24). The file beside it,
`game/core/cfg/user_keys_default.vcfg`, is the engine's tool binds
(wireframe, physics gun), not the game's. The settings page in CS2 may
differ from the file; Sid can check with `key_listboundkeys` in CS2's
console on a fresh config (Local, below).

| Key | Command | What it does |
|---|---|---|
| W, S | `+forward`, `+back` | move |
| A, D | `+left`, `+right` | strafe (CS2's names; CS:GO's were `+moveleft`, `+moveright`) |
| SPACE | `+jump` | |
| CTRL | `+duck` | |
| SHIFT | `+sprint` | walk (CS2 calls it sprint) |
| MOUSE1, MOUSE2 | `+attack`, `+attack2` | |
| MOUSE3 | `player_ping` | |
| MOUSE4 | `+voicerecord` | |
| MWHEELUP, MWHEELDOWN | `invprev`, `invnext` | |
| R | `+reload` | |
| E | `+use` | plant, defuse, swap a gun on the ground |
| F | `+lookatweapon` | inspect |
| G | `drop` | |
| Q | `lastinv` | the last weapon held |
| 1 to 9, 0 | `slot1` to `slot9`, `slot10` | 4 cycles grenades, 5 the C4, 6 to 0 each grenade |
| X | `slot12` | |
| B | `buymenu` | |
| `,` `.` | `buyammo1`, `buyammo2` | |
| DEL | `sellbackall` | |
| F3, F4 | `autobuy`, `rebuy` | |
| TAB | `+showscores` | |
| M | `teammenu` | |
| I | `show_loadout_toggle` | |
| H | `switchhands` | |
| C, V, Z | `+radialradio`, `+radialradio2`, `radio` | |
| T | `+spray_menu` | graffiti |
| Y, U | `messagemode`, `messagemode2` | chat, team chat |
| ESCAPE | `cancelselect` | closes a menu, else the pause menu |
| `` ` `` | `toggleconsole` | |
| F5 | `jpeg` | screenshot |
| F6, F7 | `save quick`, `load quick` | |
| F10 | `cs_quit_prompt` | |

**Left unbound by CS2:** J, K, L, N, O, P; F1, F2, F8, F9, F11, F12;
`-` `=` `[` `]` `;` `'` `/` `\`; the arrows, INSERT, HOME, END, PAGE UP,
PAGE DOWN and the keypad; MOUSE5. (F12 is Steam's screenshot key, so
leave it.) Test and debug actions go only on these.

## Every key on main, and where it goes

"Stays" means it already does what CS2's default does, or Sid chose it.
"Moves" is a test key on a key CS2 uses; the new key is a proposal Sid can
change.

| Key | Does now | Where | CS2's default | Plan |
|---|---|---|---|---|
| W A S D, SPACE, CTRL, SHIFT, R | move, jump, duck, walk, reload | player | same | stays |
| MOUSE1 | fire | player | `+attack` | stays |
| MOUSE2 | nothing yet (in the input map, not in `PlayerInput.BUTTONS`) | player | `+attack2` | stays; sends `ATTACK2` (contract section 5). *Done: the inventory PR* |
| 1, 2 | slot 1, slot 2 | player | `slot1`, `slot2` | stays |
| MWHEELUP | jump | player | `invprev` | stays: Sid's choice |
| V | noclip | player | `+radialradio2` | stays: Sid's choice, bound to the `noclip` command (a cheat command in CS2 too) |
| ESCAPE | frees or captures the mouse; closes the buy menu | player, buy menu | `cancelselect` | stays until item 26's pause menu |
| B | buy menu | range, dust2 | `buymenu` | stays |
| 1 to 5 in the buy menu | column, then item | buy menu | the same in CS2's menu | stays; an open menu takes keys first, as in CS2 |
| E | defuse | range (bomb) | `+use` | stays; becomes the `USE` bit (contract section 5). *Done: the inventory PR* |
| 4 | next grenade | range (grenade lane) | `slot4`, cycles grenades | stays; becomes `slot4` with the inventory in the player. *Done: the inventory PR* |
| 5 | plant | range (bomb) | `slot5`, the C4 | moves off when the inventory is in the player: 5 takes the C4 out and `+attack` or `+use` plants, as in CS2. *Done for `+attack` (the inventory PR); `+use` does not plant yet* |
| Q | throw as MOUSE1 does | range (grenade lane) | `lastinv` | retires with the hand throw (`grenades.md` item 2): MOUSE1 overhand, MOUSE2 underhand, both for the middle. Until then, `;`. *Done: retired by the inventory PR; Q is `lastinv`* |
| Z | throw as MOUSE2 does | range (grenade lane) | `radio` | as Q; until then `/`. *Done: retired* |
| X | throw as both buttons | range (grenade lane) | `slot12` | as Q; until then `\`. *Done: retired* |
| G | the dummy never dies | range | `drop` | moves to `[`; G is `drop` (contract section 5). *Done: the inventory PR* |
| H | hitboxes shown | range | `switchhands` | moves to F1 |
| T | hitbox camera | range | `+spray_menu` | moves to F2 |
| M | next surface behind the dummy | range | `teammenu` | moves to `]` |
| U | the shooter's weapon | range | `messagemode2` | moves to `-` |
| I | the shooter fires | range | `show_loadout_toggle` | moves to `=` |
| Y | your armour | range | `messagemode` | moves to `'` |
| F3 | the position readout | HUD | `autobuy` | moves to F8 |
| F5 | ends warmup (`mp_warmup_end`) | dust2 | `jpeg` | moves to F9 |
| K | the dummy's armour | range | unbound | stays |
| N | the dummy's distance | range | unbound | stays |
| J | you never die | range | unbound | stays |
| L | gives you the kit | range (bomb) | unbound | stays |
| O | resets the range (and money, grenades) | range | unbound | stays |
| P | exports the spray | range | unbound | stays |

That moves nine test keys (G, H, T, M, U, I, Y, F3, F5) and, when the
inventory and the hand throw are in the player, retires four stand-ins
(5, Q, Z, X). Afterwards every key CS2 uses does what it does in CS2, on
dust2 and on the range alike, and the test keys sit only where CS2 has
nothing.

The inventory PR (roadmap item 12) went in before the table. It binds
G `drop`, E `+use`, MOUSE2 `+attack2`, 3 to 5 and Q `lastinv` in
`project.godot` and `PlayerInput`, retires the four stand-ins (the range's
new bomb went from 5 to `O`, its reset), and moves the never-die to `[`.
The table takes those over as it takes the rest.

Still to adopt from CS2's list as the systems arrive (3, Q `lastinv` and
G `drop` came with the inventory): MWHEELDOWN `invnext`, 6 to 0 and X
(each grenade and the Zeus), F `+lookatweapon`, TAB (item 15's
scoreboard), `,` `.` DEL F4 (buying's extras), `` ` `` (the console,
`systemization.md` step 4).
Radio, chat, pings and graffiti are under "Later" in the roadmap.

## The system

1. **One bind table, a key to a command, as CS2's `bind "g" "drop"`.** A
   command starting with `+` is held: `+attack` sets `UserCmd.ATTACK` while
   the key is down, with the sub-tick time of the press and the release, as
   `PlayerInput` does now. Any other command runs once on the press.
2. **Keys never reach the simulation.** The table is the client's: it
   turns keys into the next `UserCmd`'s buttons, `weapon_select` and
   `toggle_noclip`, and into commands. Game commands (`buy`, `sellback`,
   `drop`, `throw`, and later `lastinv`, `invnext`) go to `game.command`, as
   the contract says; the client's own (`buymenu`, `toggleconsole`, the
   range's) run on the client. So bots, and later a network client, send
   the same commands without a keyboard.
3. **The defaults are CS2's file**, copied into the code with its path,
   and Sid's two departures (MWHEELUP `+jump`, V `noclip`) listed in one
   place beside it.
4. **Test and debug actions are named commands, bound in a second table on
   keys CS2 leaves unbound.** The range loads it, as CS2 runs a cfg with
   `exec`, and dust2 can load it too, so the range's tools work in a dust2
   playtest. Where CS2 has a command, use its name (`god`, `noclip`,
   `mp_warmup_end`, `give item_defuser`); the rest get plain names
   (`range_hitboxes`, `range_reset`). These are the commands the console
   runs once it exists (`systemization.md` step 4).
5. **One place hands out a key.** An open menu (the buy menu now; the
   console and scoreboard later) takes keys first, as CS2's do, then the
   bind tables. Today `player_controller.gd`'s `_unhandled_input` never
   marks an event handled, so a key bound twice does both things
   (`contracts.md` section 5); one dispatcher ends that.
6. **Physical keys**, as now, so WASD stays WASD on another layout.
7. **The table replaces `project.godot`'s input map** as where the game's
   keys are set. `scripts/setup_input_map.gd`, which should write that map,
   already knows only 21 of its 32 actions (the range's are the rest). Godot's own `ui_*` actions can
   stay for menus.
8. **Rebinding comes later:** a user file in CS2's `bind` syntax, edited
   from the settings page (item 26) or the console's `bind` and `unbind`
   (step 4). The first version needs neither.

## Checks (`tests/run_bind_checks.gd`)

- The default table is CS2's file, key for key, apart from the listed
  departures.
- No key is bound twice in one table, and the test table uses no key the
  default table binds.
- Every bound command exists; a bind to an unknown command fails.
- A key pressed and released through the table gives the expected button
  in the next `UserCmd`, with its sub-tick times, or the expected command
  in `game.command`.
- Nothing outside the input code and an open menu reads a keycode or a
  Godot action for game input (a search of `src/` and `maps/` for `KEY_`
  and `is_action_pressed`).

## Local and Remote

- **Remote:** the tables, the commands for the test keys, moving the
  range (`test_range.gd`, `grenade_lane.gd`), the HUD's F3 and the buy
  menu onto them, `PlayerInput` reading keys through the table, the input
  map in `project.godot`, and the checks. The match's F5 is one line in
  `src/modes/competitive.gd`, done with the local agent's agreement.
- **Local:** the wiring in `contracts.md` section 5 (G `drop`, E `USE`,
  MOUSE2 `ATTACK2`, the inventory's slots and `lastinv`, the hand throw)
  adds its keys as binds in the table rather than new key reads. If that
  wiring lands first, the table takes its keys over. Sid checks CS2's
  in-game defaults against the file (`key_listboundkeys`) and plays with
  the moved keys.
