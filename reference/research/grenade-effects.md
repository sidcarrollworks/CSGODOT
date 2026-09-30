# What CS2 draws for its grenades

Research for playtest issue 19's effects (`reference/playtest-2026-09-25.md`,
plan step 6), written 2026-09-30. It says which effect CS2 plays for each
grenade and when, how the flashbang's white-out and afterimage are drawn, what
the fire's ground shader does, and what Valve has changed about grenade visuals
and when. It ends with what Sid extracts on his machine (plan step 7) and what
to check in CS2. Docs only: no code changes with it.

**How each claim is marked.** *Read* means read from CS2's shipped files as
SteamDatabase's GameTracking-CS2 publishes them (origin/master `ce2a2de`,
2026-09-28, build 2000919). The paths below are in that repository, with
these short names:
- `pak`: `game/csgo/pak01_dir.txt`, the listing of every file in the game's
  main archive (names and sizes only);
- `cl` and `sv`: `game/csgo/bin/win64/client_strings.txt` and
  `server_strings.txt`, the strings in client.dll and server.dll;
- `schema`: `DumpSource2/schemas/`;
- `cvars`: `DumpSource2/convars.txt`.

*Decoded* means worked out from a shader that Source 2 Viewer reconstructs
from the game's compiled SPIR-V (`game/csgo/shaders_vulkan_dir/shaders/vfx/`).
The variable names are mostly lost, so which input is which is read from how
the code uses it. *Inferred* is a reasoned guess from the above. *Valve* is a
dated release note; *Community* is anything else from the web. Steam, HLTV and
the changelog sites refuse fetches from the cloud, so every *Valve* and
*Community* line here comes from search-engine summaries, and the wording is
not verified. Nothing here comes from Valve's leaked source.

GameTracking lists the particle files (`.vpcf_c`) but does not decompile them.
Their operators (counts, sizes, lifetimes, colours, children) need Source 2
Viewer on Sid's machine, the same way the muzzle flashes were done
(`reference/weapons/effects.md`). So this page names every effect and says when
it plays; the numbers inside each effect come with step 7.

## The short version

- **Every grenade effect is a particle system, except two screen passes.** The
  flashbang's white-out and afterimage is one full-screen shader, and the
  fire's charred ground is another. Both are decompiled in GameTracking and
  decoded below (sections 4 and 5).
- **The server chooses which explosion plays, and the client plays it.** Every
  grenade projectile networks the effect, its start tick and its origin
  (section 1). The choice between the HE's variants (plain, dirt, snow, water)
  is therefore made on the server. The rule it uses is not in GameTracking.
- **Only the root effects are named in code.** Children (debris, smoke, sparks,
  lights, decals) are reached from inside their parent's `.vpcf`, so the tree
  under each root is known only by file name until the decompile.
- **The flash's white is added to the screen, not blended over it, and the
  afterimage is a frozen copy of the view.** The shader adds a white amount and
  four times a darkened copy of the frame taken when the flash hit. Each has
  its own fade. Ours blends white over the screen and has no afterimage.
- **The fire's ground turns dark in a noisy patch that outlives the flames.**
  Within 50 units of any flame the patch is full, and it is gone by 100 units.
  It fades in over the first second and stays full until 6 s after the fire
  started, then fades out by 20 s. The flames are particles fed with the
  server's flame points.
- **No grenade leaves a trail in flight, except the burning molotov and
  incendiary.** The coloured trajectory lines are a practice and spectator
  feature, drawn by the client from its own record of the path.
- **Only the HE has a light of its own by file name.** The others may carry a
  light inside their `.vpcf`, which the decompile will show.

## 1. How CS2 plays a grenade effect

- **The projectile carries the effect.** Server and client projectiles both
  have `m_nExplodeEffectIndex` (a handle to a particle system),
  `m_nExplodeEffectTickBegin` and `m_vecExplodeEffectOrigin`, networked
  (*Read*: `schema/server/CBaseCSGrenadeProjectile.h`,
  `schema/client/C_BaseCSGrenadeProjectile.h`; the network vars at `sv` 3850,
  4401, 5004 and `cl` 5274, 5847, 6449). The client keeps
  `m_bExplodeEffectBegan` to play it once. So the server picks the explosion
  and its tick, and every client plays the same one at the same place
  (*Inferred* from the fields).
- **Strings name roots only.** Each DLL's particle paths sit in one
  alphabetical run (`cl` 37030-37130, `sv` 29140-29200). Neighbours in that run
  say nothing about which code uses a name. No `_child`, `_debris` or
  `_smoke_*` file appears in either DLL (*Read*, by their absence), so the
  children are named inside their parent's `.vpcf` (*Inferred*).
- **A name in `sv` means the server sends that effect.** A name only in `cl`
  means the client starts it on its own, from state it already has (*Inferred*).
  Root effects named by both are the explosions, the decoy's shot and the
  molotov's flight and broken glass. The decoy's ground effect is client only.
  The molotov's and incendiary's ground bursts, and the extinguish, are server
  only.
- **A second place names effects: `scripts/explosion_types.vdata`.** Its class
  `CExplosionTypeData` holds `m_SoundName`, `m_ParticleEffect`,
  `m_bIsIncindiary`, `m_bHasForces` and `m_DecalType`, whose default is
  `"Scorch"` (*Read*: `schema/client/CExplosionTypeData.h`; the file at `pak`
  87736, 2379 bytes; `sv` 21929 names it as a VData choice). Its contents are
  not in GameTracking. It may be where the HE's surface variants are chosen
  (*Inferred*); the extraction reads it as text (section 8).

### Which of our events plays what

Our events are CS2's (`src/game/game_events.gd`). What each one should start,
for plan step 8 (*Inferred*, from the names and the fields above; the root
effects themselves are *Read*):

