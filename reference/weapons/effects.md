# Tracers and muzzle flashes

What is seen of a shot: the tracer from the muzzle to where the round
stopped, and the gun's muzzle flash, in first person and third. Built
2026-09-24 (`src/effects/`), from CS2's own effect files. No research page
covered muzzle flashes; this page says where each number was read and what
is inferred. Tracers were covered by `reference/research/combat.md` R10.

## Where it comes from

- **The effects.** CS2's particle systems (`.vpcf`) do not run in Godot.
  Every file in `particles/weapons/cs_weapon_fx/` and
  `particles/unified_weapon_fx/` in `pak01_dir.vpk` (CS2 1.41.8.3) was
  decompiled with Source 2 Viewer's `-d` and read operator by operator. Their
  numbers are in `Tracers` (the ten tracer effects the guns name in
  `m_szTracerParticle`) and `FlashTable` (every flash, its layers, and which
  one each gun plays in each view). Nothing reads the `.vpcf` files at run
  time: their numbers were typed from them, with the file named beside each.
  A CS2 update that changes an effect needs them read again.
- **Which flash a gun plays.** First person: the `CNmParticleEvent` on each
  gun's first-person fire clip (`assets/.../viewmodel/clip_data.txt`), with
  its `m_config`. Third person: the same event on the gun's third-person
  shoot clips (`animation/anims/world/*/shoot_*`). A config sets the effect's
  control points, whose values scale its layers (sizes, counts, lifetimes,
  alpha). `FlashTable.FLASHES` carries every gun's flash in each view already
  worked out, so nothing is computed from control points at run time.
- **The muzzle.** Each gun model's `muzzle_flash` attachment (and
  `muzzle_flash2`: the M4A1-S's and USP-S's silencer tip, the Dual Berettas'
  left pistol), read from `weapons/models/*/weapon_*.vmdl`: an offset on the
  `weapon_offset` bone (the Berettas' `weapon_r` and `weapon_l`), in
  `Muzzles.POINTS`. vdata's `m_vecMuzzlePos0` and `1` are the same points seen
  from the eye in the first-person idle pose, which the effects checks hold
  them to (within 0.002 in for every gun but the R8, 0.2 in off; its bone is
  trusted). vdata.md's note calls them "the model's units", which is the wrong
  frame; `weapon_tables.gd` now says so for the next regeneration.
- **The textures.** `scripts/extract_assets.sh effects` fetches the eleven
  the tracers and flashes draw with, into `assets/effects/`. The flames,
  steam and smoke are sprite sheets; Source 2 Viewer writes them a trimmed
  image a frame, and `scripts/effect_textures.gd` puts every frame back where
  the texture's data block says it was, so each sheet is one texture again,
  with its frames' rectangles in `<name>.sheet.json`.
- **CS2's settings** (GameTracking-CS2 `DumpSource2/convars.txt`, read
  2026-09-24): `cl_tracer_frequency_override 1` (development-only, so fixed
  in the shipped game), `sv_sniper_tracer_mode 1`,
  `sv_sniper_tracer_innacuracy 0.085` and `_length 200`,
  `r_drawtracers_firstperson true`.

## Tracers

| Effect | Guns | Speed | Longest | Width | Notes |
|---|---|---|---|---|---|
| `pistol` | every pistol | 18,000 | 900 | 1 core, 1.3 glow | yellow-white |
| `shot` | the shotguns | 24,000-24,500 | 900 | 1, 1.3 | none under 150 units |
| `assrifle` | Galil, FAMAS, AK-47, M4A4, M4A1-S | 20,500 | 1200 | 1, 1.5 | white |
| `rifle` | AWP | 30,000 | 900 | 2 (yours), 1 | starts 20 units out |
| `rifle_ssg` | SSG 08, G3SG1 | 30,000 | 900 | 2 | none under 150 units |
| `rifle_scar` | SCAR-20 | 30,000 | 900 | 2 | |
| `smg` | the SMGs but the MP5-SD | 18,000 | 400 | 3.75 | a streak sliding down a still beam |
| `assrifle_aug` | AUG, SG 553 | 20,500 | 400 | 4 to 6 | the same |
| `mach` | M249, Negev | 15,500 | 400 | 2.5 to 7.5 | the same |

