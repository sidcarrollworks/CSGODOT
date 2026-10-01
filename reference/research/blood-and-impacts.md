# What CS2 draws when a round hits

Research for roadmap item 5 ("Blood on hit") and Sid's ask of 2026-09-30 ("We
also need blood and hit effects added"), written 2026-09-30. It covers what
CS2 draws when a round meets a body: the blood spray, the blood left on the
wall and floor behind, the wound on the body, and a helmet's sparks. It also
covers what CS2 draws when a round meets each surface of the world, and what
the repo draws now. It ends with what a thread can build now, the Local
extraction, and the checks in CS2.

**How each claim is marked.** *Read* means read from CS2's shipped files as
SteamDatabase's GameTracking-CS2 publishes them (origin/master `ce2a2de`,
2026-09-28, CS2 1.41.8.6, after the "Rush Hour" update). The paths below are
in that repository, with these short names:
- `pak`: `game/csgo/pak01_dir.txt`, the listing of the game's main archive;
- `cl` and `sv`: `game/csgo/bin/win64/client_strings.txt` and
  `server_strings.txt`;
- `CV`: `DumpSource2/convars.txt`;
- `SCH`: `DumpSource2/schemas/`;
- `IE`: `game/csgo/pak01_dir/scripts/surfaceproperties_impact_effects.txt`;
- `DG`: `game/csgo/pak01_dir/scripts/decalgroups.vdata`.

*Decoded* means worked out from a decompiled shader. *Inferred* is a reasoned
guess. *Valve* is a dated release note and *Community* anything else from the
web, both from search summaries, since Steam and the news sites refuse fetches
from the cloud. Source SDK 2013 (public) is cited only as a spec. Nothing here
comes from Valve's leaked source.

## The short version

- **Which effect and decal each surface gets is in plain text.** `IE` gives
  each surface a particle effect and a decal group. `DG` gives each group its
  materials with weights. A surface that leaves a field out takes its parent's.
  So the mapping can be built without Sid's machine; only the effects and
  textures themselves need the extraction.
- **Blood is particles, and its marks on the world are where those particles
  land.** CS2 has 83 files under `particles/blood_impact/`, and the code names
  17 of them. A particle operator stamps a decal from a named group where a
  particle hits the world, so the blood lands behind the victim, never on them
  (*Inferred* from the schema and the file names; the effect files confirm it).
- **Each hit also marks the body.** A shader paints a wound mask and blood into
  a texture per character, which the character shader reads.
- **A helmet sparks instead of bleeding.** `impact_helmet_headshot` is named by
  the server.
- **Valve made blood "much more bloody" on 2026-09-22**, and fixed blood decals
  that sometimes did not appear. The files read here are from after that
  update.
- **Ours drew nothing at a hit.** A round into a body left no mark
  (`src/combat/bullet_impacts.gd:116` returns early). This change adds a
  stand-in (section 6).

## 1. How CS2 picks an effect and decal for a surface

- **One table per surface.** `IE` (184 lines, KV3) gives each surface four
  fields:
  - `effect`, a particle system;
  - `effect_simplified`, a cheaper `_cheap` variant;
  - `impactDecalName`, a decal group;
  - sometimes `impactGrazingDecalName`, the group for a glancing hit.

  (*Read*: IE 5-183.) The client loads it in `CImpactEffectsManager`
  (`c_impact_effects.cpp`; *Read*: `cl` 4689, 6769, 8450-8451, 13309). Only the
  client names it, so the world's impacts are drawn by each client (*Inferred*).
- **A missing field is the parent's.** The parents are in
  `surfaceproperties.vsurf`, which the repo already resolves in
  `reference/surfaces/surfaces.csv`. Asphalt and rock have no `effect` of their
  own, and grass has no decal (*Read*: IE). They inherit, the way
  `reference/surfaces/surfaces.md` resolves the rest (*Inferred*).
- **Decal groups are weighted choices.** Each group in `DG` is a list of
  `{m_hMaterial, m_flProbability}` options (*Read*: DG; SCH
  `client/CDecalGroupVData.h`, `DecalGroupOption_t.h`, default probability 1).