| Our event or state | Effect in CS2 |
|---|---|
| Holding a molotov or incendiary | `weapon_molotov_held` or `weapon_incend_held`, and `_fps` / `weapon_molotov_fp*` in first person |
| Pulling the pin, throwing | `weapon_grenade_pin`, `weapon_grenade_spoon`, probably from the clips' particle events (section 2.6) |
| A molotov or incendiary in flight | `weapon_molotov_thrown` or `weapon_incend_thrown`, and `incgrenade_thrown_trail` |
| `hegrenade_detonate` | One of `explosion_hegrenade_brief`, `_dirt`, `_snow`, or `explosion_basic_water` |
| `flashbang_detonate` | `explosion_flashbang` |
| `smokegrenade_detonate` | `explosion_smokegrenade` (the burst; the cloud is the voxel volume) |
| `molotov_detonate` on the ground | `molotov_explosion` or `incendiary_explosion`, and `molotov_broken_glass` |
| A molotov that goes off in the air | `explosion_molotov_air` or `explosion_incend_air` |
| `inferno_startburn`, while burning | `molotov_groundfire` or `incendiary_groundfire`, flames per point, the smoke above, the ground pass |
| `inferno_expire` | `molotov_groundfire_remnant` |
| `inferno_extinguish` | `extinguish_fire` (smoke), `extinsguish_fire_blastout_01` (the bomb) |
| A player standing in fire | `molotov_bodyburn` |
| `decoy_started` | `weapon_decoy_ground_effect` |
| `decoy_firing` | `weapon_decoy_ground_effect_shot` |
| `decoy_detonate` | `explosion_basic` |
| `player_blind` for the viewer | The flash overlay (section 4) |

## 2. The effects per grenade

Sizes are the `.vpcf_c` sizes in bytes from `pak`. "Named by" says which DLL
names the file.

### 2.1 HE grenade

| When | Root effect | Its children, by file name | Named by | Evidence |
|---|---|---|---|---|
| Blast, default | `explosion_hegrenade_brief` (4117) | `_brief_debris`, `_debris_small`, `_decal`, `_distort`, `_embers`, `_flash_ana`, `_heattrails`, `_smoke_blasts`, `_smoke_core`, `_smoke_ground` | both | *Read*: `cl` 37050, `sv` 29153, `pak` 85191-85201 |
| Blast on dirt or sand | `explosion_hegrenade_dirt` (4224) | `_dirt_blasts`, `_burst_core`, `_bursts`, `_core`, `_debris`, `_debris_small`, `_debris_trails`, `_fallback`, `_fallback2`, `_ground`, `_particulate`, `_particulate_trails`, `_smoketrails` (+`_child`, `_rope`), `_top`, `_trails`, `_upward_collision_check` | both | *Read*: `cl` 37051, `sv` 29154, `pak` 85205-85223 |
| Blast on snow | `explosion_hegrenade_snow` (4432) | the dirt set, plus `_snow_distort`, `_snow_flakes` | both | *Read*: `cl` 37052, `sv` 29155, `pak` 85240-85260 |
| Blast in or over water | `explosion_basic_water` (4444) | 12 `explosion_basic_water_*` files (colliders, foam, ripples, silt, lingering smoke, trails) | both | *Read*: `cl` 37047, `sv` 29150, `pak` 85050-85061 |
| Water, HE's own | `explosion_hegrenade_water` (3367) | 28 files: blobs, columns, cores, drops, fish, ripple, splashes, bubbles, foam, and others | neither | *Read*: `pak` 85266-85293 |
| Shared parts | `explosion_hegrenade` (4349) | `_debris`, `_distort`, `_dust_motes`, `_embers`, `_flash01b`, `_flash02b`, `_flash_ana`, `_heattrails`, `_interior` (+`_fallback`), `_light` (2640), `_decal` (2990), `_smoke_*`, `_smoketrails*`, `_sparktrails*`, `_trails` | neither | *Read*: `pak` 85190-85239, 85261-85265 |
| Dirt on your screen, close by | `explosion_screen_hegrenade_dirt` (2336) | none | neither | *Read*: `pak` 85302; when, *Inferred* from the name |
| Through a smoke | the voxel volume, not a particle | the client keeps a ring of five `SmokeVolumeHEGrenadeTrail_t` | client | *Read*: `cl` 4530; `reference/research/smokes.md` has the hole |

Which variant plays where is not in any file read (*Inferred*, open). `_brief`
is the only HE root without a surface in its name. The likeliest rule is:
`_brief` on hard surfaces and in the air, `_dirt` or `_snow` by the surface
under the blast, and water under or at water. Dust2's sand would then be
`_dirt`. The `_upward_collision_check` children suggest the effect traces
upward to shorten its plume under a ceiling, and `_interior` suggests an
indoor version (*Inferred*). `explosion_types.vdata` and the decompiled roots
should settle it. Failing that, it is a look in CS2 (section 9).

The `particles/entity/env_explosion/explosion_hegrenade_a` to `_h` set (`pak`
84935-84945) belongs to the map's explosion entity, not the grenade
(*Inferred*). Leave it out.

### 2.2 Flashbang

| When | Effect | Children | Named by | Evidence |
|---|---|---|---|---|
| The pop | `explosion_flashbang` (3532) | none share its name; it almost certainly uses the generic `explosion_child_*` set (`_flash01b`, `_flash02b`, `_sparks01`, `_smoke*`, 72 files) | both | *Read*: `cl` 37049, `sv` 29152, `pak` 85189 and 85113-85184; which children, *Inferred* |
| The white-out | `materials/effects/flashbang_overlay/csgo_flashbang_overlay.vmat` | | client | *Read*: `cl` 35602, `pak` 16861; section 4 |
| Unknown | `materials/effects/flashbang_white.vmat` (2409) | | neither | *Read*: `pak` 16862 |

No DLL string names `flashbang_white.vmat`, so it is probably not the white-out
(*Inferred*). It may be a leftover, or a particle's material. The decompile
tells (section 8). `materials/particle/flash_bang.vtex` (`pak` 30610) is a
particle texture, probably the pop's (*Inferred*).

Since 2026-04-30 the pop's sprites fade when the flash is fully hidden from
you behind a wall (*Valve*, section 6).

### 2.3 Smoke grenade (the particles, not the cloud)

The cloud itself is the smoke volume shader drawing the server's voxels
(`reference/research/smokes.md`; plan step 9). The particles here are the
burst and its dressing.

