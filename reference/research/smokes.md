# How CS2's smokes work

Research for roadmap item 20 (the smoke) and Local check G4, written
2026-09-24 from CS2's own files and from community sources. Docs only: no
code or systems page changes with it.

**How each claim is marked.** *Read* means read directly from CS2's shipped
files as SteamDatabase's GameTracking-CS2 publishes them (commit `d45f52d`,
2026-09-23; paths below are in that repository). *Decoded* means worked out
from the smoke shaders, which Source 2 Viewer reconstructs from the game's
compiled SPIR-V: the variable names are lost, so which buffer entry is which
is read from how the code uses it. *Inferred* is a reasoned guess from the
above. *Community* comes from web search summaries, since the pages
themselves (Valve's update page, Dexerto, changelog.gg, Steam) refuse fetches
from the cloud. Nothing here comes from Valve's leaked CS:GO source.

## The short version

- **The server owns the cloud and sends it to everyone.** Each smoke
  projectile carries a networked byte array, `m_VoxelFrameData`, with a size
  and an update counter (*Read*). A server-side `CSmokeVolumeSystem` builds
  it (`SmokeVolume::BuildSmokeSimulation`) as a job, off the tick's own
  thread (*Read*: the function is wrapped in `CCoJobLambda`). That is why
  every player sees the same cloud, and why CS2 has no one-way smokes.
- **The grid is 20-unit voxels, 32 a side, centred on the smoke** (*Decoded*:
  every shader maps a point to `(p - centre) / 20 + 16` in a 32-cell grid).
  So no cloud can reach more than 320 units from its centre in any
  direction. The repo uses 16-unit cubes.
- **Its shape is a squashed torus of ring radius 61 and tube radius 88,
  centred 68 units up** (*Read* convars, *Inferred* use). Those convars are
  flagged for both the server and the client DLL, so they probably shape
  the fill itself, not only the drawing: about 300 units across and about 156
  tall on flat ground, which agrees with CS:GO's 288-unit smoke and
  with the repo's 300 by 130.
- **An HE clears a sphere of about 200 to 240 units, which fills back over
  roughly 0.5 to 5 s** (*Decoded*), against the repo's guess of 128 units for
  3 s. Only HEs that go off at least 0.4 s after the smoke pops count, and
  each HE carries a mask of which smokes it may touch (CS2's fix for HEs
  clearing smoke through walls).
- **A bullet cuts a tunnel about 20 units wide that closes in under a
  second** (*Decoded* width, *Community* time), pushes the smoke along the
  bullet's path, and glows orange along the path for its first moments
  (*Decoded*). At most 16 bullet trails are drawn at once (*Read*).
- **The bomb clears smokes with a wave at 3,000 units a second** (*Decoded*),
  gone for about 1.3 s after the wave passes, and back by about 6.7 s.
- **A fire goes out whole once a third of its flame areas are covered**, at a
  smoke density of 0.03 (*Read*; the round research, PR #58, found the first
  half).
- **Drawing it:** a ray march at 4-unit steps through a 3D texture per smoke
  (all in one 16-slot atlas), lit per voxel from the map's light probes and
  shadows, broken up by two octaves of Worley noise, at half or quarter
  resolution with a full-resolution pass to fill holes (*Decoded*, *Read*).
- **A video's edge-case tests agree** (section 2a): the grid is placed where
  the smoke lands, so small gaps pass or block by luck of alignment; confined
  smokes run into a hard box; a formed cloud does not reflow when a window
  breaks or props move; some invisible tool brushes block smoke.
- **For this repo:** the server-side model (a fill over a coarse grid, a
  density-along-a-line query, holes from HE and bullets) is what #53 already
  built. The numbers to change are the voxel size (20), the 640-unit box,
  the HE hole and the bomb's wave. The trace cost the local agent measured
  is ours, not CS2's: CS2 builds the fill in a job; the options for us are
  below.

## 1. What the server holds

`DumpSource2/schemas/server/CSmokeGrenadeProjectile.h` (*Read*):

| Field | What it is |
|---|---|
| `m_nSmokeEffectTickBegin` | The tick the smoke popped |
| `m_bDidSmokeEffect` | Whether it has popped |
| `m_nRandomSeed` | The seed that shapes the cloud the same for everyone |
| `m_vSmokeColor` | Its tint (the dev-only `smoke_grenade_ct_color` 75,127,155 and `smoke_grenade_t_color` 180,129,50 exist for team-coloured smokes) |
| `m_vSmokeDetonationPos` | Where it popped |
| `m_VoxelFrameData` (a networked `uint8` vector), `m_nVoxelFrameDataSize`, `m_nVoxelUpdate` | The cloud itself, sent to clients, with a counter that goes up when it changes |
| `m_flLastBounce`, `m_fllastSimulationTime` | Server-only: for the "is it still" check |
| `m_bExplodeFromInferno` | Popped at once because it landed in fire |
| `m_bDidGroundScorch` | A scorch decal on the ground |

The client's copy (`schemas/client/C_SmokeGrenadeProjectile.h`) has the same
networked fields plus `m_bSmokeVolumeDataReceived` and
`m_bSmokeEffectSpawned` (*Read*): the client waits for the server's voxels
before it draws.

Functions and names in `game/csgo/bin/win64/server_strings.txt` (*Read*):

- `CSmokeVolumeSystem` (a game system), `SmokeVolume::BuildSmokeSimulation(
  CSmokeGrenadeProjectile*, const VectorWS&, CFixedSizeCircularBuffer<VectorWS,16>&, float)`,
  run inside a `CCoJobLambda` (a job). What the ring of 16 positions is, is
  not said; the client keeps a ring of 16 bullet trails per smoke (below),
  so it may be recent bullet paths, or recent bounce points (*Inferred*,
  unsettled).
- `SmokeVolume::RebuildVoxels(const AABB_t&)`: rebuilds the voxels inside a
  box. What calls it is unknown: in the video in section 2a, neither a
  broken window nor moved physics props reshaped a formed cloud.
- `SmokeVolume::GetSmokeDensityInLine(start, end, …)` (public) and
  `GetSmokeDensityLOS` (private): how much smoke a line crosses. The same
  two appear in the client DLL, so client and server share this code.
- `CBotManager::IsLineBlockedBySmoke`, `IsVisibleThroughSmoke`,
  `CBtDecoratorPickerBlockedBySmoke`, `SmokeGrenadeDetonateEvent@CCSBotManager`:
  the bots' use of it; `bot_max_visible_smoke_length 200`.
- The thinks `CSmokeGrenadeProjectileThink_Detonate`, `…_BuildingSmokeVolume`,
  `…_Update`, `…_Remove`: pop, build over time, update, remove.
- `Dense voxels` and `Sparse voxels`, `voxel_size`: two storage forms and a
  size setting, their values not in the strings.
- `SmokeVolume: Failed to find detonation`: the build can fail to find a
  starting point.
- `Molotov extinguished: when %d/%d fire areas were covered by smoke
  (exceeded 1/3rd).` and `inferno_smoke_volume_density 0.03`: a flame area
  counts as covered where the density is over 0.03.
- `sv_throw_smokegrenade`, `sv_explode_smokegrenade_at_crosshair`: dev tools.
- The events `smokegrenade_detonate` and `smokegrenade_expired` carry
  `userid`, `entityid`, `x`, `y`, `z` (`game/csgo/pak01_dir/resource/mod.gameevents`).
  `player_death.thrusmoke` and `CMsgPlayerBulletHit.through_smoke`
  (`Protobufs/cs_gameevents.proto`) mark kills and hits through smoke.

Not found: any `sv_` convar for the smoke's size, duration or growth. The
only replicated ones are below, all development-only.

## 2. The shape, the fill and its life

**The convars** (`DumpSource2/convars.txt`, *Read*; all `developmentonly`,
so a player cannot change them):

| Convar | Value | Flags |
|---|---|---|
| `cl_smoke_torus_ring_radius` | 61 | gamedll clientdll replicated |
| `cl_smoke_torus_ring_subradius` | 88 | gamedll clientdll replicated |
| `cl_smoke_origin_height` | 68 | gamedll clientdll replicated |
| `cl_smoke_edge_feather` | 21 | gamedll clientdll replicated |
| `cl_smoke_lower_speed` | 1 | gamedll clientdll replicated |
| `smoke_param1` … `smoke_param5` | 6.26, 8.27, 0.13, 0, 0 | gamedll clientdll replicated |
| `smoke_use_noise_texture` | true | gamedll clientdll replicated |
| `cl_smoke_volume_growth` | 1 | clientdll |
| `smoke_volume_lod_ratio_change` | 0.6 | clientdll |
| `sv_smoke_volume_blind_start` | 0.2 | clientdll |
| `cl_use_prompt_smoke_density` | 0.03 | clientdll: the use prompt hides above this density at your eyes |

The round research read the torus convars as the drawn cloud only. Their
`gamedll` flag says the server reads them too, so the fill probably aims at
that shape (*Inferred*). A torus whose tube (88) is wider than its ring (61)
closes over its hole: a rounded, flattened blob. From 68 units up it reaches
61 + 88 = 149 units out and 88 units up and down, so about 300 across and,
on flat ground where the bottom is cut off by the floor, about 156 tall. What
`cl_smoke_lower_speed` does (a slow sinking, perhaps) and the three
`smoke_param` numbers mean is not in the strings.

**The grid** (*Decoded*). Every smoke shader turns a point into a cell with
`(p - centre) * 0.05 + 16`, clamped to 0 to 31: cells of 20 units, 32 a side,
640 units across, centred on the smoke. The client's per-smoke lighting pass
writes one value per cell at `(index - 16) * 20 + 10` from the centre, the
cell's middle. That the server's `m_VoxelFrameData` uses the same 20-unit
grid is *Inferred* (it is what the client uploads into that texture); a
32 x 32 x 32 grid is 32,768 cells, so a byte per cell, or less in the
"sparse" form, is small enough to send.

How the fill spreads is not in any published file. The community
recreations (Acerola's, below) use a limited flood fill: the landing cell
starts with a budget that falls by one per step into each open neighbour.
The repo's search, nearest first with going up costing more, is the same
idea with a rounder result. Nothing public says whether CS2 traces between
cells as the repo does or reads a pre-built map of open cells: a
`VoxelOctree::Voxelize` is in the server DLL, but beside the nav mesh
builder's voxel code, so it may be theirs.

**Growing** (*Decoded*, *Inferred* meaning). For a smoke's first second the
depth pass samples the grid at up to twice the distance from the centre,
easing to one, so the drawn cloud grows from half size to full. The
community timing is about 1 s to full (Swap.gg, bo3.gg).

**Lasting and going** (*Decoded* shape, *Community* timing). Near the end,
the main shader keeps only a sphere around the centre that shrinks from
about 0.95 of the box's half-width towards nothing (height counted 1.2
times, so it thins from the top and bottom faster), so a smoke dissipates
from its edges inwards. The duration is still disputed: most sources say
18 s from the pop with the last few seconds thin ("about 15 seconds of
strong cover"), one says about 20 (Swap.gg, csdb.gg, bo3.gg; the round
research has the same split). G4 settles it by timing `smokegrenade_detonate`
to `smokegrenade_expired` in a demo.

## 2a. What a video's tests show

Sid pasted the transcript of a YouTube video (youtube.com/watch?v=4xG4No0-y9w;
the channel isn't named in the transcript) that tests CS2's smokes in a
custom map built for it. It credits Acerola's recreation and focuses on edge
cases. What it found, in its own words where quoted, with how each finding
sits against the files (*Video* marks the claim):

- **The grid is placed where the smoke lands, not on a world grid.** Three
  throws at slightly different spots between two holes in a glass tube gave
  four different results: a tidy "smoke sausage" inside the tube, a cloud
  out of one hole, the tube's solid part filled, a cloud out of the other
  hole. The video's explanation is that the voxels are large and offset by
  the landing point, so whether a gap one voxel wide lets smoke through
  depends on how the grid happens to line up with it (*Video*). This
  agrees with the shaders, whose grid is centred on each smoke's
  `m_vSmokeDetonationPos` (*Decoded*), and the repo already anchors its
  grid the same way (`SmokeVoxels.anchor`).
- **Its guess of "20 across perhaps, about 8,000 cubes"** is a guess; the
  shaders put the box at 32 cells of 20 units, and how many are filled is
  still G4.
- **Smoke shows through glass beside a hole before it reaches the hole.**
  The video asks whether that is drawing or spreading. The drawing explains
  it: the grid is sampled with trilinear filtering (`g_sTrilinearClamp`),
  so a filled 20-unit cell bleeds up to a cell's width past a thin wall
  (*Inferred*).
- **In a confined space the smoke travels further, up to a hard limit.**
  Narrower corridors push it further, then it stops abruptly, which the
  video draws as "a big invisible cube around the smoke grenade" (*Video*):
  the 640-unit box (*Decoded*). So the fill keeps a fixed amount of smoke
  and spends it further along a narrow way, as the repo's does, but CS2's
  limit is the box, not a distance along the path.
- **Too confined, it breaks the rules.** With little room it sometimes
  passes straight through a side wall, and in a thin corridor it can appear
  at the far end but not in the gap between (*Video*). Neither follows from
  a plain flood fill; the video offers no cause and nor do the files.
- **Inside a solid, it fills the solid.** A smoke that goes off inside a
  surface treats the inside as empty space and sometimes spills out too;
  one below the ground lays a layer of fog over it (*Video*). Not something
  play reaches, but it says the fill does not check whether its start is
  inside geometry.
- **Props block like walls.** Trees and prop walls stop it; a row of trees
  with gaps is impassable because the gaps are narrower than a voxel
  (*Video*).
- **Some invisible tool brushes block it.** The video names four that do:
  "solid", "block light", "block bullets", and a fourth the captions garble
  ("layer on trol lip"; possibly a player-control clip). Others, such as
  plain player clip, let it through (*Video*; the list of which do not is
  not given in full). `TOOLS/TOOLSBLOCKBOMB` and `csgo_grenadeclip` are in
  `server_strings.txt` (*Read*) but the transcript does not say either blocks.
- **Once formed, the cloud does not reflow.** After shooting out a window
  next to a smoke only "the billowy wafts" pour through, not the cloud's
  body; moving physics props after it has formed changes nothing (*Video*).
  So the shape is fixed when the build ends, and the wisps are the
  drawing's noise sampled past the old edge (*Inferred*).
- **Its complaints:** fire is not reliably put out, and player shadows can
  show through smokes (*Video*; the second is the lighting's, section 4).

For this repo: the grid anchored at the landing point is CS2's behaviour,
not a flaw to fix; the box limit is new; and which of dust2's tool brushes
block smoke is a Local question (section 9), since the importer's hull
decides what the fill traces against.

## 3. What changes it

**Bullets** (*Decoded* from `smoke_volume.slang`'s pixel shader). The smoke
constants hold up to 16 bullet trails (start, end, age, width); the client
keeps them in a `CFixedSizeCircularBuffer<SmokeVolumeBulletTrail_t,16>`
(*Read*). For each sample in the smoke:

- inside a tunnel of radius 20 units (divided by a per-trail width factor)
  round the bullet's segment, the density is sampled from a point pushed
  along the bullet's direction by up to 20 units, so the smoke looks shoved
  through, not just cut;
- the push fades as the trail ages and near the far end;
- for the trail's first moments (its age from 0.01 to 0.2 on its own scale)
  the smoke along it is brightened orange (the colour times 8, 4, 0): the
  bullet's heat.

Community tests: holes "close very quickly, in less than a second", and a
stream of shots keeps one open (cs.money's mythbusting, Dexerto). Whether a
bullet's tunnel exists on the server too, so that a bot or
`GetSmokeDensityInLine` sees through it, is unknown: the trail buffer is
only in the client DLL, and the server's ring of 16 positions is the only
hint. Measurable (section 7).

**HE grenades** (*Decoded*, in the pixel and depth shaders alike). Up to 5
recent explosions (`CFixedSizeCircularBuffer<SmokeVolumeHEGrenadeTrail_t,5>`,
*Read*), each a position and a time, and a per-HE bitmask of which of the
16 smoke slots it may touch. For a smoke sample within 250 units of one:

- it counts only if the HE went off at least 0.4 s after the smoke started;
- samples 100 to 250 units out are displaced towards the blast, on the
  far side of a front that moves out at 1,250 units a second: the push;
- the density drops to 2% inside about 200 units, rising to full by 240;
  the hole opens over its first 0.2 s or so (for that moment every point
  counts as 250 units further out);
- it comes back as `smoothstep(0.5, 5.0, t)` to the power 1.8: nothing for
  half a second, half back after about 3 s, all of it at 5 s.

Community: "a massive gap … for about 2-3 seconds before it re-expands"
(cs.money). The Limited Test notes of 2023-03-30 said HEs "no longer affect
smokes through walls" (Sportskeeda, from the round research): the bitmask
is where that lands in the drawing, so the server decides which smokes an
HE reaches, probably by a trace (*Inferred*). Whether the server's density
drops too, which decides bots and the kill feed's `thrusmoke`, is
unconfirmed.

**The bomb** (*Decoded*, one position and time in the constants). A front
moving out at 3,000 units a second; behind it the density falls to 2%, stays
there until the front is 4,000 units past (about 1.3 s), and is fully back
when it is 20,000 units past (about 6.7 s). Only smokes that started before
the blast are touched. Valve added this on 2026-07-20 ("the C4 explosion now
disperses active smoke clouds and extinguishes molotov/incendiary fire",
Insider Gaming, skin.club, dust2.us).

**Fire**: a smoke that lands in fire pops at once (`m_bExplodeFromInferno`);
a fire goes out whole once more than a third of its flame areas are in
smoke denser than 0.03 (*Read*); a fire started in smoke fizzles
(`CInferno.m_bWasCreatedInSmoke`, round research). 2025 notes also fixed
overlapping smokes putting fires out early (esports.gg summary).

**Decoys**: the 2023-11-02 update said decoys "interact aesthetically with
smoke clouds" (Escorenews). One summary adds that an enemy decoy makes the
smoke briefly see-through; no second source, so treat that as unconfirmed.
Most likely the decoy's fake shots draw bullet trails (*Inferred*).

**Nothing else**: molotovs, flashes and thrown objects do not move the smoke
(cs.money tested them).

## 4. How it is drawn

All *Decoded* from `game/csgo/shaders_vulkan_dir/shaders/vfx/smoke_volume*.slang`
and `overlay_smoke.slang`, with names from `client_strings.txt` (*Read*).
This is the client's business only; nothing here decides the game.

1. **Upload.** Each smoke's grid goes into one slot of a shared 3D texture
   atlas (`SmokeVolumeTexA_Atlas`): 16 slots of 32 cells with 2 cells of
   padding, 542 wide. Four channels, read as two pairs blended by a
   per-smoke factor: most likely the last two server updates, blended so
   the cloud changes smoothly between them (*Inferred*).
2. **Lighting per cell** (`smoke_volume_lpv.slang`, a compute pass): for each
   20-unit cell, the map's baked light probes (`LPV_Irradiance`), its direct
   shadows (`LPV_DirectShadows`) and its lights (`BarnLights`), into a second
   atlas (`SmokeVolumeLPV_Atlas`). Smokes cast shadows since 2024-07
   (siege.gg; `r_csgo_smoke_shadow`, `ParticleShadowBuffer`).
3. **Mask** (`smoke_volume_mask.slang`): each smoke's box drawn as an
   instanced cube, marking per pixel which smokes it crosses (a bitmask,
   `D_DDA_MASK`).
4. **Ray march** (`smoke_volume.slang`): per pixel, from where the ray enters
   the box to the scene's depth, samples every 4 units (`g_flRayStepLength`
   4), front to back, stopping at 99.1% opacity. Each sample: the density
   (after bullet and HE changes), two octaves of Worley (cellular) noise at
   2.3 and 6 cycles per 100 units drifting over time (weights 0.6 and 0.28
   plus 0.12), the cell's light, a sun term from the direction out from the
   smoke's centre, and the tint blended in by luminance.
5. **Resolution**: at half or quarter resolution with moment-based
   order-independent transparency (`MBOIT(%d) Smoke 1/2`, `1/4`, `Full`),
   then a full-resolution pass "to cover holes and artifacts"
   (`r_csgo_smoke_fullres_pass`), and an upscale.
6. **Depth** (`smoke_volume_depth.slang`): where the accumulated density
   passes 1, a depth is written (dithered with blue noise), so effects and
   the sniper scope (`r_csgo_smoke_clip_sniper`) treat thick smoke as solid.
7. **Inside it** (`overlay_smoke.slang`, `SmokeOverlayDataA/B`): a screen
   overlay once the density at your eyes passes 0.2
   (`sv_smoke_volume_blind_start`); bloom is off while smoked
   (`r_csgo_effects_bloom_when_smoked false`).

Also in the client: `Unable to render more than %d smokes.` (the atlas's 16,
*Inferred*), `Cannot record demos while a smoke grenade is active.`, and the
May 2025 hotfix for seeing players' outlines and fire through smokes with
anti-aliasing off (dust2.us), which shows how much of the smoke's fairness
rests on the drawing.

## 5. Sight

- **Players** see what is drawn, and everyone draws the same voxels.
- **Bots** see through at most 200 units of smoke
  (`bot_max_visible_smoke_length`), measured by the shared
  `GetSmokeDensityInLine` (*Inferred* from the names).
- **The kill feed** marks `thrusmoke`; the server's bullet-hit message marks
  `through_smoke`.
- **The radar**: community sources say a smoke blocks the radar for about
  15 s (bo3.gg); nothing in the files confirms it.

## 6. History (Community, from search summaries)

| Date | Change |
|---|---|
| 2023-03-22 | CS2 announced: smokes are "dynamic volumetric objects that interact with the environment, and react to lighting, gunfire, and explosions", "expand to fill spaces", "all players see the same smoke" |
| 2023-03-30 | HE grenades no longer affect smokes through walls |
| 2023-11-02 | Decoys interact with smoke clouds |
| 2024-07 | Smokes cast shadows; their animation and rendering improved |
| 2025 | Overlapping smokes drawn correctly; overlapping smokes no longer put fires out early |
| 2025-05-08 | Fixed players' outlines and fire showing through smokes with anti-aliasing off |
| 2026-07-20 | The bomb's blast disperses smokes and puts out fires |

esports.gg also mentions a July 2024 "utility pass" and a January 2026
"smoke re-tune" with win-rate effects; no other source names them, so they
are left out of the table.

## 7. Against the repo's guesses

The repo's numbers are in `src/grenades/grenade_rules.gd` and
`reference/systems/grenades.md`.

| Repo | CS2 | Verdict |
|---|---|---|
| 16-unit cubes (`SMOKE_VOXEL`) | 20-unit cells | **Change to 20** (*Decoded*) |
| No box limit; `SMOKE_REACH` 400 along the path | A 640-unit box round the centre (±320), which confined smokes run into (the video) | **Add the box**; the reach can stay as the flow limit |
| The grid anchored where the grenade stopped | The same: small gaps pass or block depending on the landing spot (the video) | Keep |
| 1,600 cubes (6.6 million cubic units) | Not published; the torus shape is about 300 x 156 in the open | **Measure** (G4: the cloud's size in the open) |
| A dome from a nearest-first search, up costs 1.25, down 0.8 | A torus 61/88 centred 68 up | **Aim the fill at the torus shape** (*Inferred*) |
| Grows over 1 s | About 1 s, drawn from half size | Keep |
| 18 s | 18 s (most) or about 20 | **Measure** (G4) |
| Holes: HE 128 units for 3 s | About 200 to 240 units, back over 0.5 to 5 s; HEs 0.4 s after the pop or later; only smokes the HE reaches | **Change** (*Decoded*); whether the server's density changes too: measure |
| Tunnels close in 0.25 s | Under a second, 20 units wide, pushed along the bullet | **Roughly right**; widen; server side unknown |
| Fire: flames go out one by one | The whole fire, once a third is covered at density 0.03 | **Change** (PR #58 found it) |
| The bomb: nothing | Clears with a 3,000 u/s wave, back by about 6.7 s | **Add** (with the bomb's blast) |
| Bots: 200 units | 200 units | Keep |

## 8. What it means for the build here

**The server side stays as #53 built it**, with the numbers above. CS2 sends
the cloud as data, not as a seed for each client to rerun, so a client does
not need the fill code: the view reads the server's cells, as the
contract already has it.

**The cost the local agent measured** (about 2,400 traces a smoke in its
first second, 2.6 to 2.8 ms on the worst tick with three smokes) is our
design's, not a CS2 figure. Three ways to cut it, cheapest to build first:

1. **Trace lazily** (the review notes' version): a neighbour is traced only
   when it comes off the heap. Same cloud, fewer traces.
2. **20-unit cells instead of 16**: about half as many cells for the same
   volume (1.95 times fewer), so about half the traces, and CS2's size.
3. **A map-wide grid of open cells built once**, when the map loads or on
   first use (never read from disk during a tick): each cell's six links
   traced once for the whole map, after which every smoke's fill is array
   lookups and no traces. dust2's playable space at 20 units is a few
   hundred thousand cells, so this is a one-off cost at load and some
   memory; the links through `allowsmokethrough` surfaces are part of it.
   CS2 builds its fill in a job off the tick; Godot's
   `WorkerThreadPool` could do the same with option 1, but the physics
   space is not safe to query off the main thread without care, so option
   3 is the cleaner way to take the cost off the tick.

None of these is started; Sid has not given the go on the smoke fix.

**Drawing it in Godot 4.7** (the thread's reading of Godot, not measured):

- A `FogVolume` with a fog shader sampling the smoke's cells as an
  `ImageTexture3D` is the least code, but Godot's volumetric fog is drawn in
  coarse screen-space cells (froxels), so a 20-unit bullet tunnel would blur
  away. Fine for a first look.
- A box per smoke with a ray-marching spatial shader, sampling a 32 x 32 x 32
  `ImageTexture3D` (or one atlas for all smokes, as CS2 does), is the
  closest match: 4-unit steps, the HE and bullet uniforms as CS2 passes them,
  Worley noise, and front faces culled so it still draws from inside.
- CS2's half-resolution march and full-resolution fill-in would need a
  `CompositorEffect`; worth it only if the box shader costs too much.

**Recreations to read, not copy** (none has a licence, so all rights are
reserved): Acerola's video "I Tried Recreating Counter Strike 2's Smoke
Grenades" (youtube.com/watch?v=ryB8hT5TMSg) and its Unity code
(github.com/GarrettGunnell/CS2-Smoke-Grenades: flood fill, voxelizer, ray
marcher, tiled Worley noise); TsingLoo/Smoke-CS2 (Unity URP, no scene
voxelizing); lolgube010/DX11-TGA-Portfolio-CS2-Smoke (DX11). They are
guesses at CS2 like ours; the shader numbers above are closer to the game.

## 9. What a Local check would settle

Most of this is one local server with `sv_cheats 1` and a demo parsed with
demoparser2 (MIT), as the combat research proposes:

| Question | How |
|---|---|
| Duration (18 or 20 s) | Time `smokegrenade_detonate` to `smokegrenade_expired` |
| The cloud's size in the open, and its height | A smoke on flat ground, walk out to its edge; or screenshots from above with `cl_drawhud 0` |
| Whether HE holes and bullet tunnels exist on the server | A bot behind a smoke: does it see and shoot you through a fresh HE hole, or a tunnel you keep open? And does a kill through the hole carry `thrusmoke`? |
| The HE hole's size and refill | An HE into a smoke, filmed from outside at a known distance |
| The torus convars' effect on the fill | With `sv_cheats 1`, change `cl_smoke_torus_ring_radius` and see whether the cloud's shape changes for a second client (it is replicated) |
| Which tool brushes block smoke on dust2 | The video found four that do; list dust2's tool brushes from the extraction and throw a smoke against each kind on the range copy |
| Whether the fill traces or reads a pre-built grid | Not measurable from outside; not needed |

## Sources

- SteamDatabase, GameTracking-CS2, commit `d45f52d` (2026-09-23):
  `DumpSource2/schemas/server/CSmokeGrenadeProjectile.h`,
  `DumpSource2/schemas/client/C_SmokeGrenadeProjectile.h`,
  `DumpSource2/convars.txt`, `game/csgo/bin/win64/server_strings.txt`,
  `game/csgo/bin/win64/client_strings.txt`,
  `game/csgo/shaders_vulkan_dir/shaders/vfx/smoke_volume.slang`,
  `smoke_volume_depth.slang`, `smoke_volume_lpv.slang`,
  `smoke_volume_mask.slang`, `smoke_volume_cs.slang`, `overlay_smoke.slang`,
  `game/csgo/pak01_dir/resource/mod.gameevents`,
  `Protobufs/cs_gameevents.proto`, `Protobufs/te.proto`
  (github.com/SteamDatabase/GameTracking-CS2).
- Valve's announcement, as quoted by counterstrike.fandom.com and
  counter-strike.net/cs2 in search summaries.
- cs.money, "Mythbusting CS 2 smokes" (cs.money/blog/news/mythbusting-cs-2-smokes/).
- Dexerto, "All smoke changes in Counter-Strike 2".
- Swap.gg, "How long does smoke last in CS2"; bo3.gg, "How long do CS2
  grenades last"; csdb.gg grenade guide.
- siege.gg, "New CS2 update brings a big change to the smokes" (shadows,
  2024).
- Escorenews, "CS2 update … adds decoy interaction with smoke" (2023-11-02).
- dust2.us, "CS2 May 5/8 update quickly patches new smoke bug" (2025).
- Insider Gaming, "CS2 update adds bomb interaction with smokes and
  molotovs"; community.skin.club, "C4 now affects smokes and fire" (2026-07).
- esports.gg, "Every major CS2 update explained" (2025 overlap fixes).
- A YouTube video testing CS2's smokes in a custom map
  (youtube.com/watch?v=4xG4No0-y9w), from the transcript Sid pasted into
  the project on 2026-09-24.
- This repo: `reference/research/round-bomb-grenades.md` on PR #58 (fire and
  smoke, the 2023-03-30 note); `/mnt/project-files/reviews/local-review-notes.md`
  (the trace count).