- **Glancing hits.** A hit takes the grazing group when the round meets the
  surface at a shallow angle. The cutoff is
  `r_impacts_decal_grazing_incidence_cutoff 0.55`, with `_variance 0.1`
  (*Read*: CV 8238, 8241; that it is the cosine of the angle is *Inferred*).
- **Ricochet sparks.** `r_impact_ricochet_chance 0.3` gives a ricochet spark on
  30% of hits (*Read*: CV 8232). Which surfaces it applies to is *Inferred*:
  metal, or glancing hits.
- **Limits and fade.** At most `r_decals 2048` decals. Each starts to fade at
  30 s and is gone 3 s later (`r_decals_default_start_fade 30`,
  `_fade_duration 3`). Decals grow up to 1.35 times between 256 and 1536 units
  from you (`r_decals_distance_scale*`). (*Read*: CV 7893-7912.)

Resolved per surface (*Read*: IE 5-183, DG 4-898; the inheritance *Inferred*):

| Surface | Effect (`particles/impact_fx/`) | Decal group | Glancing group |
|---|---|---|---|
| default, concrete | impact_concrete | Impact.Concrete (concrete1-5) | - |
| asphalt | impact_concrete | Impact.Asphalt | Impact.Asphalt_Grazing |
| rock, brick, gravel | impact_concrete | Impact.Rock (rock1-4) | - |
| dirt, sand, mud, cardboard | impact_dirt | Impact.Dirt (dirt_dark1-4) | - |
| grass | impact_grass | Impact.Dirt | - |
| plaster, sheetrock | impact_plaster | Impact.Plaster, Impact.Sheetrock | - |
| tile | impact_tile | Impact.Tile (tile1-5) | - |
| wood and its children | impact_wood | Impact.Wood (wood1-4) | Impact.Wood_Grazing |
| metal, solidmetal, Metal_Box, metalpanel | impact_metal | Impact.Metal (metal1-4) | Impact.Metal_Grazing |
| metalvent, metalgrate | impact_metal_vent, impact_metal_grate | Impact.Vent, Impact.Metal | Impact.Metal_Grazing |
| chainlink | impact_chainlink | Impact.Concrete | - |
| glass | impact_glass | Impact.Glass | - |
| computer | impact_computer | Impact.Computer | Impact.Metal_Grazing |
| carpet, upholstery | impact_carpet, impact_upholstery | Impact.Upholstery | Impact.Upholstery_Grazing |
| plastic, rubber | impact_plastic, impact_rubber | Impact.Plastic, Impact.Rubber | - |
| pottery | impact_pottery | Impact.Tile | - |
| foliage | impact_leaves | Impact.Leaves | Impact.Wood_Grazing |
| water, wet | `water_impact/water_splash_03`, impact_concrete_wet | none | - |
| snow | impact_snow | Impact.Snow | Impact.Snow_Grazing |

`DG` also has groups that no surface in `IE` names: Impact.Brick, BrickRed,
Sand, Mud, Grass, Cardboard and MetalShield. Maps or materials may name them,
or they may be leftovers (*Inferred*). As far as this table shows, brick takes
rock's holes and sand takes dirt's.

## 2. A round into a body

### 2.1 The spray

- **Seventeen roots.** 83 files are in `particles/blood_impact/` (*Read*: `pak`
  84701-84783). The client names 17 roots (*Read*: `cl` 37016-37033):
  - `blood_impact_basic`, `_light`, `_medium`, `_heavy`;
  - `_low`, `_med`, `_high`;
  - `_light_headshot`;
  - the colours `_red_01`, `_yellow_01`, `_green_01`;
  - `_friendly`;
  - the victim's own view: `_localKillShot`, `_localfrontenemy`,
    `_localfrontsimple`, `_localplayer`, `_localrearhit`;
  - `impact_taser_bodyfx`.