| When | Effect | Variants and children | Named by | Evidence |
|---|---|---|---|---|
| The pop | `explosion_smokegrenade` (2644) | `_init`, `_distort`, `_refract`, `_voxel` (6131), `_adaptive`, `_simulated`, `_fallback`; team tints `_ct`, `_t` | both | *Read*: `cl` 37053, `sv` 29156, `pak` 85305-85321 |
| CS:GO's sprite smoke | `explosion_smokegrenade_s1_smokegrenade` and its children | | neither | *Read*: `pak` 85312-85318; probably unused or a fallback, *Inferred* |
| Saved point clouds | `smokegrenade/smokegrendae.vsnap` (sic), `weapon_smokegrenade_adaptive.vsnap`, `_pointcloud.vsnap`, `_pointcloud_col.vsnap` | read by `explosion_child_smoke_pointcloud(_col)` and `_smoke_adaptive` | neither | *Read*: `pak` 85326-85329, 85156-85159 |
| Standing inside | `explosion_screen_smokegrenade_new` (2155) | | neither | *Read*: `pak` 85303; when, *Inferred* |
| Walking through it | `particles/characters/smokegrenade_body_fx` (+`_temp`, `_trails`) | | neither | *Read*: `pak` 84872-84874; when, *Inferred* |
| Cleared by an HE or the bomb | `explosion_smoke_disperse` (2428) | | neither | *Read*: `pak` 85304; when, *Inferred* |

- The smoke's colour is networked (`m_vSmokeColor`, *Read*:
  `schema/*/C_SmokeGrenadeProjectile.h`, `sv` 4466). Development convars set
  it per team: `smoke_grenade_ct_color [75,127,155]` and
  `smoke_grenade_t_color [180,129,50]` (*Read*: `cvars` 9546, 9549). The
  `_ct` and `_t` bursts are the tinted versions (*Inferred*).
- A smoke thrown into fire (`m_bExplodeFromInferno`) or landing on it
  (`m_bDidGroundScorch`) leaves a mark (*Read*: server schema; the meaning is
  *Inferred*).

### 2.4 Decoy

| When | Effect | Children | Named by | Evidence |
|---|---|---|---|---|
| It lands and starts | `weapon_decoy_ground_effect` (1771) | `weapon_decoy_ground_embers_01`, `_low_02`, `_low_03`, `_low_04`, `_primary_01`, `_smoke_01` | client only | *Read*: `cl` 37121, `pak` 87089-87096; when, *Inferred* from `decoy_started` (`cl` 31506) |
| Each fake shot | `weapon_decoy_ground_effect_shot` (1466) | probably the same set | both | *Read*: `cl` 37122, `sv` 29191 |
| The last pop | `explosion_basic` (1613) | none share its name | both | *Read*: `cl` 37046, `sv` 29149; that the decoy uses it, *Inferred* |

The shot's tick is networked as `m_nDecoyShotTick`. The client keeps
`m_nClientLastKnownDecoyShotTick` and `m_flTimeParticleEffectSpawn` to start
one effect per new shot (*Read*: schema; `DecoyProjectileEffects_client` at
`cl` 17450). A decoy explosion exists (`ff_damage_decoy_explosion`, `cvars`
3262), and `explosion_basic` is the only small generic root left for it.

### 2.5 Molotov and incendiary

Named in code at `cl` 37034-37126 and `sv` 29167-29194. The children are
from `pak` 85600-85800 (`particles/inferno_fx/`) and 87100-87120
(`particles/weapons/cs_weapon_fx/`). When each plays is *Inferred* from the
names and the entity's fields unless marked.

| When | Root effect | Children, by file name |
|---|---|---|
| In hand, molotov | `weapon_molotov_held` (third person), `weapon_molotov_held_fps`, `weapon_molotov_fp` | `_fp_wick`, `_fp_fire`, `_fire2`, `_fire3` to `_fire3d`, `_fp_glow`, `_fp_fire_blue` |
| In hand, incendiary | `weapon_incend_held`, `weapon_incend_held_fps` | `_held_sparks`, `weapon_incend_core_sparks` |
| In flight | `weapon_molotov_thrown`, `weapon_incend_thrown` | `_thrown_child1`, `_child3`, `_thrown_glow`; `incgrenade_thrown_trail` (+`_glow`) |
| Breaks on the ground | `molotov_explosion`, `incendiary_explosion` (server only) | `molotov_explosion_child_fireball1` to `4`, `_flash`, `_ground1`, `_ground2`, `_sprays`; `explosion_molotov_ground_debris`, `_ground_splash07a`; `incend_explosion_child_sprays`, `explosion_incen_ground_splash07a` |
| The bottle's glass | `impact_fx/molotov_broken_glass` (5020), both DLLs, and the model `weapon_molotov_broken_glass.vmdl` (`cl` 41167) | |
| Goes off in the air (after `molotov_throw_detonate_time`, 2 s) | `explosion_molotov_air`, `explosion_incend_air` | `_core`, `_debris`, `_down`, `_falling`, `_fallingfire`, `_smoke`, `_splash01a`, `_splash07a` |
| The whole fire | `molotov_groundfire`, `incendiary_groundfire` | quality tiers `_00high`, `_00medium`, `_fallback`, `_fallback2`; `_main`, `_main_center`, `_main_fancy`, `_main_glow`, `_outline`, `_outlineset`, `_outline_burn`, `_outline_embers`, `_climbingset`, `_climbingoutline`, `_filltest`, `_filler_napalm` and `_replicator` (incendiary), `_fillsparks` (incendiary), `_snapshot_child_base`, `_snapshot_water_silt`, `_projected`, `_lighting`, `_scortch`, `_streaks`, `_child_base` (+`_glow`, `8`, `_hcp`), `_child_embers`, `_child_glow` |
| Per flame | `molotov_fire01` (+`_cheap`), `incendiary_fire01` | `molotov_child_flame01a` to `05a`, `_child_glow01a` to `03`; `incendiary_child_flame01a`, `03a` |
| Smoke above it | `molotov_smoke_screen`, `molotov_center_smoking_ground` | `molotov_smoking_ground_child01` to `03` (+`_cheapo`) |
| Burns out | `molotov_groundfire_remnant` (no incendiary twin) | `_endcap`, `_endcap_ground`, `_ground_swirly`, `_groundsmoke`, `_endcap_wall` |
| Put out by a smoke or the bomb | `extinguish_fire` (server only), `extinsguish_fire_blastout_01` (sic) | `extinguish_fire_swirl` (+`_smoke`), `extinguish_embers_small_01`, `_02` |
| A player standing in it | `molotov_bodyburn` | `_footprint`, `_smoke`; also `burning_fx/burning_character` (`_b` to `_e`) |
| The charred ground | the `materials/dev/inferno.vmat` pass (section 5); decals `decals/molotovscorch.vmat`, `scorch1_projected_cheap`, `_triplanar` | |

