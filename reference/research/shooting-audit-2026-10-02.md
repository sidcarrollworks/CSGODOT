# Shooting audit of the installed CS2 build

Audited 2026-10-02 against CSGODOT `2080489` and Sid's installed CS2.
This covers weapon checklist R3, R6, R7 and the remaining R5/R13 parity
work, with a smaller Zeus pass for roadmap item 21. It changes no gameplay.
It supersedes the September 24 guesses about these algorithms in
[combat.md](combat.md); implementation checkboxes remain as they were.

The useful result is that most missing shooting behavior can now be built
from the installed data and code. The remaining local checks concern
animation transitions, input ordering and observed bullet/camera paths,
rather than guessing recoil constants or the R8 delay.

## Evidence and reproducibility

**Data** means freshly decoded installed resources. **Binary** means a
reachable machine-code path, inspected in Ghidra and checked against
instructions/constants where the decompiler's types were wrong.
**Open** means this audit does not yet establish the behavior. Descriptive
function names below are ours; Valve's PDB/source was not available.

Used [Ghidra 12.1.4](https://github.com/NationalSecurityAgency/ghidra),
JDK 25 and Source2Viewer CLI 20.0. The official Ghidra release archive's
SHA-256 matched its release asset digest. Server, client and tier0 automatic
analysis completed. Selected client recovery/spread paths were compared
with the server. PE unwind ranges and MSVC RTTI/vtables helped identify
functions; string names alone were not taken as proof of an algorithm.

Installed `steam.inf`: patch **1.41.8.8**, client/server **2000922**,
SourceRevision **11064488**, version date September 30, 2026 at 16:29:50.
Steam manifest build **25640462**. These are installed-build findings,
not a claim that a later Steam update uses the same instructions.

All addresses below are preferred virtual addresses in the corresponding
64-bit PE, image base `0x180000000`; subtract that base for an RVA. ASLR
runtime addresses differ. Re-identify functions after a binary changes.

| Input | SHA-256 |
|---|---|
| `game/csgo/bin/win64/server.dll` | `3541e46a3193fcf1151e97ce19cd4daf86c5fdb2889033c2bab1d4cc7f555b9c` |
| `game/csgo/bin/win64/client.dll` | `9ddf30d68b8ef66607783d418c4f74a6004cf2104572e6c630625e52c1c1202d` |
| `game/bin/win64/tier0.dll` | `4e0dcb0af3f6953f37ddaed0f4e67a56d031f1e84964a262148f8a6f80547791` |
| Fresh CLI text for `scripts/weapons.vdata_c` | `a7f8d2f69ff1daba35a7441a7a23cf7bb3ac4205313624dbf32c3dc289bfc81c` |

The fresh scalar/one-line-array comparison resolves **43 weapons/equipment**
and compares **1,629 shooting-related fields** with the generated CSV:
**zero changed, newly present or missing fields**. This is a comparison of
that field set, not of every model, animation or nested resource block.
The missing behavior is not explained by stale weapon tuning in that table.

Reproduction helpers and commands are in
[scripts/shooting_audit](../../scripts/shooting_audit/README.md).
Raw resources, DLLs, Ghidra databases, logs, and decompiler output stay local
under ignored `.godot/shooting-audit/` or the external Ghidra project folder.
This page records our description of behavior, not Valve source code.

Generated schema names were checked against
[GameTracking-CS2 at 6ac2479](https://github.com/SteamDatabase/GameTracking-CS2/tree/6ac247908a83c309b37314fd097c47dc78103746/DumpSource2/schemas/server).
The installed serializer supplies the offsets used here: weapon
`m_flRecoilIndex = 0xf98`, accuracy penalty `0xf88`, burst flag `0xf9c`,
postponed attack tick/fraction `0xfa0/0xfa4`, `m_bIsHauledBack = 0xfbc`,
silencer-on `0xfbd`, silencer-complete time `0xfc0`, last shot `0x1038`.
The R8's armed hammer flag must not be mistaken for the adjacent silencer flag.

## Function ledger

| Mechanism | Server address | Cross-check / supporting evidence |
|---|---|---|
| Weapon field serialization | `180a00ca0` | Schema strings and stored offsets |
| Vdata field serialization | `180a097d0` | Names map seeds, recoil, recovery and burst fields |
| Recoil table generation | `1809b7340` | Vdata fields and named tier0 imports |
| Recoil table lookup | `1809b8b60` | Two 64-entry mode tables; index masked with 63 |
| Recoil impulse dispatch | `180a1a230` | Truncated float recoil index, aim-punch service |
| Aim-punch impulse | `180a45890` | Angle/magnitude to velocity |
| Aim-punch reconstruction | `180a38bc0` | Decay constants and 128 Hz cached samples |
| Aim-punch composition | `180a3ce60` | Predictable and unpredictable contributions |
| Bullet aim consumer | `180298420` → `180abf1e0` | Passes scale flag true to composition |
| Recovery time | `1809fb9d0` | Client `18080d700` also truncates float index |
| Accuracy/index update | `180a1fdd0` | Client `1808283f0` agrees on decay/gating |
| Total inaccuracy | `1809fa7d0` | Client `18080c9b0` agrees on movement/air branches |
| Turning / velocity-direction terms | `180a20780` / `1809fbd80` | Optional convars; defaults disabled |
| Shot seed | `180298360` | SHA1 over two quantized floats and a tick |
| Angle quantization | `18028fd50` | Normalize, double, `floorf`, halve |
| Shot/pellet spread | `180298e90` | Client `180d23a60` has same special distributions |
| Shotgun spread table / lookup | `1809b7640` / `1809b96f0` | Seeded radial strata; 64-entry boundary |
| Primary / pending burst shots | `180a198e0` / `180a08b00` | Initial shot plus two follow-ups |
| Secondary mode handler | `180a1c8b0` | Burst, silencers, R8; vdata-controlled generic path |
| R8 primary gate / secondary gate | `180a09130` / `180a094c0` | Client `180818ec0` also adds 13 ticks; alternate mode |
| R8 release/reset | `180a096c0` / `180a1b8c0` | Invalidates postponed deadline |
| Weapon animation state / output | `1809f0d90` / `180a179c0` | Silencer actions and event-driven mode changes |
| Weapon action blocking | `180a209c0` | Primary, secondary, switch and player gates |
| Zeus shot / recharge | `180a284b0` / `180a27720` | Dedicated firing path and recharge convar |
| Zeus trace/damage path | `180a25c50` | Uses weapon range; separate from ordinary pellets |
| Zeus recharge registration | `1800c4b80` | Default 30 seconds; -1 disables recharge |

Tier0 exports are stronger anchors than guessed weapon function names:
constructor `18015e660`, SetSeed `18015e640`, GenerateRandomNumber_Locked
`18015e070`, instance RandomFloat `18015e740`, global RandomSeed
`18015d020`, global RandomFloat `18015d0e0`.

## R6: recoil is a seeded table, including the "random" guns

**Binary.** Each weapon has two mode tables of 64 angle/magnitude pairs.
Each mode restarts the same `CUniformRandomStreamImpl<CThreadNullMutex>`
at `m_nRecoilSeed`, then draws angle variance followed by magnitude variance
for each entry. Add the mode's authored angle/magnitude to those draws.

For full-auto weapons, entries after zero blend both values toward the new
draw by **0.55**. The first four magnitudes also receive factors
**0.75, 0.8125, 0.875, 0.9375**, in that order. Attenuation happens after
blending; the previous magnitude used in the next blend is already
attenuated. Non-full-auto weapons skip those two full-auto adjustments.
Lookup uses the integer-converted decaying float recoil index and `index & 63`.

**Binary.** Tier0's stream is a Park–Miller generator with a 32-value shuffle
table. Its integer step uses multiplier **16807**, modulus **2147483647**,
and quotient divisor **127773**. Initialization warms 40 steps, retaining
the last 32 in reverse slots; the shuffle slot is `previous_output >> 26`.
SetSeed stores the negative absolute signed seed and clears shuffle state;
zero initializes as one. Preserve 32-bit signed behavior, including extreme
seed inputs, when implementing it.

RandomFloat converts the integer to float32, multiplies by **2^-31**,
caps at float32 **0.9999998807907104**, then scales into the requested
interval with float32 subtract/multiply/add operations. Godot's RNG with
the same seed is not this stream. A future port still needs numeric samples
checked against CS2; this audit did not call Valve's DLL routines.

**Binary.** The kick becomes angular velocity: angle is in degrees,
converted to radians, with pitch/yaw components from cosine/sine times
magnitude. Velocity decays at **4.5**; angular decay uses **8 exponential**
and **18 linear**. The bullet aim path requests the **2×** angle scale.
Those four constants in `recoil_state.gd`, previously attributed only to
CS:GO, are now verified in this CS2 build.

The implementation differs beyond the constants: CS2 builds cached
**128 Hz** samples, uses half-step velocity contributions, a **0.03125**
velocity cutoff, and quaternion interpolation between angle samples.
Our 512 Hz integration, one-second forced settling and measured-pattern
impulse fitting are not that exact reconstruction. A separate **0.055**
view-kick contribution also exists in the impulse path; its complete camera
composition needs observation before replacing our cosmetic springs.

**Code gap.** Guns without a measured/community pattern still have
provisional view kick and no corresponding bullet climb. Generate their
seeded impulses, preserve CS2 signs/axis mapping, and validate bullet climb
independently from camera/viewmodel response. Cache tables at load time;
there is no reason to regenerate a recoil table per bullet.

## R13: recovery and inaccuracy

**Binary, client/server agree.** Grounded recovery selects standing or
crouched initial/final times. A final value of exactly `-1` returns the
initial time. Otherwise CS2 **truncates `m_flRecoilIndex` to an integer**
before clamped linear interpolation between the authored start/end bullets.
It does not interpolate with the fractional index or use the separate
persistent integer shot counter. For nonnegative indices, truncation is floor.
Ladder recovery returns initial standing time; airborne recovery returns
**four times initial crouched time**.

For accuracy penalty `P`, current state floor `F`, recovery `T`, and step `dt`:

```
if P < F: P = F
else:     P = F + (P - F) * exp(-ln(10) * dt / T)
```

The update uses a **1/64-second** step. Recovery means a tenfold reduction,
as our `T / ln(10)` conversion already assumes. But our penalty decays
toward zero independently of a dynamically changing stance/air/reload floor.

The float recoil index starts decaying when time is **strictly later than
last shot + primary cycle time + 1/64 second**, then multiplies each step by
`exp(-2 * ln(10) * dt)`. At **0.1 or below it snaps to zero**. Our two-cycle
delay and lack of that cutoff differ. Subtick eligibility and the ordering
of decay versus a new shot still need recorded boundary cases.

**Binary.** Movement maps horizontal speed from **0.34× max speed** to
**0.95× max speed**, clamped to [0,1]. Ordinary movement raises that fraction
to the fourth root; walking keeps it linear. Our threshold/curve agree.

Air inaccuracy additionally uses `sqrt(abs(vertical_velocity))`, remapped
from **0.25× sqrt(jump impulse)** to **sqrt(jump impulse)**, with the
scaled jump-apex and jump-initial fields as endpoints, and clamped between
zero and twice scaled jump-initial. That remap is not clamped before the
final clamp. The persistent airborne penalty floor also contains the
authored mode's jump penalty. Our fixed airborne cone cannot express this
height/vertical-speed behavior. Work in CS2's raw cone values before
converting for Godot; adding separately converted degree cones is not
automatically equivalent.

Optional turning and velocity-direction penalties are present, but both
enabling convars register **false** by default in this build. Their presence
does not justify adding a new default movement penalty. Total inaccuracy
is capped at **1** in raw cone units.

**Open.** Exact zoom-mode accuracy transition/settling, landing penalty
application, and animation-driven changes to the attack gates need a
focused follow-up trace/capture. Our linear `scoped_share()` over ZoomTime
remains provisional; do not present camera FOV animation as proof of that
accuracy curve.

## Spread and R5: shotgun pattern parity

**Binary.** A normal single pellet adds two independently sampled polar
offsets, one for inaccuracy and one for spread. Each radius is uniform
[0,1] and each angle uniform [0,2π]; it is not uniform area in a disk.
R8 alternate fire transforms both radii into **`1 - r²`**. The Negev below
recoil index three repeatedly squares each radius (three, two, or one times
for indices in [0,1), [1,2), [2,3)), then uses **`1 - r`**. From three onward
it uses the ordinary distribution.

The shot stream seed is produced by SHA1 over **12 bytes**: normalized
pitch and yaw quantized to half-degree bins, as float32s, followed by a
32-bit tick. Quantization is `floor(2 * normalized_angle) / 2`, including
negative angles. The first digest word is used; this is not an arbitrary
8-bit seed or a hash of our command object. Preserve byte order and sample
the actual shot angle/tick when porting. Demo bullet messages can also
carry the shot seed, useful for testing the spread generator separately
from seed production.

**Binary.** `weapon_accuracy_shotgun_spread_patterns` registers true.
For a multi-pellet weapon, its `m_nSpreadSeed` generates **64** cached pairs:
angle drawn first, then radius within a linear stratum
`[j / pellet_count, (j + 1) / pellet_count]`. The stratum index wraps through
the pellet count. The radius is clamped to [0,1], with no square root.

Lookup uses **`int(recoil_index) * pellet_count + pellet_index`**. It uses
cached pairs only while that index is below 64; later pellets fall back to
ordinary random spread draws. This lookup does **not** wrap at 64 as the
recoil table does. With patterns enabled, **each pellet also rerolls its
inaccuracy radius/angle**, rather than shifting the whole group by one
common random offset.

**Code gap.** `Weapon.pellet_directions()` currently hashes the spread seed
for one repeated pattern and receives a shared inaccuracy-shifted aim.
Replace that approximation while retaining per-pellet traces/damage,
shell reloads and one report per pull. Check past the 64-pellet boundary,
not only the first shot of a full tube.

## R3/R7: burst, silencers and revolver

**Data + binary.** FAMAS and Glock burst initialize two pending follow-up
shots before firing the first. Post-frame processing fires pending rounds
without another trigger edge, decrementing after each successful shot.
The gap is the authored intershot value until the final round, which sets
`max(1/64, burst_cycle - 2 * intershot)` before another burst may start.
Mode is alternate during the burst.

| Gun | Intershot gap | Complete burst cycle | Mode-switch secondary gate |
|---|---:|---:|---:|
| FAMAS | 0.075 s | 0.55 s | 0.30 s |
| Glock-18 | 0.05 s | 0.50 s | 0.30 s |

A failed pending shot cancels the remaining burst. Burst holstering is
allowed by the compiled default `m_bAllowBurstHolster = true`; the guard
blocks it only when that option is false and follow-ups remain. Still test
empty/one/two-round magazines, release, holster, death and reload ordering.

**Binary.** R8 primary arm stores current tick/fraction plus **13 ticks**,
preserving the fractional part. At 64 Hz that is **203.125 ms**, distinct
from the authored **0.50 s** primary cycle. Holding until the deadline lets
the primary shot through; release resets the postponed deadline and armed
state. Secondary uses alternate mode and its **0.40 s** cycle, with the
special spread distribution above. Mixed primary/secondary input and
holster cancellation still need behavioral cases; do not build those
from the delay number alone.

**Data + binary.** Detachable silencers use weapon actions **600/601**.
Animation output sets silencer-on and switches the mode at the attach or
detach event. The freshly decoded event times agree with `timings.csv`:

| Gun/action | State-change event | Full source clip length |
|---|---:|---:|
| USP-S attach | 3.3666 s | 4.8333 s |
| USP-S detach | 3.3666 s | 4.8333 s |
| M4A1-S attach | 3.4333 s | 4.8333 s |
| M4A1-S detach | 3.2666 s | 4.8333 s |

**Open.** Neither event time nor full clip length alone establishes when
shooting becomes available. The initial action applies a long **100 s**
blocking placeholder; leaving the action resets gates. Animation/action
completion must be followed to get actual timing. That placeholder is
not the silencer duration. Port event-driven mode changes and measure the
earliest accepted primary shot, interrupt/switch behavior and playback rate
before choosing lockout timers.

## Zeus: useful anchors, not a complete damage audit

**Binary.** Zeus uses a dedicated trace/damage handler and authored weapon
range. A successful shot records its fired time and schedules recharge.
`mp_taser_recharge_time` registers **30 s**, with **-1** disabling recharge;
the recharge path restores one charge and emits `Weapon_Taser.ChargeReady`.
Our eventual implementation needs that state, rather than ordinary gun
reserve ammunition. This pass did not finish exact damage falloff,
hitgroup/armour handling or the trace-mask policy; keep item 21 open.

## Implementation order and acceptance work

1. **R13 first:** whole-index recovery, primary-cycle-plus-tick delay,
   0.1 cutoff and state-floor recovery. Smallest changes with direct
   client/server evidence. Compare a pistol and AK tap/spray/pause across
   fractional index boundaries, standing/crouched/airborne/ladder.
2. **Shared RNG + R6/R5:** float32 stream and cached recoil/shotgun tables;
   then recoil reconstruction and ordinary/R8/Negev spread. Validate
   numeric streams before replacing measured-pattern fitting.
3. **R3/R7:** deterministic burst and R8 states in the simulation, with
   button edges, magazines, switching, death and reload boundary checks.
   Silencers additionally need their animation completion trace.
4. **Remaining R13 visual/state checks:** record zoom settling, landing,
   camera kick and viewmodel motion independently. Scope artwork cannot
   validate bullet accuracy or camera composition.
5. **Zeus:** dedicated simulation state and trace/damage follow-up.

Use an offline CS2 practice session: log build, weapon, convars, tick and
fraction, aim, stance/velocity, mode, pre-shot recoil index, accuracy/spread
and shot seed where exposed. Record repeat runs of held sprays, release
gaps around the recovered threshold, first three Negev indices, both R8
attacks, and shotgun shots on both sides of the table boundary. Compare
numerical directions/hit locations before screen-space camera motion.

Research is complete for the recovered branches above. Gameplay parity
and the explicitly open captures remain implementation/validation work.
No performance claim follows from static analysis; profile the actual port.

## Validation of this research change

`scripts/run_tests.sh` passed locally with Box3D, the matching native library
and extracted assets: **7,060 checks across 75 files**. The three GPU draw
checks skip in headless mode. Four Python audit-parser fixtures pass; the
fresh-data and PE helpers ran against the installed files, and both Java
helpers compiled/executed in Ghidra. These validate the tooling and existing
game baseline, not an as-yet-unwritten CS2 mechanics port.