- **Everything else is a child** (*Inferred* from the names):
  - `_spray_away`, `_mist_away`, `_vis_spray(_trail)` and `_ground_decal`
    under each of low, med and high;
  - the headshot set;
  - `red_01`'s backspray, chunks, drops, goop and mist;
  - `_splatter`, and `_spray_screen` (blood on the victim's screen);
  - `blood_pool`.
- **Which plays when** (*Inferred*):
  - Low, med or high goes by the damage. CS2's client convars
    `damage_impact_medium 20` and `damage_impact_heavy 40` are the likely
    bands (*Read*: CV 2782, 2785). Source SDK 2013 also scales blood by damage.
  - The `local*` roots are what the victim sees of a hit from the front or
    behind, and of the killing shot.
  - `_friendly` is a teammate's hit.
- **Colour.** `BloodType` {None, ColorRed, Yellow, Green, ColorRedLVL2..6} is
  networked as `m_nBloodType` (*Read*: SCH `client/BloodType.h`; `cl` 6083).
  LVL2 to 6 match the decal groups Bloodlvl2 to 6 (*Inferred*).
- **Code names.** `fx_cs_blood.cpp`, `fx_blood.cpp`, and the dispatch effects
  `csblood`, `bloodspray` and `bloodsplat` (*Read*: `cl` 13338, 13365,
  31093-31094). The server names the dispatch effects but no blood particle
  file (*Read*: `sv` 24407-24408, 25099). So the server asks for blood, and
  each client picks the particle (*Inferred*).

### 2.2 Blood on the wall and floor behind

- **The groups.** `Blood`, then `Bloodlvl2` to `Bloodlvl6`, hold 7, 7, 11, 12,
  10 and 7 options from `materials/decals/blood/blood_decals_{10,15,22}_NN`
  (*Read*: DG 470-721). Each option is a material with its own colour,
  occlusion and normal textures: 428 files, about 45 MB (*Read*: `pak`
  13404-13824). There are also 8 `blood_decals_spray_*` materials.
- **How they are placed.** The particle operator `C_OP_GameDecalRenderer` takes
  a group from `decalgroups.vdata`, fires on a particle's collision by default,
  and has a trace, a size, a random pick and turn, a tint and
  `m_bNoDecalsOnOwner` (*Read*: SCH `particles/C_OP_GameDecalRenderer.h`). So
  the spray's particles fly on along the round and leave blood where they hit
  the world, never on the victim (*Inferred*; the decompiled effects will
  show each operator's group, size and trace). This differs from Source 1,
  where the game traced a few rays up to 172 units along the shot (SDK 2013's
  bleed trace).
- **Blood ages.** The decal shader has an `F_BLOOD_AGING` feature ("Blood
  Spawning and Aging Effects"), driven by an age timer from 0 to 30 s
  (*Decoded*: `csgo_projected_decals.slang` 36, 43, 371). So CS2's blood decals
  spread in and darken as they age (*Inferred*).

### 2.3 The wound on the body

- `Impact.RtWound` names `materials/decals/system/rt_decal_impact_wound_stub.vmat`
  (*Read*: DG 864).
- `csgo_decal_renderer.slang` ("Blood Decals", line 21) paints
  `materials/blood/blood_default_impact.vtex` into a render target for each
  character, centred on each hit, 4 units across by default (*Decoded*: lines
  181, 218-222). Its output keeps the most wound so far and adds up the blood.
- The target is `r_character_decal_resolution 1024` across (*Read*: CV 7488),
  and it is a video setting.
- So each hit leaves a wound and blood on the model's skin, which the character
  shader reads (*Inferred*).

### 2.4 Helmets and armour

- `impact_helmet_headshot`, with glow and spark children, is named by both DLLs
  (*Read*: `cl` 37067, `sv` 29160). The server sends it, so it plays on a head
  hit that the helmet took (*Inferred*).
- A head hit without a helmet plays the headshot blood (*Inferred*).
- `impact_armor_ricochet*` (5 files) is named by neither DLL (*Read*, by
  absence). Kevlar body hits bleed as usual (*Inferred*; a check in CS2).
- The server also names `impact_hit_effect` and `impact_hit_effect_kill`
  (*Read*: `sv` 29161-29162), a server-sent mark at the victim for a hit and
  a kill (*Inferred*).

### 2.5 What is sent, and prediction

- **The events.** The server sends `player_hurt`, which carries no position,
  and `bullet_damage`: the victim, the attacker, the distance, the direction,
  the walls gone through, and the shot's angles, inaccuracy and ticks (*Read*:
  `mod.gameevents` 79-103).
- **Prediction.** Since 2024-11-13 the shooter's client can predict a hit.
  Predicted body and head effects are off by default (`cl_predict_body_shot_fx 0`,
  `cl_predict_head_shot_fx 0`), and predicted kill ragdolls are on (*Read*: CV
  1804-1813; *Valve*, per `combat.md`). `sv_server_verify_blood_on_player 1`
  (CV 11694) suggests the server confirms predicted blood (*Inferred*).
- **Convars.** `violence_hblood 1` and `violence_ablood 1` (CV 12684-12693).

## 3. A round into the world

- **The folder.** `particles/impact_fx/` has 297 files, about 1.35 MB (*Read*:
  `pak` 85345-85641). Each surface's root has a base, smoke, burst, bits and
  glow child, sparks and glow for metal, and a `_cheap` variant.
- **Wallbangs.** `impact_wallbang_heavy`, `_light` and `_light_silent` are named
  by both DLLs (*Read*: `cl` 37068-37070, `sv` 29164-29166): a server-chosen
  puff where a round comes out of a wall (*Inferred*). The repo draws the
  wallbang tracer but not this puff.
- **Close up.** `impact_screen_smoke_*` is smoke on your screen when you shoot
  something close (*Inferred*).
- Which of `effect` and `effect_simplified` plays is likely the particle detail
  setting (*Inferred*).

## 4. What Valve has changed, by date

- **2023-11-08:** "Improved performance of blood effects at close range."
  (*Valve*)
- **2024-11-13:** damage prediction, with predicted body and head effects off by
  default (*Valve*).
- **2026-09-22** ("Rush Hour"): "Globally increased visual clarity and improved
  fidelity of bullet impact decals. Blood is now much more bloody, and bullet
  impacts are far more impacty. Increased default bullet decal rendering
  distance. Fixed a case where blood decals weren't appearing." (*Valve*) The
  files read here are from after it, so the tables above are the new ones.
- **What players said** (*Community*): before Rush Hour, blood in CS2 was weaker
  than CS:GO's for confirming hits in a spray, and one analysis put it 19
  frames after the hit. After Rush Hour, streamers said it looks like CS:GO's
  again. So blood should first of all be quick and easy to read, sized by the
  damage.

## 5. What the repo had

- `BulletImpacts` (`src/combat/bullet_impacts.gd`) draws a hole and plays a
  sound where a round meets the world, from the shooter's own trace
  (`PlayerView._on_shot_traced`, `Bot._on_shot_traced`), not from the game's
  events. It has several gaps:
  - A round into a body left nothing (line 116).
  - It has holes only for concrete, plaster, metal and wood.
  - Dirt and sand take plaster's holes and tile takes concrete's, where CS2
    gives them `Impact.Dirt` and `Impact.Tile`.
  - There are no glancing groups, no weights, no 30 s fade and no distance
    scaling.
- `Hitscan.fire_as` sends `bullet_impact` for each surface and `player_hurt`
  through `DamageInfo.deal`. `HitTarget` knows its helmet.
- `src/effects/` draws tracers and muzzle flashes from typed tables of CS2's
  own effects, through `EffectQuads`. It has no impact, blood or spark effect.

## 6. What this change builds (Remote, no extraction)

1. **`bullet_damage`, CS2's own event, from the tick.** `Hitscan.fire_as` sends
   it after each `player_hurt` for a round into a living body. It carries CS2's
   fields that the game has, plus `x`, `y` and `z`: where on the body the round
   landed, which CS2's clients take from their own trace. `in_air` is sent
   false for now, since `Hitscan` does not know the shooter's state.
2. **`HitEffects` (`src/effects/hit_effects.gd`), per frame.** It notes
   `player_hurt` and the `bullet_damage` after it as the tick hands them out.
   So every viewer sees every hit, the victim and spectators included, not only
   the shooter. `HitEffects.effect_for` chooses CS2's root by the rules in 2.1
   and 2.4, and the next frame starts it. It is on dust2 and the test range.
3. **A stand-in until the effects are extracted.**
   - A spray of dark red cards flies on along the round, through
     `EffectQuads`; a helmet throws a few bright sparks instead.
   - Blood lands on the world behind: a few rays go from the hit along the
     round within a 12 degree cone, tilted down, up to 172 units (SDK 2013's
     reach, a stand-in), and one goes down to the floor. They are cast on the
     next physics frame through `PhysicsQueries`, against the world only.
   - Each ray that lands leaves a dark red splat. It is never drawn on a body,
     comes from a pool of 64, and fades by CS2's 30 s and 3 s.
   - The victim's own hits are not sprayed in their face.
   - All of this is plainly a stand-in: the splat and the cards are drawn here,
     not CS2's.
4. `tests/run_hit_effect_checks.gd` checks the choice, the rays, the view
   noting hits, and the splats landing on a wall behind and the floor.
   `tests/run_contract_checks.gd` checks `bullet_damage`'s fields.

Left for later Remote work, once the extraction is in:
- the typed blood and impact tables on the effect runner (grenade-effects.md
  section 8);
- CS2's blood decals in place of the stand-in splat, placed where the typed
  spray's particles land;
- the surface table generated from `IE` and `DG`, with dirt, tile, rock,
  asphalt and glass holes, weights and glancing groups;
- the wallbang puff;
- the wound on the body (a render target per character, or a decal that draws
  only on bodies and follows the bone).

## 7. For Sid's machine: the extraction

A new step, `impacts`, beside `effects` and `grenade-effects`, writing under
`assets/effects/impacts/` only. It follows the same method as the muzzle
flashes: decompile, read each effect operator by operator, write a generated
page of the numbers, and put the textures the files name back together as
sprite sheets with `scripts/effect_textures.gd`.

1. **Particles** (`-d`, as text): all of `particles/blood_impact/` (83) and
   `particles/impact_fx/` (297), plus `particles/water_impact/water_splash_03*`
   and `water_splash_01_blood`. Note each `C_OP_GameDecalRenderer`'s group,
   size and trace.
2. **Data:** `scripts/decalgroups.vdata_c` (`-b DATA`). GameTracking already
   has it and `IE` as text, so this only confirms them.
3. **Decals:**
   - the materials the groups name: 97 impact materials, the 37 blood options
     and the 8 spray materials, with their colour, occlusion and normal
     textures (fetch only the named options, since the blood folder is
     about 45 MB);
   - `materials/decals/system/rt_decal_impact_wound_stub.vmat_c`;
   - `materials/blood/blood_default_{color,impact,normal}.vtex_c`;
   - `characters/models/shared/materials/character_blood/default/*`.
4. **Textures** that the decompiled particles name, listed after step 1.

**What VCS 72 allows.** Since CS2's 2026-09-23 update, Source2Viewer-CLI 20.0
cannot read the shaders, so a material comes out incomplete (Sid). Textures
and the KV3 files (`.vpcf`, `.vdata`) are not affected. `BulletImpacts.read_hole`
needs a decal material's `DecalWorldWidth`, `DecalDepth`, `g_flCutoffAngle` and
texture names. Three ways round it:
- (a) Try `-b DATA` on a material, which may list its parameters without the
  shader (*Inferred*; check it).
- (b) Pair textures by file name: `blood_decals_10_NN` goes with its `_color`,
  `_ao_blr` and `_normal_blr`.
- (c) Reuse the hole materials already on disk from before the update.

The materials exported are all decal and effect materials, none of them a
character's or the map's, except `character_blood`. That one is a character
material: keep it out of `assets/` character folders and write it under
`assets/effects/impacts/` only.

## 8. Checks in CS2

1. With `sv_cheats 1; bot_stop 1; host_timescale 0.1`, shoot a bot's chest,
   stomach and leg with a Glock, an AK and an AWP, with and without kevlar.
   Record how big the spray is, and how many splats land behind the bot and
   how far away.
2. Headshot a bot with and without a helmet: sparks or blood? Does a kevlar
   body hit spark too?
3. Get shot from in front and from behind. Is there blood on your screen?
4. Hit a teammate in a friendly-fire match to see the friendly effect.
5. Does a hole fade at 30 s? Does a hole look bigger from 1500 units? Look at
   glancing holes on asphalt, metal and wood.
6. Which holes do dust2's brick and sand walls get: rock or brick, dirt or
   sand?
7. Do wounds stay on the body after the hit, and on the ragdoll?
8. With `cl_predict_body_shot_fx` at 1 and at 0, when does the blood appear
   against the hit sound?