The `firework_crate_*` effects belong to a firework crate (`CFireCrackerBlast`,
an inferno of another type) and are not a grenade's. Leave them out.

**How the fire's particles get their points.** The client entity `C_Inferno`
turns the server's flame positions into five particle snapshots, which are
point sets that particle systems read: flame points, filler points, outline
points, climbing-outline points and decal points (*Read*:
`schema/client/C_Inferno.h:4-8`). The groundfire's `_outlineset`,
`_climbingset`, `_filler_*` and `_snapshot_child_base` children read them
(*Inferred* from their names). `particles/inferno_fx/fire_core.vsnap`,
`fire_edge.vsnap` and `fire_filler.vsnap` (`pak` 85671-85673) are saved
snapshots, probably the editor's preview points (*Inferred*). Whether a flame
also runs its own `molotov_fire01` system beside the snapshot children is not
settled.

**What the server sends for each flame** (*Read*: `C_Inferno.h:3-26`):
- `m_firePositions[64]` and `m_fireParentPositions[64]`: each flame and the
  flame it spread from, which would place the filler and the streaks between
  them (*Inferred*);
- `m_bFireIsBurning[64]`, and `m_BurnNormal[64]`, the surface's normal, which
  stands flames up on walls for the climbing outline (*Inferred*);
- `m_fireCount`, `m_nInfernoType` (molotov, incendiary or firework crate),
  `m_nFireLifetime`, `m_nFireEffectTickBegin` (the tick the effect's clock
  starts, *Inferred*), and `m_bInPostEffectTime` (the flames are out and the
  remnant plays, *Inferred*).

The client keeps the five snapshot handles, the fire's bounds (`m_minBounds`,
`m_maxBounds`), its widest flame and tallest, and a line-of-sight check
(`m_blosCheck`, `m_nlosperiod`). The burning player's effect runs off
`m_nPlayerInfernoBodyFx` and `m_fMolotovDamageTime`, the last time fire hurt
them (*Read*: `schema/client/C_CSPlayerPawn.h:96-97`). `C_EntityFlame` is a
flame stuck to an entity, with a cheap version (`m_bCheapEffect`, `cl` 5017,
6178).

Fire convars (*Read*: `cvars`):
- `inferno_dlights 30`: "Min FPS at which molotov dlights will be created";
- `inferno_dlight_spacing 7200`: lights "at least this far apart", probably a
  squared distance, about 85 units (*Inferred*);
- `cl_inferno_bodyburn true`, `r_csgo_render_inferno_decals true`;
- `inferno_surface_offset 15`, `Inferno_concav_plane_threshold -10`;
- `inferno_max_flames 16`, which matches the ground shader's 16 flames per
  fire (section 5).

### 2.6 Every grenade: the pin, the spoon and the trajectory line

- **Pin and spoon.** `weapon_grenade_pin` (3978) and `weapon_grenade_spoon`
  (4000) (*Read*: `pak` 87098-87099). Neither DLL names them, so they are
  probably started by a particle event on the pull and throw clips, as each
  gun's muzzle flash is started by a `CNmParticleEvent` on its fire clip
  (*Inferred*; `reference/weapons/effects.md`). The extracted clips'
  `clip_data` would show it.
- **No trail in flight.** No file under any HE, flash, smoke or decoy name is a
  trail (*Read*, by absence). Only the molotov and incendiary burn in flight.
- **The trajectory line is drawn by the client.** The client projectile holds
  its path (`m_arrTrajectoryTrailPoints`, their creation times,
  `m_bCanCreateGrenadeTrail`, `m_nSnapshotTrajectoryEffectIndex`), and the
  server's twin holds none of it (*Read*: `schema/client/C_BaseCSGrenadeProjectile.h`).
  The effect is `particles/entity/spectator_utility_trail.vpcf` (4368), fed by
  the snapshot `particles/entity/grenade_path_snap.vsnap` (*Read*: `cl` 37039,
  `sv` 29145, `pak` 84951, 84961; the pairing is *Inferred*). It is off in
  normal play: `sv_grenade_trajectory_prac_trailtime 0` and
  `sv_grenade_trajectory_time_spectator 0`, each up to 8 s (*Read*: `cvars`
  11169-11176). A community page gives the spectator default as 4 s
  (*Community*, csdb.gg); the dump says 0.
- `CGrenadeTracer` (`m_flTracerDuration`, `m_nType`), `grenade_tracer.cpp`
  (`cl` 13341) and a runtime texture `GrenadeTracerTexture%d.vtex` (`cl` 19995)
  are a client-only tracer entity, most likely the replay or spectator line
  (*Inferred*).

### 2.7 Scorch marks and lights

- **Scorch.** The HE's roots carry particle decals,
  `explosion_hegrenade_decal` and `explosion_hegrenade_brief_decal` (*Read*:
  `pak` 85204, 85194). Explosions also carry a decal type, `"Scorch"` by
  default (section 1), resolved through `scripts/decalgroups.vdata`
  (`pak` 87735, 12678 bytes), whose options are each a material, a probability
  and a range of angles to gravity (*Read*: `schema/client/DecalGroupOption_t.h`).
  The materials are `materials/decals/scorch/scorch1` to `scorch4.vmat`,
  `materials/decals/scorch1.vmat` (+`_projected_cheap`,
  `_projected_triplanar`) and the fire's `materials/decals/molotovscorch.vmat`
  (*Read*: `pak` 14941-14955). Which ones the `Scorch` group lists needs the
  file.
