# Current CS2 blood and bullet impacts

Research for roadmap item 5 and PR172, refreshed **2026-10-02**. The local
installation is **CS2 1.41.8.8**, client/server **2000922**, source revision
**11064488**, built **2026-09-30 16:29:50**. Steam's manifest reports build
**25640462**. Source archive:
`D:/SteamLibrary/steamapps/common/Counter-Strike Global Offensive/game/csgo/pak01_dir.vpk`.

Particle KV3, surface mappings, weighted decal groups and material DATA were
decoded from that archive with Source 2 Viewer. **Read** means authored
content, not reconstructed closed-source gameplay code. **Inferred** marks
implementation choices that need controlled CS2 comparison. The original
page's collision-triggered blood placement, universal 30+3-second blood
lifetime, and categorical helmet blood suppression were not established
by the files and are corrected here.

## Sources and update boundary

Valve's [September 22 Rush Hour announcement](https://steamcommunity.com/games/CSGO/announcements/detail/711161056325533827)
describes stronger hit feedback. The shipped-content comparison isolates
18 changed blood definitions and two additions: `blood_impact_localfrontsimple`
and `blood_impact_low_forw_spray`. The impact folder has ten changed files
and two additions; the relevant addition is `impact_fx_hit_darken_model`.
Blood textures, surface mappings and weighted groups were unchanged at
Rush Hour. The scoped graphs also remained unchanged through September 30.

Fixed extracted-content references:

