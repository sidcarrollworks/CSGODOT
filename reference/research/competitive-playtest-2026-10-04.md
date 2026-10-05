# Competitive playtest follow-up, October 4

Sid tested Dust2 competitive with the movement-command and subtick-friction
changes (#191–192). Movement felt very good and smoke lineups nearly perfect.
This follow-up leaves those movement rules alone.

## HUD, audio and spectator fixes

- A planted bomb replaces the round clock with the extracted red planted-C4
  icon. A defuse shows its green counterpart; the next round restores the clock.
  The icon's pulse is an approximation, not a recovered Panorama animation.
- The opaque red patch was a local blood particle placed eight units ahead
  of the camera with a guessed projection scale. Suppress that approximation
  for local hits, including helmet particles; retain the existing narrow
  directional damage arcs. Blood on other bodies, world splashes, hit sounds
  and flinches remain. Exact CS2 local-screen particle control points are open.
- Spectator status and controls use separate lines. Reserve ammo has a six-pixel
  gap before its magazine icon. The inventory list was rendered at 1080 and
  its icon/key gutters checked; no further guessed rescaling was applied.
- After a controlled bot dies, a dead human may take another living teammate
  bot. The one-takeover-per-round restriction was removed at Sid's request.
  Enemy, living-human, roaming and already-controlled restrictions remain.
- Team selection was bypassed by our test launcher passing `--team t`.
  Interactive competitive launches must omit `--team` to display the picker.
  Explicit `--team` remains useful for deterministic tests and profilers.

## Current CS2 bomb-beep audit

Read from Sid's installed `game/csgo/bin/win64/client.dll` on 2026-10-04 with
Ghidra 12.1.4, using `CS2_Viewmodel_Current_20261004`. Executable SHA-256:
`d7db25d48f1d10c5e0b0296e20ed803426eb9509da41760daeda39dd35ba89b9`.
The older shooting project contains a different build and was not used for
the final findings. The full 4,218-byte function span, including chained PE
unwind ranges, was exported and byte-compared to the installed executable.
Decompiled text, binaries and temporary scripts stay under ignored `.godot/`.

Planted-C4 update: `0x180caee60` through `0x180cafed9` (inclusive).
Regular sound-name references: `0x180caf434` and `0x180caf43e`;
warning references: `0x180caf60e` and `0x180caf61d`.

The remaining fraction is clamped between zero and one. The next beep is
scheduled at current time plus `max(0.15, 0.1 + 0.9 * remaining_fraction)`.
The float constants and min/max/clamp helpers were checked against the PE
and disassembly, not inferred from the debug string. For a 40-second timer:

| Seconds remaining | Interval |
|---|---|
| 40 | 1.0 s |
| 30 | 0.775 s |
| 20 | 0.55 s |
| 10 | 0.325 s |
| 5 | 0.2125 s |
| 0 | 0.15 s |

The regular site-A/site-B beep is started first. With **11 seconds or less**
remaining, the matching `_10sec` event is additionally started in the same
update. It does not replace the regular event. Their extracted sound events
retain A/B pitch, gain, distance curve and warning delays (A 0.05 s, B 0.07 s).
The separately selected ten-second music cue is unchanged.

The update also computes `min(1, 0.2 + 0.8 * remaining_fraction)` for a sound
parameter. Its parameter identity has not been confirmed; it is not the
interval and was not ported as an assumed volume control.

## Basic round planner follow-up

Sid also reported that bots loop one route, never use Long, and do not hunt
or defuse. `BotRoundPlan` now chooses one-way goals above their existing
navigation/combat. It is an explicit implementation choice based on
`round-hud-bots.md` B4/B8 and its item-24 recommendations, not a claim to
have recovered CS2's complete tactical AI.

- `BotRoundMap` prepares named callout floors once. Dust2's openings use Long,
  Short and tunnels/B doors; other maps fall back to site goals and callout
  searches. Both teams have physically passed through Long in the Dust2 replay.
- Broad site callouts are **not** planting volumes: Dust2's A/B callout centers
  are outside `func_bomb_target`. Plant goals are projected onto a nav floor
  inside the actual volume, checking `BombSite.contains`; no guessed goal is
  returned if it cannot find one. A carrier follows an opening lane to its
  selected site and plants through held Attack/Duck with the C4 equipped.
- A sight memory stores the enemy's position when visible, never continually
  reading a hidden opponent's position. After ten seconds it expires; arrivals
  lead to searches of other named areas, staggered by bot/round. CTs initially
  hold their opening position for eight seconds. These are chosen policies.
- Post-plant, one autonomous CT receives the defuse goal, preserving a current
  human/bot defuser. Assignment prefers a kit within a 200-unit distance penalty,
  uses distance and a stable userid tie-break, and excludes controlled bots.
  Other CTs move to spots around the bomb; Ts guard. Defusing holds Use and aims
  at the bomb through `BombSystem`, including its reach, ground and angle checks.
  Losing the defuser allows another living bot to take the task.
- Human T item/goal deference remains; a controlled bot counts as human-directed
  to the planner. A bot can recover and plant after the human dies. Cover,
  acoustic investigation, coordinated rotations, escape when no defuse is
  possible, grenade tactics and complete CS2 AI parity remain open.

Planning stays in `prepare_to_think` on the tick thread, reviewed every half
second and immediately when bomb state/carrier/defuser changes. It neither
reads disk nor adds unbudgeted AStar searches. `Bot._find_way` retains the
world's existing search budget. Worker thinking reads the goal and writes only
that bot's command/sight memory. Navigation fixtures/range bots retain their
route loops when no competitive planner is attached.

Focused checks completed real plants and kit defuses both sequentially and on
workers. Dust2's 50-second fight remained identical at every tick across both
thinking modes. The extracted-map quiet-round replay completed a plant and
defuse and verified Long traversal; its committed check also verifies a CT
round win. Sid's live match replay remains necessary for tactical quality.

Full bot follow-up validation: **8,878 checks in 86 files, all passed** with
extracted maps/assets, Box3D and current native libraries. The quiet Dust2
check planted at 31.19 s and completed the kit defuse at 43.98 s (321 Use
ticks). Planning alone, for nine bots post-plant over seven 10,000-tick
trials, measured 0.01116 ms/tick median (0.01110–0.01213 ms); this excludes
navigation searches, combat and the rest of the match. The normal interactive
competitive launch without `--team` showed the team picker before starting.

## Validation

Focused checks cover local-hit suppression, planted/defused/reset HUD state,
repeat takeover, beep intervals and actual layered playback. A rendered 1080
HUD fixture with extracted fonts/icons verifies spectator text, reserve ammo,
the planted icon and inventory gutters. Local match playtesting is still
needed for the corrected beeps and damage feedback.

`scripts/run_tests.sh` passed **8,832 checks across 84 files** locally with
extracted assets, Box3D and the current debug/release native libraries.