- **Lights.** Only the HE has a light file: `explosion_hegrenade_light.vpcf`
  (2640 bytes, `pak` 85233), probably a particle light like the muzzle
  flashes' `C_OP_RenderStandardLight` (*Inferred*; the bomb's twin is
  `explosion_c4_light`). The fire makes dynamic lights spaced by the convars
  above. Any light the flash, smoke or decoy makes is inside its `.vpcf`.

## 3. What ours draws now

- `src/grenades/grenade_view.gd` draws stand-ins: a grey sphere per smoke
  cube, an orange emissive cone per flame (bobbing), an orange ball and an
  OmniLight for 0.3 s at an HE or decoy blast, and a white light at a flash.
  Nothing of CS2's particles.
- `src/grenades/flash_overlay.gd` is a white `ColorRect` whose alpha is the
  linear value of the blind share. That matches CS2's own sRGB-to-linear step
  (section 4), but it blends the white over the screen where CS2 adds it, and
  it has no afterimage.
- `src/grenades/flash_blind.gd` holds a duration and a peak on the server,
  held and then faded over `GrenadeRules.FLASH_FADE_SECONDS`, which matches
  CS2's networked pair (`m_flFlashDuration`, `m_flFlashMaxAlpha`). It has no
  build-up and no separate afterimage fade; CS2 keeps both on the client
  (section 4.3).
- `src/grenades/fire_spread.gd` keeps each flame's position only. CS2 sends a
  birth time (the ground shader needs it), the flame it spread from, the
  surface's normal and whether it burns (section 2.5).
- `src/effects/` already plays CS2's muzzle flashes from typed tables
  (`FlashTable`, drawn through `EffectQuads`, sprite sheets put back together
  by `scripts/effect_textures.gd`). Plan step 8 generalises that runner to
  play a table at a world point.

## 4. The flashbang's screen

### 4.1 The pieces

- The shader `csgo_flashbang_overlay.slang`, "Flashbang overlay effect"
  (*Read*: line 6), and its material
  `materials/effects/flashbang_overlay/csgo_flashbang_overlay.vmat` (section
  2.2).
- In client.dll: `cs_render_flashbang.cpp` (`cl` 13358), the class
  `CFlashbangResolveLayerRenderer` (`cl` 8325), the layers `FlashbangOverlay`
  and `FlashbangResolveLayer` (`cl` 18761-18762), the pipeline
  `RenderingPipelineCsgoFlashbangOverlayManifest` (`cl` 24083), and the render
  target names `cs_flash_frame_render_target_split_%d` and
  `cs_flash_frame_texture_player_%d.vtex` (`cl` 31065-31066). *Read*
- The client pawn's flash state (*Read*:
  `schema/client/C_CSPlayerPawnBase.h:11-18`): `m_flFlashBangTime`,
  `m_flFlashScreenshotAlpha`, `m_flFlashOverlayAlpha`, `m_bFlashBuildUp`,
  `m_bFlashDspHasBeenCleared`, `m_bFlashScreenshotHasBeenGrabbed`,
  `m_flFlashMaxAlpha`, `m_flFlashDuration`.
- The server's (*Read*: `schema/server/CCSPlayerPawnBase.h`):
  `m_blindUntilTime`, `m_blindStartTime`, `m_flFlashDuration`,
  `m_flFlashMaxAlpha`. Only the last two are networked, with client callbacks
  `OnFlashDurationChanged` and `OnFlashMaxAlphaChanged` (`cl` 5593-5594,
  22388-22389). server.dll logs "Blinded: holdTime = %3.2f, fadeTime = %3.2f,
  alpha = %3.2f" (`sv` 10447).

### 4.2 What the shader computes (*Decoded*, lines 297-319)

Its inputs keep their attribute names:
- W, `FlashbangAlpha`: the white;
- S, `FlashbangScreenshotAlpha`: the afterimage;
- `FlashbangFrameTexture`, read with `SrgbRead(true)` and a point sampler: the
  frozen frame.

A colour texture (`TextureColor`) is declared but never read.

Per pixel:
1. Each alpha is clamped to 0..1 and turned from an sRGB amount into linear
   light with the exact sRGB curve (`x / 12.92` up to 0.04045, else
   `((x + 0.055) / 1.055)^2.4`).
2. The frame is read at the pixel's screen position (`FragCoord * 1/size`),
   clamped to 0..1 and raised to the power 2.2.
3. The output is `rgb = frame^2.2 * lin(S) * 4.0 + lin(W)`, alpha 0.

There is no tint: the white is the same on all three channels. The constants
are the 4.0 gain on the afterimage, the 2.2 on the frame, and the sRGB curve.

**It adds to the scene** (*Inferred*). The alpha out is 0, and the shader's
render states list no blend state. With alpha 0, an ordinary blend would draw
nothing, and no blend at all would turn the screen black whenever both alphas
are 0. The shader offers `F_TRANSLUCENT` and `F_ADDITIVE_BLEND` (lines 30-35),
so the material almost surely turns on additive blending:
`screen = scene + lin(W) + 4 * lin(S) * frame^2.2`. The material settles it
(section 8).

So the afterimage is the frozen view, darkened toward its highlights by the
extra power and then brightened fourfold: the sky and lit walls of the old
view show as a bright ghost, and its dark parts vanish. The double gamma has
two readings (*Inferred*; GameTracking cannot decide it). Either the frame
really is decoded as sRGB and the 2.2 is a deliberate contrast curve, which
gives a dimmer, harder ghost, or the target is bound as plain UNORM and the
2.2 is a rough sRGB decode. A screenshot in CS2 settles it (section 9).

Render states (*Read*: lines 349-359): no depth test or write; the stencil
test (`NotEqual`, ref 3, read mask 1) passes only where the stencil's lowest
bit is clear. So pixels tagged with that bit stay unwhited. Which pass tags
them is not in GameTracking; it may be the viewmodel (*Inferred*). The vertex
shader draws a quad straight in clip space: the whole screen (*Decoded*,
lines 225-232).

### 4.3 When the afterimage is taken, and the fades (*Inferred* from names)

- **Once per flash.** `m_bFlashScreenshotHasBeenGrabbed` and
  `m_flFlashScreenshotAlpha` pair with the shader's S, and
  `m_flFlashOverlayAlpha` with W. So the frame is grabbed once per flash and
  fades on its own curve, apart from the white.
