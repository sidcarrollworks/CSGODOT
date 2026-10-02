# First-person jump camera

Sid's October 1 feedback on [PR #160](https://github.com/sidcarrollworks/CSGODOT/pull/160#issuecomment-5939472124): the weapon transition is smoother, but jumping also needs a little vertical dip and rise of the camera, like the head and eyes in CS2.

## What is established

The extracted first-person gun graph has no jump or air state (`reference/animgraph/viewmodel.md`). Its weapon bob is separate from the view. The body's graph supplies the 0.1 s takeoff and 0.2 s return cross-fades already used by #160's `ViewModelMotion`; issue 17 in `reference/playtest-2026-09-25.md` tracks its air poses and remaining Local extraction.

`reference/research/movement.md` researches physical jumps, crouching and landing, not the camera's head motion. No measured CS2 first-person eye curve or camera dip amounts were found in these pages. Valve's published [Source SDK 2013 player view](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/c_baseplayer.cpp) is older Source code and cannot establish CS2's curve. The camera motion below is therefore a small, explicitly tuned approximation for Sid to compare in game, not a claim to reproduce extracted CS2 camera numbers.

## Implemented for the feedback

`JumpCameraMotion` reads `PlayerBody.air_action` and its simulation timestamp. A jump gives a critically damped vertical spring a downward push; landing gives it a slightly larger one. The exact spring solution uses `DrawClock` time, not drawing-rate Euler steps. The camera starts each response at its existing height, dips, and rises to rest without an upward bounce. A repeated jump can interrupt landing recovery without resetting the height.

| Tuning | Current value | Meaning |
|---|---:|---|
| Spring response | 20 /s | An isolated impulse is deepest after 50 ms |
| Takeoff velocity push | 55 units/s downward | About 1 unit of eye dip |
| Landing velocity push | 88 units/s downward | About 1.6 units of dip after a normal jump |
| Maximum dip | 4 units | Bounds overlapping responses |
| Minimum/full landing air time | 0.08 / 0.3 s | Ignore a brief loss of ground; ease toward the full landing response |
| Viewmodel dip scale | 1 times the eye dip | About 1 unit on takeoff and 1.6 on landing, relative to the camera |

All six choices are **by eye**. Landing strength is approximated from air time, not measured impact speed. Walking off a ledge creates no takeoff response; a longer fall still dips on landing. A stopped or restarted draw clock does not advance or retain stale motion. An action received ahead of the interpolated view waits for its tick to be drawn.

`PlayerView` adds the dip in world-up units to the usual interpolated position and standing/crouched eye height. `ViewModelMotion` also adds that drawn spring height to the arms' camera-local vertical offset, alongside the existing running bob, sway and recoil. The model follows the camera and dips relative to it, so jumping visibly moves the hands and weapon on screen. Guns, knives, grenades and the bomb all use the same composition; switching items during recovery uses the existing spring rather than replaying the impulse. Sniper overlays still hide the first-person model; the AUG and SG 553
keep their raised models visible when scoped.

Sid's competitive Dust2 playtest on October 1 identified the missing part: the eyes moved, but the model stayed fixed relative to them. The initial camera-only implementation supplied no distinct weapon motion. The follow-up keeps the subtle camera tuning and adds the model's relative dip. The first 2-times scale was close but too dramatic in Sid's next playtest, so his requested half-strength bounce uses a scale of 1. The procedural motion remains an approximation rather than a measured
CS2 eye curve.

The next playtest found the overall motion good and very close, with a little too much bounce when the feet hit the floor. The landing push is now 20% smaller (110 to 88 units/s), softening both the camera and the relative weapon response to about 1.6 units. Takeoff strength and spring timing retain the accepted tuning.

Death, respawn, round placement, teleport through `PlayerController.place` and noclip clear the shared response. It adds no physics query, per-tick movement calculation, animation clip, asset load or node; only the local view evaluates the spring per frame, and the model reuses its height. It changes no movement, collision, gameplay eye height, look angles, recoil or shot origin. Spectator/death cameras retain their existing placement.

`tests/run_jump_camera_checks.gd` checks takeoff and landing continuity, dip/recovery, brief ledges and longer falls, repeated jumps, clock alignment and resets, and the same motion at 30/60/144/224/240 FPS. A model-free controller also exercises the actual camera placement and relative viewmodel movement, including the model's scale/rotation, crouched eyes, recovery, noclip, placement, death and respawn. The existing `run_model_checks.gd` continues to check the weapon bob fade and recoil composition with the extracted models.

## Playtest accepted; remaining CS2 measurements

Sid accepted the softened landing response and merged PR #160. The
following are further parity checks, not a pending merge requirement.

Compare standing/running jumps and landings on the test range and Dust2 beside CS2, on both teams and while crouching, carrying guns and equipment. Judge the size and timing of both the camera and weapon dip, a jump during landing recovery, switching items while recovering, and falls from ledges. If a closer match needs measured numbers, record the first-person horizon/eye and weapon motion against the physical jump over time in CS2. The procedural constants remain named so the Local result can replace the tuning without changing the simulation.
