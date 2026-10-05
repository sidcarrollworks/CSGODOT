# Walking and scoped movement commands — October 4, 2026

This follow-up ports ordinary land command speed selection, walking taper
and scoped weapon acceleration to the existing combined movement kernel.
Command caps and acceleration scales are separate values. Both GDScript
and native movement apply the cap before deferring collision velocity.

## Evidence

Installed CS2 build **2000924**, patch **1.41.8.8**, SourceRevision
**11076591**, built October 2. Server SHA-256:
`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`.

Ghidra 12.1.4 exports were checked against current PE bytes: **16 function
spans match byte for byte**. Movement exports from the accumulated project
were checked individually; the three current weapon getters were exported
from a fresh import of the installed server. Current MSVC RTTI resolves the
AWP, SSG 08, AUG and shared gun vtables to the same getter addresses.
Disassembly confirms float returns and constants alongside pseudocode.
Binaries, projects, decoded code and diagnostic scripts remain uncommitted.
No Valve DLL was executed or debugger attached.

| Path | Server address | Confirmed ordinary behavior |
| --- | --- | --- |
| Movement dispatch/speed setup | `180ad89b0`, `180ad5510` | Select the minimum of weapon speed and the ordinary 260 u/s ceiling before command modifiers |
| Command parameters | `180ab6310` | Walking gate, grounded velocity modifier, then input scaling |
| Ground acceleration wrapper/core | `180ab0010`, `180ab00d0` | Separate wish cap, acceleration scale, walking goal and projected-speed taper |
| Walk movement | `180ae3950` | Clamp total velocity at the command cap; add the clamp correction to continuous acceleration before deferring |
| Weapon speed getter | `1809b8880` (`+0xc20`) | Mode array at weapon data `+0x748` |
| Zoom-level count | `1809b9bf0` (`+0xc28`) | Weapon data `+0x7f4` |
| Current zoom level | `1809f9e80` (`+0xcb0`) | Weapon `+0x1280` |

Other checked spans are the min/max helpers `180178b30`/`180178b40`,
friction `180abe710`, interval finish `180abe000`, pre-move `180ad5fb0`,
`180adbbd0` and supporting weapon method `180a09130`. Exported constants
confirm 250, 260, 0.52, 0.34, 110, 25 and 5.

## Ported behavior

**Command speed.** A walk command reduces the cap to 0.52 of weapon speed
only when the pawn's incoming full velocity magnitude is strictly below
that walk speed plus **25 u/s**. Faster walk entry retains the running cap
while friction slows it. Duck input or an active duck transition suppresses
walking; the two slowdowns do not stack. The existing duck-amount transition
still scales the ground cap. Tagging applies to ground command speed, while
the untagged weapon speed controls acceleration. Air crouch leaves its
wish speed unchanged.

**Acceleration scale.** Let `base = max(250, wish_speed)` and
`ratio = min(weapon_speed / 250, 1)`. Running uses `base * ratio`;
ordinary walking uses `base * 0.52`; ordinary crouching uses `base * 0.34`.
When zoom is active, the weapon has more than one zoom level, and
`weapon_speed * 0.52 < 110`, walking retains the ratio without another
0.52 multiplier, and crouching uses `base * min(ratio, 0.34)`.
The AWP and SCAR-20 enter this branch; the scoped SSG 08 and AUG do not.

The AK's walk cap is **111.8 u/s** but its acceleration scale is **130**.
The scoped AWP's walk cap is **52** but its scale is **100**. This corrects
their former scales of 111.8 and 52 respectively. Crouched AK acceleration
remains 85, preserving the accepted slow starts on slopes.

**Walk taper.** The independent walking goal is `base * ratio * 0.52`.
After friction, acceleration is full up to goal minus **5 u/s**, then
decreases linearly to zero at the goal, using positive velocity projected
along the wish direction. Counter-strafing and perpendicular input retain
full acceleration. The taper is ground-only and clears when Walk is released.