- **It is the world, without the HUD.** `CFlashbangResolveLayerRenderer` is a
  layer in the 3D pipeline that copies the rendered view into
  `cs_flash_frame_render_target_split_%d` (one per split-screen player), bound
  to the shader as `cs_flash_frame_texture_player_%d.vtex`. The scope's
  magnifier does the same (`MagnifierResolveLayer`, `cl` 21562). A layer
  inside the 3D pipeline comes before the HUD, so the frame holds no HUD.
- **It is the view at the moment of blinding.** The grab runs when the client
  first sees a new flash (the duration or peak changes, and the grab flag is
  clear).
- **The white builds up.** `m_bFlashBuildUp` suggests a short ramp up before
  the hold, rather than full white in one frame. Its length is not in
  GameTracking.
- **The curves are code.** The client works out both alphas each frame from
  `m_flFlashBangTime`, the duration and the peak. The hold, the fade, and how
  the afterimage fades against the white are not data, and not in
  GameTracking. `cl_display_flashbang_values` would print them, but it is a
  development convar that retail cannot set (*Read*: `cvars` 1174).
- `m_bFlashDspHasBeenCleared` is the sound's muffle, already done in #142.

### 4.4 Convars (*Read*: `cvars`)

- `r_spectator_flashbang_opacity 0.6`, from 0.2 to 1, saved: "Spectator flash
  opacity" (8616-8617). It scales the effect for spectators only.
- `sv_flashed_amount_for_blind_kill 0.7`: the least flashed a killer can be
  for a blind kill (11106-11107).
- No convar sets the hold, the fade, the colour or the afterimage's gain.

### 4.5 Over or under the HUD

For the flashed player the white covers the HUD (*Inferred*). The spectator
change of May 2026 (section 6) moved it under the HUD for spectators only.

## 5. The fire's charred ground: `inferno.slang`

`inferno.slang` does not draw the flames. It is one full-screen pass that
darkens or tints the world's surfaces near the flames (*Decoded*). Its
material is `materials/dev/inferno.vmat` (*Read*: `cl` 35565, `pak` 16701),
and the code is `cstrike15/effects/clientinferno.cpp` and
`cs_inferno_visual.cpp` (`cl` 13336-13337). The header still says "Smoke
Volume", so it began as a copy of the smoke shader (*Inferred*).

**Its inputs** (names lost; read from use):
- 256 flame slots, 16 fires of 16 flames: each a world position and, in `.w`,
  a time, the flame's birth (*Inferred*);
- 16 fire slots, each with its start time in `.x` (*Inferred*);
- per screen tile (the screen split 4 by 4), a bitmask of the fires reaching
  it, and per fire and tile, a bitmask of its flames reaching it. They are
  built on the CPU each frame from the fire's bounds (*Inferred*; the buffer's
  name has "BoundingBox" in it);
- the scene's depth, the current time, and the camera;
- `g_flTintStrength` (default 1) and `g_vTintColor`, set in the material;
- a 3D noise texture (`TextureNoise`, suffix `_z0000`), which matches
  `materials/dev/noise/worley_perlin_z0000_tga_*.vtex` (`pak` 16709-16710),
  the smoke's Worley-Perlin volume (*Inferred*).

**Per pixel** (*Decoded*, lines 185-265):
1. Skip the pixel if no fire reaches its tile.
2. Rebuild the world point P of the surface under the pixel from the depth.
3. For each fire, with `t` the time since it started, and each of its flames:
   - `v = P - flame; v.z *= 2`, so the reach is half as tall as it is wide:
     a flat ellipsoid on the ground;
   - `age = now - birth`; `d = length(v) - age`, so the reach grows by one
     unit per second of the flame's age;
   - skip it if `d >= 100`, otherwise
     `m = max(m, smoothstep(100, 50, d) * smoothstep(0, 1, age) * smoothstep(6.5, 5.5, birth - fire start))`.
   So a flame counts in full within 50 units and not at all past 100. It fades
   in over its first second. A flame born more than about 6 s after its fire
   started does not count.
4. `m *= smoothstep(0, 0.5, t)`: the whole fire fades in over half a second.
   Where `m > 0`, the noise is read at `P * 0.007` (one tile per about 143
   units), with P raised by `100 * smoothstep(7, 0, t)`. That slides the
   pattern 100 units through the ground over the first 7 s, so it churns and
   then sets. Then `a = saturate((noise.y + m) * m) * (0.85 + 0.1 * noise.x)`.
5. `a *= smoothstep(20, 6, t)`: full until 6 s after the fire started, gone by
   20 s. The strongest fire wins.
6. Below 0.0001 the pixel is skipped. Otherwise it writes
   `(tint colour, a) * tint strength`.