- [Before Rush Hour, d8e2c7a4](https://github.com/SteamDatabase/GameTracking-CS2/tree/d8e2c7a4f9b86e60d5a1b584a83ee0e15f59cc54).
- [Rush Hour, 10f3693c](https://github.com/SteamDatabase/GameTracking-CS2/tree/10f3693c381475016b128c549928d14eb3adfcf2).
- [Installed build's corresponding data, 6ac24790](https://github.com/SteamDatabase/GameTracking-CS2/tree/6ac247908a83c309b37314fd097c47dc78103746).

GameTracking mirrors extracted shipped files, not Valve's gameplay source.
The raw local audit and comparison remain in ignored
`.godot/research-cs2-blood-current/`. Regenerable current numbers are in
[the generated hit tables](../effects/hits.md) and
`src/effects/hit_effect_table.gd`; those win over old handwritten guesses.

Two original release dates were wrong. The blood decal visibility fix was
[January 21, 2026](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1822556746157780).
The default bullet-decal rendering distance increased on
[November 12, 2025](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1816215235365196).

## Airborne blood composes sprites, trails and mist

**Read:** `blood_impact_{low,med,high}.vpcf` are parent graphs. Children
compose animated visible spray, trails, away spray, mist and friendly flash.
All three include the recent forward-spray child. A root distance operator
remaps 128–1024 units to CP4.x 0.2–0.85; children use that as an alpha
threshold. Runtime CP meanings/orientation remain unverified.

The forward child has capacity three and detail counts [1,2,3,3], radius
5–8, lifetime 0.35–0.75 seconds, and local velocity [150,-12,-15] to
[250,15,15] u/s. Its radius grows from 0.1 to 3 times, and renderers combine
`blood_spray_top`, motion vectors, breakup and a red gradient. It is a
directional animated spray, rather than identical linear red cards.

Representative initializer values, before noise/growth/age curves:

| Child | Capacity | Count at detail 0–3 | Radius (u) | Base lifetime (s) |
|---|---:|---|---|---|
| low_mist_away | 4 | [1,2,3,4] | 7–8 | 0.5–1 |
| med_mist_away | 5 | [2,3,4,5] | 9–12 | 0.5–1 |
| high_mist_away | 3 | [1,2,4,6] | 10–15 | 0.75–1.25 |
| low_vis_spray_trail | 2 | [1,2,3,4] | 16–32 | 0.5–0.65 |
| med_vis_spray_trail | 2 | [1,1,2,2] | 14–20 | 0.5–0.75 |
| high_vis_spray_trail | 2 | [1,1,1,1] | 16–32 | 0.5–0.75 |
| med_vis_spray | 3 | [1,2,3,3] | 11–16 | 0.5–0.7 |
| high_vis_spray | 1 | [1,1,2,2] | 14–20 | 0.5–0.75 |

Emission requests and capacity are distinct, and engine budgets can reduce
visible counts. Medium visible spray uses gravity -250 u/s²; trails/away
spray use -450 with drag 0.05. Manual animation frames have normalized-age
curves. Motion-vector decoding uses the texture's actual encoded channels;
the atlas rectangles/display times are retained in `.sheet.json`.

**Read:** client strings register `blood_impact_light_headshot`, local/victim
roots and friendly blood. Convars name medium 20 and heavy 40. **Inferred:**
damage-band dispatch, root precedence and CP axis sign. A child named
`*_spray_screen` is not automatically a HUD effect; actual screen roots
explicitly set `m_bScreenSpaceEffect`.

## Ground particle splats and persistent wall blood are separate

**Read:** visible-trail parents choose ground children in group 1. Their
emitters use `m_flInitFromKilledParentParticles=1`, and initializers copy
the dead parent's position/previous position. They are **parent-death
projections**, not collision-triggered decal stamps. No
`C_OP_GameDecalRenderer` or collision-event operator appears in the blood
folder inspected.

The ground child offsets upward by 64 units for low, 32 for main medium/high,
and 64 for medium's third alternative. `C_INIT_PositionPlaceOnGround` traces
**256 units** downward; medium/high explicitly set the surface normal.
Low detail counts are [0,0,1,1], while inspected medium variants use
[0,1,1,1]. Base radii are 20–25 for low and 30–40 for main medium/high.
Most live **5–10 seconds**; `med_ground_decalaltb` lives **20 seconds**.
Fade timings belong to each child. Projected materials specify normal
alignment, particle-age input and depths -15 to +5 (main high: -15 to +10).

Separate persistent Blood/Bloodlvl2–6 groups contain 7,7,11,12,10,7 weighted
materials. They have actual dimensions, normal/AO maps, roughness, cutoff
and `F_BLOOD_AGING`. Sample `blood_decals_10_00` is 47.2 by 47.2 units,
depth 10, offset -2; that is not a universal splat size. Complete visual
aging, wall-placement ray range/count and group thresholds remain unverified.

[Current decal convars](https://github.com/SteamDatabase/GameTracking-CS2/blob/6ac247908a83c309b37314fd097c47dc78103746/DumpSource2/convars.txt)
scale from 1 at 256 units to 1.35 at 1536 units. Generic defaults are 2048
decals, fade start 30 seconds and duration 3 seconds. They do not override
each ground particle's own lifetime.

## Body wounds accumulate in character UV space

The [reflected current wound shader](https://github.com/SteamDatabase/GameTracking-CS2/blob/6ac247908a83c309b37314fd097c47dc78103746/game/csgo/shaders_vulkan_dir/shaders/vfx/csgo_decal_renderer.slang)
projects skinned vertices through a hit basis and writes using the second
UV set. Its decal-size parameter defaults to 4, with range 1–32; its vertex
math determines the footprint. The fragment shader reads `BloodDefaultImpact`
and the previous render target, taking the maximum red-impact contribution
in blue and adding green-impact contribution to alpha, scaled by facing.

Extracted `blood_default_impact` is a packed RG mask, with blue zero and
opaque alpha. `blood_default_color` is opaque tiled dark-red tissue; drawing
it directly as a cutout would show a square. `blood_default_normal` is
separate. All three assets are included in the extraction. The complete
character shader's accumulation/aging/material interaction is not reproduced
by a simple bone-following wound projection.

## World impacts and helmet sparks

**Read:** `surfaceproperties_impact_effects.txt` supplies a surface-specific
particle root, optional cheaper root, hole group and optional grazing
group. `decalgroups.vdata` supplies weighted materials. Concrete, metal,
dirt, wood, tile, glass and water have distinct graphs. Missing-field
inheritance and quality/graze dispatch are engine behavior and remain
inferred. Grazing controls are cutoff 0.55 and variance 0.1; their precise
angular use needs a game check.

The recent `impact_fx_hit_darken_model` is a **3D puff** child of shared
darken feedback. It names `impact_puff.vmdl` (four mesh variants) and
`smoke_puff_dirt.vmat`. It requests 1–2 puffs from a distance CP, base
lifetime 0.35–0.55 seconds with an additional distance curve, radius growth
and normal offset. Material DATA exposes color/mask textures and Fresnel
exponent 4.399/falloff 1.909. This transient feedback is separate from the
persistent bullet hole. World flecks use the shipped `flecks3` mesh.

`impact_helmet_headshot` has additive glow/spark children. That proves the
spark asset exists, not that all helmet hits, especially lethal ones,
suppress every blood component.

## PR172 implementation and explicit approximations

Rendering consumes `bullet_damage` hit events and leaves damage decisions
in the simulation. The generated table holds ranges, LOD counts/caps,
age/radius/alpha curves, surface/decal groups and material parameters.
Assets are preloaded before play; no source KV3/DATA is parsed on a tick.

The new implementation uses extracted spray sheets/trails, gradients and
motion-vector interpolation, a bounded 512-particle pool, analytical motion
from event timestamps, real puff/fleck meshes and parent-death ground
projections with the authored 256-unit trace and separate lifetimes.
Persistent world decals use weighted groups, real textures/dimensions and
distance scaling. Helmet feedback and victim-view assets are separate.

The current playtest tuning doubles body-mist emission counts/caps and
halves their sampled lifetimes. Mist starts within one Source unit of the
actual bullet contact point. This applies to remote body mist only;
local-screen reactions, visible spray and ground/persistent decals keep
their own timings. The generated authored table remains unchanged by that
runtime override.

Explicit approximations, not measured current-CS2 equivalence:

- Damage/root precedence, CP assignments and local-view positioning.
- Linear interpolation between curve points instead of Source spline
  tangents; some biases, noise, lighting/shadows and mixed-resolution draws.
- Spritecard texture composition is partial: breakup SUBTRACT/MOD2X
  overlays and UV tiling/distortion are not all reproduced. Gradient
  REPLACE/MULTIPLY and MIX_RGB/MIX_RGBA controls are implemented, while
  other composition paths remain partial. The puff's color/mask and Fresnel
  shader also approximate the shipped material's full shading.
- Motion vectors use the actual green/alpha channels and independent
  frame rectangles. Converting authored -8/-16 renderer overrides to
  pixels in atlas space is inferred; texture header displacement and
  closed-source renderer override units still need direct comparison.
- Unsupported operators remain named in each layer's `unsupported_ops`.
  They include global scale, sequence lifetime, CP alignment, expression
  operators, turbulence, velocity decay and oscillation. A normalized
  field's presence does not prove an identical Source 2 operator.
- Persistent wall blood uses one bounded 172-unit ray behind the victim,
  a Source 1-inspired stand-in rather than a decoded CS2 wallblood rule.
- Body wounds use the actual red impact mask and tiled color in bounded
  bone-following projections, approximating persistent skinned UV2 accumulation.
- Persistent blood respects material fade overrides, with generic decal
  fading as the fallback. Full shader aging and body wound transfer to
  ragdolls still need comparison.
- Blood world projections consume color/normal/AO, width, height and depth;
  roughness, exact offset/cutoff and particle-age shading
  remain partial. Bullet-hole material preparation handles more of those
  parameters than blood projection.
- Surface-to-particle dispatch covers the selected representative graphs,
  not every surface mapping in the source table. Grass, wet/water, carpet,
  plastics and foliage need their additional particle graphs before they
  can use distinct effects; the weighted decal groups are already decoded.

Body hit sounds use authored attacker/victim/onlooker damage/death events
with body/head/armor selection; see [gameplay audio](audio-gameplay.md).
Flinches use 42 extracted additive rifle/pistol/knife clips in separate
head/body layers; [body flinches](body-flinches.md) records timings and
remaining inferred direction/damage-handler behavior.

## Reproduction and remaining checks

Run `scripts/extract_assets.sh impacts` with CS2, Source 2 Viewer and Godot.
It decodes definitions/material DATA under ignored
`assets/effects/impacts/raw/`, resolves dependencies, assembles whole sheets
at original paths under `assets/effects/`, exports only small puff/fleck
models under `impacts/`, and regenerates hit reference/code tables. Three
textures come from the shared Core archive. It never re-exports map or
character materials. Material DATA is readable despite shader V72 preventing
full shader reconstruction. Duplicate atlas rectangles retain all sequences;
a missing unique frame fails extraction.

`character-animations` extracts bullet flinches; `sounds` includes the five
burn-damage files as well as body/head/armor hits. `all` includes impacts.
Missing required material DATA fails before replacing generated tables.
Dependency mode resolves material texture slots without replacing tables;
the extraction stage checks every expected resource against freshly dumped
main/Core texture DATA, then reconstructs frames before writing the tables.
Cached images cannot hide a missing resource in that fresh report.
Table checks cover source input reduction, gradient/motion texture slots,
graph dependencies and distinct ground lifetimes without extracted assets.
Local rendering checks also need real sheets, masks and mesh variants.

The [1080p/4K performance measurements](hit-effects-performance-2026-10-02.md)
record sustained bursts, accumulated marks and the remaining particle CPU cost.
Controlled current-CS2 comparisons remain needed for band boundaries,
helmet/headshot/lethal combinations, local/friendly effects, persistent
wall placement/aging, body wounds, grazing dispatch and detail budgets.