**Total ground cap.** WalkMove caps the entire velocity vector even without
movement input. The former crouch guard preserved residual speed and only
capped selected turns. CS2 applies its command cap directly. A crouched
knife-to-AWP switch therefore caps a perpendicular turn at 68 u/s instead
of retaining the knife's faster residual speed. Its correction participates
in midpoint displacement and collision restoration, as in the earlier
[horizontal integration](horizontal-integration-2026-10-03.md).

## Validation

The command suite checks independent numeric scales/caps, the strict walk
entry boundary, full-magnitude gating, ground versus air tagging, both AWP
zoom levels, AUG/SSG 08/SCAR-20 selection, reverse input and taper boundaries.
Real Box3D intervals check speed, midpoint displacement, coasting and total
turn speed, long walk holds and releasing Walk. Every native step is also
run by the script and compared bit for bit. The existing total-cap oracle
now supplies its command cap explicitly; the obsolete gradual knife-to-AWP
expectation is replaced with the recovered absolute cap.

Both native debug and release libraries were rebuilt from the final sources.
The full runner exercised **8,768 checks across 83 files**, with three
drawing-only suites skipped in headless mode and four existing AWP drop
settling cases reported as known open. Two legacy movement assertions
initially failed: the course's direct body driver retained PlayerSim's new
command cap after its settling phase, masking friction differences between
jump press times. Clearing command inputs at that handoff restores the
fixture's intended legacy-mode isolation; its assertions are unchanged.

The final runner rerun passed **146 checks**: **66 command movement** and
**80 legacy movement**, with no script errors. These replace the earlier
64/80 results, yielding **8,770 checked cases** across the full run and
targeted reruns, all passing. The new command fixture compares **221 native
and script steps bit for bit**. The full run also passed **138 crouch
movement**, **158 horizontal integration**, **32 native movement**, **283
simulation** and **354 grenade lineup** checks. The accepted Dust2 launch
fixtures still pass; new CS2 walk/scoped captures remain local validation.

### Paired performance

The seeded ten-player Dust2 fixture ran serially in the order updated,
main, main, updated, using separate native processes after tests finished.
Main is unchanged `ec221626ffff3545b44cab98e6b5d2cd10a71264` in a separate
checkout. Each run warms up for 96 ticks and measures 768 ticks of
`GameWorld.step()`, including native physics stepping. Rendering, audio/UI,
animation pose refresh and Godot's automatic server step are excluded.
Both checkouts use Box3D and active terrain eyes, and
their native source stamps identify their respective source versions.

| Run | Mean ms | p95 ms | Maximum ms | Movement traces/tick |
| --- | ---: | ---: | ---: | ---: |
| Updated 1 | 2.579 | 3.407 | 5.358 | 44.66 |
| Main 1 | 2.638 | 3.520 | 5.142 | 46.35 |
| Main 2 | 2.578 | 3.408 | 4.843 | 46.35 |
| Updated 2 | 2.599 | 3.396 | 5.254 | 44.66 |

The paired mean is **2.608 → 2.589 ms**, a **−0.019 ms (−0.7%)** change
smaller than repeat variation. This shows no mean-cost regression in this
fixture. Updated p95 is slightly lower; the largest observed updated tick
is 0.216 ms above the largest paired main tick. Four runs do not establish
worst-case cost or a rendering performance improvement.

Both versions fire 22 shots and retain all ten players. Command caps change
routes/endpoints, so this is not an identical-trajectory microbenchmark.
Native queries change from 51,166 to 50,294 and terrain casts from 17,858 to
16,717; no query was added to the command-selection path. The query and
endpoint records reproduce within each version.

## Remaining boundaries

This is the ordinary supported land path. Use/hostage constraints, water,
ladders, moving platforms, repeated-duck gates, complete duck/root/view
timing and modern landing/bhop windows remain outside this port.

Friction's input/time cache at movement services `+0x690..+0x698` remains
separate work with command event segmentation. The current port computes
control speed afresh each segment; this follow-up does not claim the cached
subtick behavior or complete CS2 velocity quantization. Scalar configuration
arithmetic uses the game's existing precision; native/script agreement and
these numeric checks do not prove complete CS2 trajectory parity.

Local follow-up: walk entry/release, counter-strafing while scoped, scoped
crouch turns, walking on slopes, and run/jump smoke lineups on Dust2/Mirage.