So it is a soft, noisy mask on every surface within 50 to 100 units of the
flames. It comes in with the fire and outlives it: the molotov burns 7 s and
the incendiary 5.5 s, and the mask lasts to 20 s. One flat tint colours it,
which fits charred ground (*Inferred*; compare `r_csgo_render_inferno_decals`
and the fire's decal snapshot). The tint and the blend mode are in the
material, which GameTracking does not carry. The 6.5 s cutoff and the 7 s
slide match `inferno_flame_lifetime 7` (*Inferred*). The incendiary's shorter
fire is not in the shader.

## 6. What Valve has changed, by date

All from search summaries; the pages refuse fetches from the cloud.

- **2024-05-23** ("Fire Sale" update): "The height of the 'pillar' of flame for
  both Molotov and Incendiary grenade now decreases over time." The
  incendiary's "explosion and flame visual treatment" was adjusted, shorter and
  smaller (*Valve*; Steam news 4177730135016140040, HLTV 39059).
- **2024-06-10**: "Fixed one-way visibility for players inside HE grenade
  explosions." (*Valve*)
- **2024-10-28**: an HE going off inside a smoke clears the smoke-screen effect
  on players inside it within range (*Valve*). That effect is
  `explosion_screen_smokegrenade_new` (*Inferred*).
- **2025-05-09**: fixed fire being visible through smoke, a bug from the day
  before (*Valve*). Players reported that the fire's shadows showed players in
  smoke with anti-aliasing off (*Community*, Sportskeeda).
- **2025-08-02**: the correct molotov fire particle restored (*Valve*, via
  tradeit's summary). An undated note says fire was no longer drawn through
  the AK-47's viewmodel.
- **2025-09-16**: new grenade sounds (draw, inspect, pin, throw); sounds only
  (*Valve*).
- **2026-04-30**: "Adjusted particle effect sprite opacity for fully occluded
  flashbangs." (*Valve*) This is the pop's sprites, not the screen.
- **2026-05-22 or so, then 2026-05-28/29**: spectators first got the flash in
  full, then "Added the new r_spectator_flashbang_opacity console variable,
  allowing remote spectators to adjust flashbang opacity. Flashbang effects
  for remote spectators now render underneath the HUD." (*Valve*; HLTV 44721,
  Dust2.us 74285)
- **2026-07-20**: "Smoke, flashbang, and bomb-blast shaders have been reworked
  for more consistent visual effects"; the bomb's blast now disperses smokes
  and puts out fires nearby (*Valve*; Dust2.us 76184). An auto-generated site
  says the flash's two alphas were clamped to 0..1 and its per-channel curve
  made one scalar (*Community*, cs2news.gg, unverified). The current shader
  does exactly that (section 4.2), so the shader was probably changed then.
- No dated note was found on the HE fireball's own look, the decoy's effect,
  or a trail in normal play.

What players say (*Community*):
- The afterimage has been part of the flash since CS:Source and is in CS2
  (the fandom wiki).
- Players ask for a black flash for their eyes' comfort (Steam discussion
  840610464762324418; Dot Esports). Valve has not added one.
- The incendiary shows blue at its edges, says the fandom wiki; another
  summary says green. They disagree, so it is a check in CS2.
- The molotov's top is too bright to see through (a Steam thread), and guides
  teach seeing through a molotov low down, so its flames are partly
  see-through near the ground.
- Fire or muzzle flashes behind a smoke once made the smoke look thin.

## 7. Code fixes this research finds

These are fixes to make when the effects are built, not in this PR:

1. **The white-out adds, and has an afterimage** (plan step 9's last part).
   `FlashOverlay` should add its white (`blend_add`) instead of blending it
   over the screen, and add the frozen frame at four times the afterimage's
   linear amount. Over black the two blends give the same result; over a lit
   scene CS2's is brighter and reaches full white sooner.
2. **The flash gets a build-up and a second fade.** Beside `FlashBlind.amount()`
   the view needs a short ramp up and the afterimage's own fade. CS2 keeps
   both on the client, so ours can be view-side functions of the same
   duration and peak read with `DrawClock`, with the server still holding only
   those two. Their lengths wait on the look in CS2 (section 9).
3. **Spectators see the flash at 0.6 and under the HUD**, once there are
   spectators.
4. **`FireSpread` keeps more per flame:** its birth time (on `SimClock`), the
   flame it spread from, the surface's normal from the trace that placed it,
   and whether it burns. The ground pass needs the birth time, the filler
   needs the parent, and wall flames need the normal. This is server state, so
   it goes in the tick; the drawing only reads it.

## 8. Mapping onto Godot 4.7 (*Inferred*; for plan steps 8 and 9)

Read `reference/godot/README.md` and its rendering and shader pages first.

- **The particles use the existing runner.** Step 8 generalises
  `src/effects/muzzle_flashes.gd`'s `FlashTable` layers, drawn through
  `EffectQuads`, to play a table at a world point. Each root above becomes a
  table typed from its decompiled operators, the way `FlashTable` was. The
  fire places its layers on the server's flame points (flipbook flames from
  `fire_small_sim` or `fire_gas`, a glow, embers), fillers between a flame and
  its parent, and wall flames on the normal. Its pillar shortens with age
  (2024-05-23). `GPUParticles3D` is the other option, but the table runner is
  already built and can be checked headless.
- **The fire's ground is one spatial shader.** Per fire, a box around its
  flames (their bounds plus 100 units across, and plus 50 up and down) drawn
  with `cull_front`, no depth test, unshaded and blended. It reads the depth
  texture, rebuilds the world point from `INV_PROJECTION_MATRIX` and
  `INV_VIEW_MATRIX`, and takes `vec4 flames[16]` (position and birth) and the
  fire's start as uniforms. The box does the job of CS2's tile masks. Godot is
  Y-up, so CS2's `v.z *= 2` is `v.y *= 2`, and the slide moves along y. The
  world is in inches, so `P * 0.007` carries over unchanged. The noise is an
  `ImageTexture3D` shared with the planned smoke volume
  (`reference/research/smokes.md`). A cheaper fallback is Godot `Decal` nodes
  with `molotovscorch`, which loses the noise's shape.
- **The fire's light** is a few orange `OmniLight3D`s without shadows, spaced
  about 85 units apart, flickering per frame.
- **The flash overlay** is a `canvas_item` shader with `blend_add` on a
  full-screen `ColorRect` in a `CanvasLayer` above the HUD:

  ```glsl
  shader_type canvas_item;
  render_mode blend_add, unshaded;
  uniform sampler2D frame : filter_nearest, repeat_disable; // the grab
  uniform float white_srgb;  // W
  uniform float shot_srgb;   // S
  float lin(float x) { return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4); }
  void fragment() {
  	vec3 f = pow(clamp(texture(frame, SCREEN_UV).rgb, 0.0, 1.0), vec3(2.2));
  	COLOR = vec4(f * lin(clamp(shot_srgb, 0.0, 1.0)) * 4.0 + lin(clamp(white_srgb, 0.0, 1.0)), 1.0);
  }
  ```

  The project blends 2D in linear light (`hdr_2d`), the space CS2 adds in, so
  the numbers carry over. `blend_add` multiplies by the source alpha, hence
  alpha 1.