- **Which rounds.** Every round of a gun with tracers: the override replaces
  the guns' every-third. A silenced gun (M4A1-S and USP-S silencer on,
  MP5-SD) draws none: that the override leaves their 0 alone is inferred.
  A sniper round more than 0.085 inaccurate (CS2's tangent) draws 200 units.
- **How long.** A trail flies from the muzzle to where the round stopped at
  its speed and is gone as it arrives (an AK's across 500 units lives 24
  ms). It shows from a fifth of its way, full by 30%, fading over its last
  5%. Its streak is its trail time times its speed, growing in over its
  first 0.05 to 0.1 s, capped, never behind the muzzle. Each is aged by the
  simulation time since its round, at the time the frame falls at, so it
  looks the same at any frame rate.
- **Your own** is twice as long as anyone else's (CS2's CP3.x, which a
  designer's note in `weapon_tracers_rifle_wisp` ties to first person), and
  starts where the first-person gun is drawn: the view model's narrower field
  of view widens a point's place in the view, as Source's
  `FormatViewModelAttachment` does.
- **Through a wall.** The tracer ends at the first wall, and a fainter,
  slower streak (`weapon_wallbang_risidual_tracers`: 10,500 u/s, 500 units,
  half the alpha) goes on to where the round stopped. That CS2 ends the
  tracer there is inferred: no tracer has any collision, and CS2 has
  separate `impact_wallbang_heavy`/`_light` effects that carry the streak.
- **The look.** The core is CS2's `spark` texture, recoloured through its
  gradient by brightness (white-hot to orange); the glow the `sparks` sheet's
  soft teardrop through its own. How the renderers' UV scales and offsets
  read is inferred (the shader could not be read).

## Muzzle flashes

Every gun's flash is CS2's, per view: the flames (sprites from the
`fire_gas_batch_b_top`, `wispy_steam_burst_b` and `fire_small_sim_b` sheets),
the beams and the compensator and brake streaks (`wispy_steam_set`), the
sparks, the smoke and a light. Most flashes pick at random shot to shot, as
CS2's `C_OP_ChooseRandomChildrenInGroup` does: a rifle's is one of its flame,
its other flame (twice as likely) or a beam with a smoke puff, and two of
nothing, a compensator streak and sparks. A flame rides the barrel as the gun
kicks; sparks and smoke stay where they were made. In first person the flash
is drawn with the view model's projection, as the gun is; the SSG 08's brake
smoke and the R8's alt-fire flash are world effects, as CS2 has them.

Smoke is lit by the scene's sun and ambient, from whichever side the light
is on, a tenth of its colour its own (CS2's self-illumination for most).

Left out: the particles' noise, curl and wind forces, depth feathering, the
smoke's shadows and each smoke's own self-illumination, motion-vector sheets
and extra texture layers, the trails' tapers, CS2's bloom-only renderers
(stood in for, below), skewed random draws (drawn uniform), the sniper vapour trails
(`weapon_tracers_rifle_wisp`), the Zeus's wires, and the rope tracers' heat
shimmer. The AWP clip's second ground-smoke event is left out: with no
attachment and no config, CS2 would make it at the map's origin (inferred).

What makes a flash look as big and bright as it does in CS2 is mostly
its bloom: every flame has a second renderer that draws only into CS2's
effects bloom, which is blurred and added over the frame. How far that blur
spreads is not in the files. A soft glow card behind each flame (CS2's
`particle_glow_04`, 1.6 times the flame, at 0.2) stands in for it, set by
eye against Sid's screenshot of a Glock's flash
(`reference/cs2 _screenshots/Glock_muzzleflash.png`); stronger, it hazes the
gun white. The flames' and tracers' colours are CS2's 0-255 as they are, not
decoded from sRGB: the screenshot's flame is yellow-white at its core, which
CS2's overbright gives only that way. Ours still reads a little smaller than
the screenshot's (Local check 7).

The flash's light is an `OmniLight3D` for CS2's light's life (25 to 52 ms),
its range the particle's radius times 0.5 (inferred), fading only to its
range (Godot's own falloff is by the metre and left the hand a tenth of
it), its colour CS2's as it is, and its brightness CS2's intensity times its
alpha times `MuzzleFlashes.LIGHT_ENERGY` (50), set by eye so a Glock's
flash lights the glove, as it does in Sid's screenshot. A Glock's light is a
quarter of a rifle's in CS2's numbers, so a rifle's lights the front of the
gun orange.

## What it costs

Drawn per frame, never in the tick: the events are taken as the tick hands
them out and played on the next frame. Every card (a tracer's core and glow,
each flash particle) goes into one MultiMesh a texture, blend and view,
refilled each frame, so a spray of flashes is a few draw calls. A flash is
10 to 30 particles for 0.05 to 1 s; the lights are a pool of eight.

Measured on dust2 with its bots fighting (75 s of a round, headless, the
CPU side only): 0.38 ms a frame while anything is drawn, 0.26 ms median,
1.1 ms at the 95th percentile, 2.3 ms at most, up to 81 cards. The textures
are read as the map loads (`ShotEffects.prepare`, 25 to 30 ms): read on the
first flash of a fight, the 4096 by 2048 flame sheet held that frame up
12 ms.

## Local checks (Sid)

1. **Every round, and silenced.** Spray an AK-47 at a wall with
   `host_timescale 0.1`: does every round draw a tracer (the override), and
   does a silenced M4A1-S draw none?
2. **Your tracer against a bot's.** A pistol's is 900 units yours, 450 a
   bot's (CP3.x): compare one fired past you with your own.
3. **Through a wall.** Shoot through a dust2 door: does the tracer end at
   it, and what carries on?
4. **Up close.** Freeze a tracer and a flash (`host_timescale 0.01`) and
   screenshot them next to ours: the streak's bright head and tail, the
   flame's size and reach (the Deagle's faint flame 15 to 35 units out), the
   AWP's ground dust.
5. **The light.** How far and how brightly a flash lights your hand and a
   wall (80 units a rifle, 70 a pistol, 160 a machine gun or shotgun), in
   shade and in sun, to set `LIGHT_ENERGY`; that silenced guns cast none.
6. **Size on screen.** A distant tracer's width at 1080p: about 1 pixel a
   pistol's, 2 an AWP's.
7. **The flash's bloom.** Against CS2 side by side (a few guns, first person
   and third), tune `MuzzleFlashes.BLOOM_SIZE` and `BLOOM_STRENGTH`, set so
   far against one screenshot of a Glock.
