# Current hit effects: draw cost, 2 October 2026

PR #172 replaces placeholder blood with the extracted current CS2 particle
layers, world impacts, persistent projections, body wounds, hit sounds and
additive flinches. This has a measurable cost during sustained hits. It is
mostly CPU time evaluating particle attributes in GDScript, rather than GPU
fill or physics rays.

## Fixture

`scripts/profile_hits.gd` runs the actual test range on the local RTX 4070 Ti,
Godot 4.7.2, Vulkan Forward+, with extracted assets and current native physics.
The camera stays 256 Source units from the dummy. The simulation keeps
ticking. Vsync and the frame cap are disabled. Each phase lasts seven
seconds; the first two seconds are discarded, then medians are reported.

One pair means one 30-health/5-armor body hit and one world impact. The
fixture sends authoritative hurt/damage snapshots to exercise audio,
flinches, wounds and particles without killing the dummy. World particles
alternate default and solid metal. It does not add world bullet-hole marks.
Each phase clears particles and body/blood projections before starting.
The sequence is idle, eight pairs/second, 32 pairs/second, then idle again.
The last phase checks recovery after the pools have been used.

These are controlled effects measurements, not competitive-match frame
rates or a paired comparison against main. The scene, sustained hit rate,
close camera and accumulated marks differ from a normal match. GPU and
whole-frame times overlap; they should not be added together.

## Results

| Resolution | Hit pairs/s | Whole frame, ms | GPU, ms | Particle draw script, ms | Live particles |
|---|---:|---:|---:|---:|---:|
| 1920 x 1080 | 0 | 1.346 | 0.262 | 0.024 | 0 |
| 1920 x 1080 | 8 | 4.372 | 0.719 | 2.536 | 132 |
| 1920 x 1080 | 32 | 11.524 | 1.807 | 8.558 | 480 |
| 1920 x 1080 | recovery | 1.387 | 0.277 | 0.024 | 0 |
| 3840 x 2160 | 0 | 1.953 | 1.017 | 0.024 | 0 |
| 3840 x 2160 | 8 | 4.455 | 1.482 | 2.560 | 132 |
| 3840 x 2160 | 32 | 11.599 | 2.576 | 8.563 | 482 |
| 3840 x 2160 | recovery | 1.949 | 1.003 | 0.024 | 0 |

At eight sustained pairs/s, frame time rises about 3.03 ms at 1080p and
2.50 ms at 4K; GPU time rises about 0.46 ms at either size. At 32/s, the
particle interpreter dominates the frame. This is a remaining performance
limitation, even with the bounded 512-particle pool. The near-identical
particle draw cost across resolutions supports the CPU attribution.

Caching renderer keys, attribute-operation descriptors, sampled constants,
fade/growth values and sprite-sheet offsets reduced the 1080p eight-pair
draw stage from 3.102 to 2.536 ms (about 18%) in consecutive serialized runs.
The authored table stays unchanged. Body mist uses the playtest override:
twice the count/cap, half the lifetime, and initial positions within one
Source unit of the actual bullet contact. The performance rows include it.

Decals, wounds, model variants and quad batches are bounded/prepared before
play. Event handlers queue snapshots, rendering runs on draw frames, and
projection rays use the physics-query wrapper in physics frames. Further
reductions should target native/GPU particle evaluation or a measured
detail budget; these results do not establish regression-free comp play.

## Reproduce

After extracting/importing assets, run these separately with no other GPU
test or game instance active:

```text
godot --path . --script scripts/profile_hits.gd -- 1920x1080
godot --path . --script scripts/profile_hits.gd -- 3840x2160
```

Read the final `HIT_PROFILE` JSON line. Optional per-stage instrumentation is
enabled only by this script. Captures are written to ignored
`.godot/pr172-hit-profile-1920.png` and `-3840.png`. The local measurement logs
are `.godot/pr172-hit-profile-1080-cached.log` and
`.godot/pr172-hit-profile-4k.log`.
