# Jump snapshot timing and the Dust2 Xbox lineup — October 2, 2026

Sid's playtest found that the T-spawn jump smoke followed the expected route
but bounced below Xbox. The two reference screenshots supply the aim landmark,
the expected landing surface and our rounded HUD values: feet
`(-1163.7, 77.8, -299.7)`, yaw `270.2`, pitch `11.8` in Godot coordinates.
There is no recorded CS2 launch state or time series for this comparison yet.

**October 3 follow-up:** the [subtick audit](grenade-subtick-snapshot-2026-10-03.md)
establishes that CS2 scopes this clock to each movement segment and inserts
an exact snapshot boundary. The sign fix below remains in PR #184, but its
whole-tick capture was incomplete. Sid subsequently requested applying the
audited replacement for playtest; it now runs on the branch, while the
mid-door landing regression remains unresolved.

## Cause and correction

The initial grenade audit misread the helper that offsets the jump snapshot
timer. The port added a movement interval to the input's jump instant.
The instructions instead use the scoped simulation time, subtract the
current movement interval, then add 0.1 seconds:

```text
stash_time = simulation_time - movement_interval + 0.1
```

The relevant server addresses are unchanged from the original audit:

- `180ab57f0` and `180adf830`: the two jump paths read the movement interval,
  obtain the pawn's simulation time and schedule the stash.
- `180c7fe60`: supplies the pawn tick used to select the scoped clock;
  `180921a10` reads current time rather than converting this tick to seconds.
- `1801bdb80`: subtracts its float argument (`SUBSS XMM0,XMM2`).
- `18017e3f0`: adds the subsequent 0.1-second delay.
- `180abe000` / `180add6f0`: capture the parameters when movement finish
  crosses the stash time.

`GrenadeThrowState.jumped` now subtracts the movement interval.
The initial `PlayerSim` correction passed whole-tick time at movement finish.
The jump's physical movement used its subtick press. CS2 uses segment-end
time and segment duration, implicitly retaining the button fraction, and
adds a movement boundary at the deadline. This remaining difference was
established by the October 3 audit and is now implemented for playtest.

The delayed release, snapshot age checks, box flight, restitution `0.45`
and high-speed floor reduction stay as recovered. The error was in the
launch state, so this correction applies to jump throws of all six grenades.

## Current installed build check

CS2 updated locally after the initial audit. The current `steam.inf` says
client/server **2000924**, patch **1.41.8.8**, SourceRevision **11076591**,
built October 2, 2026 at 14:45:21. Current `server.dll` SHA-256:

`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`

The original Ghidra project retains the September 30 binary, with the hash
recorded in the original audit. Before using its instructions, the bytes at
the same addresses were compared against the current installed module.
All nineteen checked function spans are byte-identical: the two jump paths,
movement finish and snapshot writer/getter, jump predicate, release writer
and consumer, launch calculation, pawn-tick getter and scoped-clock getter,
subtraction and addition helpers,
flight/gravity routines, collision callback, velocity clip, collision dispatch
and push routine. Current-module constants independently read as
`0.1`, `0.2` and `96000.0` at their original addresses.

This validates these particular anchors in the newer module; it is not a
claim that every grenade-related function or resource is unchanged.
Ghidra was used read-only. Local exports, instruction listings and comparison
binaries remain ignored; no Valve binary or decompiler output is committed.

## Reproduction and validation

```text
godot --headless --path . --script tests/run_grenade_lineup_checks.gd
```

This optional asset-dependent regression loads only the extracted Dust2 hull,
including grenade clips, and runs the real `GameWorld`, player movement,
held smoke release and Box3D flight. It requires the patched addon and skips
when the collision assets are absent. Three jump fractions (`0`, `0.25`,
`0.75`) are crossed with release offsets of `0`, `2` and `8` ticks.
It checks a contact with the wooden top, a rest point in the Xbox region,
absence of blocked starts and repeatability across eligible release times.

At jump fraction `0.25`, the old port captured upward pawn velocity
**209.8055 u/s**; the corrected timer captures **222.3055 u/s**.
The grenade inherits 1.25 times that velocity. The first ground bounce
therefore happens later along the sloping mid floor, and the rebound reaches
Xbox's top instead of its side:

| Quarter-tick jump fixture | Old port | Corrected timer |
|---|---|---|
| First ground contact | `(1105.839, -77.999, -307.622)` | `(1172.953, -93.999, -307.856)` |
| Rest point | `(1283.780, -121.196, -317.340)`, below Xbox | `(1444.472, -26.927, -308.954)`, on Xbox |
| Flight to rest | 6.484375 s | 5.281250 s |

All nine cases reach the top with unchanged bounce rules. The same jump
fraction gives the same trajectory for all three eligible release offsets.
Different jump fractions still produce different movement states and final
rest points; this fixture does not establish exact CS2 subtick consistency.
The existing timer suite covers strict release and snapshot-age boundaries,
and the simulation suite also checks retained aim after a later mouse turn.

The screenshots are rounded inputs and show the intended landing, not exact
CS2 coordinates for every contact. A live side-by-side throw, followed by
recorded first-bounce and landing positions/times, remains necessary before
claiming precise lineup parity or adjusting the global bounce coefficient.