- **Grabbing the frame once.** The better way is a `CompositorEffect` at
  `POST_TRANSPARENT` that, when a flag is set, copies the scene's colour into
  its own texture with `RenderingDevice.texture_copy`, shown to the overlay as
  a `Texture2DRD`. It stays on the GPU, leaves the HUD out as CS2's does, and
  is the same idea as a resolve layer. That colour is linear HDR before the
  tonemap, so the copy needs the project's tonemap (or issue 10's grade)
  applied. It runs on the render thread, so the flag needs a mutex
  (`reference/godot/rendering.md`). The simple first cut is
  `get_viewport().get_texture().get_image()` into an `ImageTexture`, once per
  flash. It stalls the GPU for a frame and includes the HUD, but it happens
  once per blind. `hint_screen_texture` and `BackBufferCopy` are live, not
  frozen, so they do not work here.

## 9. For Sid's machine

### 9.1 Extraction: one new step, `grenade-effects`

Plan step 7. The pattern is the muzzle flashes': decompile with Source 2
Viewer `-d`, read each effect operator by operator, write a generated page of
the numbers, and put the textures the files name back together as sprite
sheets with `scripts/effect_textures.gd`. It should be a step of its own
beside `effects`, so running it never touches anything else.

**What it exports.** `.vpcf` and `.vsnap` text, two data files as text,
textures, and four kinds of materials. The materials are all effect or decal
materials under `materials/effects/`, `materials/dev/` and `materials/decals/`.
None is a character or map material, so they cannot overwrite his working
agent materials. The step should still write everything under
`assets/effects/grenades/` and nowhere else.

1. **Particles** (`-d`, as text, into `assets/effects/grenades/vpcf/`, with a
   `.gdignore`):
   - `particles/explosions_fx/`, the whole folder (about 330 files, most under
     6 KB). It holds every HE, flash, smoke and basic explosion root, the 72
     shared `explosion_child_*` files, the screen effects
     (`explosion_screen_*`), `explosion_smoke_disperse` and the smoke's four
     `.vsnap` files. The script already takes folder prefixes with `-f`.
   - `particles/inferno_fx/`, the whole folder: the ground fires and their
     children, the per-flame effects, the smoke above, the remnant, the
     extinguish, the body burn, the air bursts, the flight trail, and
     `fire_core`, `fire_edge` and `fire_filler.vsnap`.
   - `particles/impact_fx/molotov_broken_glass.vpcf_c`.
   - `particles/burning_fx/burning_character*`.
   - `particles/weapons/cs_weapon_fx/weapon_molotov_*`, `weapon_incend_*`,
     `weapon_decoy_*` (8), `weapon_grenade_pin.vpcf_c` and
     `weapon_grenade_spoon.vpcf_c`.
   - `particles/characters/smokegrenade_body_fx*` (3).
   - `particles/entity/spectator_utility_trail.vpcf_c` and
     `particles/entity/grenade_path_snap.vsnap_c`.
2. **Data**, as text with `-b DATA` (as `weapons.vdata` is read):
   `scripts/explosion_types.vdata_c` (which effect, sound and decal each
   explosion uses; may say which HE variant plays where) and
   `scripts/decalgroups.vdata_c` (which materials the `Scorch` group lists).
3. **Screen materials** (`-d`):
   - `materials/effects/flashbang_overlay/csgo_flashbang_overlay.vmat_c`:
     which features are on (`F_ADDITIVE_BLEND`, `F_TRANSLUCENT`), its colour
     and texture settings. This settles the blend.
   - `materials/effects/flashbang_white.vmat_c`: its shader and colour, to
     learn whether anything draws it.
   - `materials/dev/inferno.vmat_c`: the ground's tint colour, tint strength,
     blend mode and noise texture.
   - The compiled `csgo_flashbang_overlay` shader in `shaders_vulkan_dir.vpk`,
     if Source 2 Viewer reads its blend state (the decompiled text leaves it
     out). Source2Viewer-CLI 20.0 cannot read VCS 72 shaders (CS2's 2026-09-23
     update), so this may fail; the material alone is enough if it does.
4. **Decals** (`-d`): `materials/decals/scorch/` (4 materials, 6 textures),
   `materials/decals/scorch1*.vmat_c` with their `scorch1_color_*` textures,
   and `materials/decals/molotovscorch.vmat_c`.
5. **Textures**: those the decompiled files name. They cannot be listed from
   here. Run 1 first, collect every `.vtex` and `.vmat` the files name, and put
   them in a `GRENADE_EFFECT_TEXTURES` list for `effect_textures.gd`. Expect
   `materials/particle/fire_small_sim/`, `fire_gas/` (with their `_mv`
   motion-vector twins), `fire_onsurface`, `fire_climbing`,
   `particle/flames/`, `materials/particle/flash_bang.vtex_c`, the
   `particle_smokegrenade*` textures (`pak` 30720-30724), smoke, debris and
   sparks. Two are already fetched for the muzzle flashes
   (`fire_gas_batch_b_top`, `fire_small_sim_b`). Add the 3D noise
   `materials/dev/noise/worley_perlin_z0000_tga_*.vtex_c` (both), which the
   fire's ground and the smoke volume share.
6. **The pin and spoon.** Check the grenades' pull and throw clips'
   `clip_data` (already extracted by `weapon-animations`, if the grenades are
   in it) for a `CNmParticleEvent`.
7. Write the generated page of each effect's operators, as step 7 says, so the
   cloud threads can type the tables in step 8.

### 9.2 Checks in CS2

Offline with bots, `host_timescale 0.1` or a 120 fps capture, the colour grade
on:
1. **Which HE plays where:** one on dust2's sand, one on the concrete at A
   site, one in the air.
2. **The flash's curves:** be flashed full on and from the side. Frame by
   frame, read the white over a black wall and the ghost's edge. Measure the
   build-up, the hold and the fade, and whether the ghost fades faster or
   slower than the white. With `developer 1` on a local server, see whether
   "Blinded: holdTime ..." prints.
3. **What the white covers:** the HUD, and the gun in your hands (the stencil
   bit).
4. **The ghost:** a screenshot of it over a dark area, to tell the two
   readings of the double gamma apart.
5. **A flash behind a wall:** does its pop fade (2026-04-30)?
6. **The decoy:** its first shot, and its end (is the end `explosion_basic`?).
7. **A smoke from each team:** the burst's tint.
8. **The fire:** how long the charred ground lasts and its colour; how long a
   player keeps burning after leaving the fire; how many lights a fire makes;
   the incendiary's edge colour (blue or green); screenshots beside ours.
