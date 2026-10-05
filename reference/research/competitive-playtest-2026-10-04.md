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

## Remaining round behavior

Sid also reported that bots loop one route, never use Long, and do not hunt
or defuse. Their navigation/combat primitives exist but they have no round
planner. A separate follow-up will choose objectives, preserve sight memory,
assign lanes and issue normal plant/use commands through the simulation.
That planner will be an explicit implementation choice based on the existing
bot research, not a claim to have recovered CS2's complete tactical AI.

## Validation

Focused checks cover local-hit suppression, planted/defused/reset HUD state,
repeat takeover, beep intervals and actual layered playback. A rendered 1080
HUD fixture with extracted fonts/icons verifies spectator text, reserve ammo,
the planted icon and inventory gutters. Local match playtesting is still
needed for the corrected beeps and damage feedback.
