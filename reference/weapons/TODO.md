# Every gun: the todo list

Status checked against merged `main` on **2026-10-02**, through PR #172.
Completed implementation is checked below; direct CS2 measurements and
remaining visual comparisons stay open even where the feature is playable.

Sid, 2026-09-22: build all the other guns, with every number from the CS2
weapon sheet (`cs2_weapon_sheet.csv`, explained in `README.md` beside this
file). This widens the scope from the AK-47 and M4A1-S alone.

The list is split by where the work can happen:

- **Local** needs Sid's machine: CS2, Source2Viewer-CLI, the extracted
  `assets/`, or someone playing the game. Sid's local agent takes these.
- **Remote** is code, data and headless tests. A project thread (the cloud
  sessions) can do these without the assets, testing against stand-ins.

Neither side waits on the other to start. Local extraction can begin today;
the remote work builds against the game's numbers (`WeaponVData`, from the
committed `vdata.csv`) and falls back to no model, the way the two rifles
already do when `assets/` is missing.

Rules that apply to both: branch and PR, never main; `assets/` is never
committed; the game's files win over the sheet wherever they have the
number (`WeaponVData`; the sheet gives landing and ladder), and anything
measured by hand goes in `reference/` with how it was measured.

## The weapons

The 34 in the sheet, by CS2's entity class name, which is stable across
updates. Their model, animation and sound paths inside the VPK are not; find
those by listing (`scripts/extract_assets.sh list-weapons` once widened), not
by guessing.

| Class | Sheet row | Mode rows |
|---|---|---|
| Pistols | | |
| `weapon_glock` | Glock-18 | Glock-18 (burst) |
| `weapon_hkp2000` | P2000 | |
| `weapon_usp_silencer` | USP-S (no silencer) | USP-S (silencer) |
| `weapon_elite` | Dual Berettas | |
| `weapon_p250` | P250 | |
| `weapon_tec9` | Tec-9 | |
| `weapon_fiveseven` | Five-SeveN | |
| `weapon_cz75a` | CZ75 Auto | |
| `weapon_deagle` | Desert Eagle | |
| `weapon_revolver` | R8 Revolver | Revolver (Rapid Fire) |
| Shotguns | | |
| `weapon_nova` | Nova | |
| `weapon_xm1014` | XM1014 | |
| `weapon_sawedoff` | Sawed-Off | |
| `weapon_mag7` | Mag-7 | |
| SMGs | | |
| `weapon_mac10` | MAC-10 | |
| `weapon_mp9` | MP9 | |
| `weapon_mp7` | MP7 | |
| `weapon_mp5sd` | MP5-SD | |
| `weapon_ump45` | UMP-45 | |
| `weapon_p90` | P90 | |
| `weapon_bizon` | PP-Bizon | |
| Rifles | | |
| `weapon_galilar` | Galil AR | |
| `weapon_famas` | FAMAS | FAMAS (burst) |
| `weapon_ak47` | AK-47 | done |
| `weapon_m4a1` | M4A4 | |
| `weapon_m4a1_silencer` | M4A1-S (no silencer) | M4A1-S (silencer), done |
| `weapon_sg556` | SG 553 | SG 553 (scoped) |
| `weapon_aug` | AUG | AUG (scoped) |
| Machine guns | | |
| `weapon_m249` | M249 | |
| `weapon_negev` | Negev | |
| Snipers | | |
| `weapon_ssg08` | SSG 08 | SSG 08 (scoped) |
| `weapon_awp` | AWP | AWP (scoped) |
| `weapon_g3sg1` | G3SG1 | G3SG1 (scoped) |
| `weapon_scar20` | SCAR-20 | SCAR-20 (scoped) |

---

## First-shot accuracy while running (Sid, 2026-09-22)

The first shot while running must be as inaccurate as the running cone says.
Sid playtested it perfectly accurate. The cone was open, but spread was seeded
by the round's place in the pattern, so every first round landed on the same
spot, 0.9 degrees off the aim (a tenth of the AK's 10.3-degree running cone).
PR #24 seeds each round by the moment it was fired instead, so first rounds
land anywhere in the cone. It applies to every gun:

- Remote: R1's test fires each weapon's first round at a run and checks it
  lands anywhere in that weapon's running cone, not on one spot. The AK's
  version is `_test_first_rounds_go_anywhere_in_the_cone` in
  `tests/run_weapon_tests.gd`.
- Local: L8 checks it by feel. Run at the dummy and tap: most first rounds
  should miss the head at range, and they should not land in the same place.

## Local (Sid's machine)

Roughly in order; L1 to L3 can start at once.

- [x] **L1. Extract every weapon model.** *(done 2026-09-22: 78 models, the 34 guns, their magazines and the shell casings; `reference/weapons/models.md`)* Widen `list_weapons` and
  `extract_weapons` in `scripts/extract_assets.sh` from `(ak47|m4a1)` to all
  34, still anchored to `^weapons/models/` so keychain charms stay out. Keep
  the glTF, materials and animations flags the rifles use. Print the list the
  filter found, and write the class-to-model-path table it discovers to
  `reference/weapons/models.md` so the remote side can use the names.
- [x] **L2. Extract the animation sets per weapon class.** *(done 2026-09-22: 630 clips and skeletons, every gun's first- and third-person set, the pistols' locomotion; every gun builds in first person, checked by `run_model_checks.gd`)* First person:
  `animation/anims/viewmodel/<class>/...` for pistol, SMG, shotgun, rifle,
  sniper and machine gun sets, with the skeletons, the way the rifle sets are
  fetched today. Third person: the matching `anims/world/<class>` locomotion,
  shoot, reload and draw clips. Record which clip set each weapon uses.
- [x] **L3. Extract every weapon's sounds.** *(done 2026-09-22: every gun's folder, 743 sounds with the rest; `reference/weapons/sounds.md`)* Fire, distant fire, the reload's
  parts, draw, and for the modes: silencer on and off, zoom in and out, burst.
  Widen `SOUND_FILTER`; list the files per weapon in
  `reference/weapons/sounds.md` so `WeaponSounds` can be filled in remotely.
- [x] **L4. Scope overlays.** *(done 2026-09-22: `scripts/extract_assets.sh hud` fetches the overlay, three images the game composes in code, and every equipment icon; the zoom sounds came with L3; `models.md` lists both)* The scope textures and the zoom sounds for the
  AWP, SSG 08, G3SG1, SCAR-20, AUG and SG 553.
- [x] **L5. Measure what the sheet does not have** *(done 2026-09-22 from the game's own data rather than by hand: `timings.md` and `timings.csv` have every gun's draw, reload to rounds in and to ready, shotgun shell loop, silencer switch and sound timing, from the clips; `vdata.md` has the zoom levels, FOVs and zoom times, the deploy times and how soon a reload lets the gun fire, from `scripts/weapons.vdata`, which Source 2 Viewer 20.0 decodes)*, in CS2, per weapon, into
  `reference/weapons/measured.csv`:
  reload time (to rounds in, and to ready), draw time, and for the snipers the
  zoom levels (FOV per level) and time to scope in. Frame-by-frame, the way
  the recoil timings were taken.
- [ ] **L6. Spray patterns for every "Set Pattern" weapon** *(partly answered 2026-09-24 from a community source, not a measurement: `reference/spray_patterns/weapon_<class>.csv` has the M4A4, Galil AR, FAMAS, unscoped SG 553 and AUG, all seven SMGs, M249, Negev and CZ75-Auto, on the AK's scale, read by the game since the playtest of 2026-09-25 (issue 14: `WeaponLibrary.pattern_of`); its AK-47 and M4A1-S match the plots but for two swapped pairs of rounds each. The R8's fan fire and the XM1014 have no path to learn (Sid, 2026-09-24), and the scoped SG 553 and AUG are likely their unscoped paths scaled down by the game's scoped recoil (19 against 28, 16 against 24). Left: the G3SG1 and SCAR-20, one scoped spray each of the SG 553 and AUG to settle that, and the scale, which the 496-unit AK spray still settles; `README.md` there says how far to trust the rest)*, by the procedure
  in `reference/spray_patterns/README.md`, from 496 units at the range's wall
  so every pattern has a known scale: CZ75 Auto, R8 Revolver, XM1014, all
  seven SMGs, Galil AR, FAMAS, M4A4, SG 553 and its scope, AUG and its scope,
  M249, Negev, G3SG1, SCAR-20. Re-take the M4A1-S at 20 rounds while there;
  its plot has 25 (CS:GO's old magazine), and a 496-unit AK spray retires
  `recoil_scale` for both rifles.
- [ ] **L7. Fit each model.** *(partly answered 2026-09-22: in first person the clips place every gun themselves, with no offset of CS2's own to add, and all 34 render held and posed at `viewmodel_fov`; in third person all 34 sit in the hand on the `wpn` bone, with the player model using weapon-specific locomotion, including `world/pistol/_default_pistol`; the muzzle point is `m_vecMuzzlePos0` in `vdata.md`. Left for Sid: judging each on screen in play)* Viewmodel offset per weapon at CS2's
  `viewmodel_fov`, the weapon in the third-person hand, the muzzle point for
  effects. Needs the models on screen.
- [ ] **L8. Playtest each weapon at the range** against the sheet: fatal
  headshot ranges with K and N on the dummy, accurate range, tapping, spray,
  and the first shot while running (see below).

## Remote (a project thread)

- [x] **R1. A weapon registry off the sheet.** *(done 2026-09-23:
  `WeaponLibrary.build(class)` makes any of the 34 from `vdata.csv`, the
  sheet's landing and ladder, and `models.md`'s model and clips;
  `WeaponLibrary.all()` is all 34 and `ItemRegistry` names each by class;
  `run_contract_checks.gd` builds every one against the game's damage and
  magazine and fires its first round at a run inside its running cone. No
  spray pattern but the AK-47's and M4A1-S's (L6), and the AK's recoil
  settling time on the rest.)* *(2026-09-26, playtest issue 14: 15 more
  guns read their pattern from `reference/spray_patterns/weapon_<class>.csv`;
  the AK's settling time is still on every other gun.)* *(2026-09-22: numbers now come from the game, not the sheet: `WeaponVData.apply(data, class, alternate)` puts any of the 34 guns' figures on a `WeaponData` from the committed `vdata.csv`; read the sheet first only for landing and ladder, as `WeaponLibrary` does. The files are in `models.md`, `sounds.md`, `timings.csv`.)* One entry per class above:
  sheet row and mode rows, model path, clip set, sound set, slot
  (pistol/primary), pattern file, reload and draw time, all read from files
  (`cs2_weapon_sheet.csv`, and `models.md`, `sounds.md`, `measured.csv` as
  they land). `WeaponLibrary` builds any of the 34 from it; a test builds
  every row and checks it against the sheet, and that its first round at a
  run lands anywhere in its running cone. Missing assets fall back to no
  model, as now.
- [x] **R2. Semi-automatic fire.** *(done 2026-09-23: `Weapon.can_fire`
  holds a gun the game calls semi-automatic, `m_bIsFullAuto` false, to one
  round until the trigger comes up or `Weapon.press_trigger()` reports a
  fresh press; checked in `run_weapon_tests.gd` and, through commands, in
  `run_sim_checks.gd`. Thirteen guns: every pistol but the CZ75-Auto and the
  R8, the Nova, Mag-7 and Sawed-Off, the AWP and the SSG 08.
  `PlayerSim._update_weapon` calls `weapon.press_trigger()` for every press,
  preserving rapid release/press pairs inside a tick. To check in CS2 (Local): a click
  before the gun is ready fires when it is if held, and nothing if let go
  first; that is CS:GO's behaviour, assumed here.)* "Hold to Shoot: No" fires
  once a click.
- [ ] **R3. Weapon modes.** Right click switches mode where the sheet has
  one: burst (FAMAS, Glock), silencer on and off with its attach time (M4A1-S,
  USP-S), fan fire (R8). A mode reads its own row over the weapon's.
  *Audited 2026-10-02: [installed-build findings](../research/shooting-audit-2026-10-02.md)
  establish three-round burst scheduling and event-driven silencer mode
  changes. The [follow-up](../research/shooting-followup-2026-10-02.md)
  traces graph completion at 0.1 s remaining and holster gate cleanup;
  effective playback and earliest accepted input still need local captures.*
- [x] **R4. Scopes.** Zoom levels, scoped mobility and accuracy from the
  scoped rows, the sniper unscoping after a shot, the scope overlay (L4) when
  it exists. *(Done 2026-09-24, `tests/run_scope_checks.gd`: right click
  steps through `m_nZoomLevels` at `m_nZoomFOV1/2`, each level reached over
  its `m_flZoomTime`; scoped speed and inaccuracy are the game's second
  values; the AWP and SSG 08 unzoom as they fire and rezoom once the bolt is
  worked; a reload or a switch takes the scope down; the view hides the
  snipers' arms, draws the scope (CS2's mask where extracted) and slows the
  mouse by the zoomed fov over 90; no crosshair on the four snipers;
  noscope kills; bots scope before they fire. Guessed until the Local check
  in `reference/research/combat.md`: the scoped accuracy comes in linearly
  over the zoom time, and the zoom times are read as the time to reach each
  level. The zoom sounds play from `weapon_zoom` (`WeaponSounds`), a sniper coming out silent. Not done: the scope showing inaccuracy. The AUG and SG 553 raise the gun to the eye as they scope, with the lens clear, its dot in the crosshair's colour and no crosshair (2026-09-30, `tests/run_iron_sight_checks.gd`, `reference/research/scopes.md`, whose Local checks are the look beside CS2). Their scoped framing now matches the reference's roughly 46%-of-height opening, the outside scene is softly blurred, and the lens is black when lowered (Local rendering checked 2026-10-01, PR #169).)*
- [x] **R5. Shotguns.** Pellets per shot (Bullets), each traced and damaged
  on its own, shorter range. *(Done 2026-09-24 for the Nova, XM1014,
  Sawed-Off and MAG-7, the player's and the bots': a pull fires
  `m_nNumBullets` pellets, each its own trace, impact and hurt, in a fixed
  pattern `m_flSpread` wide from `m_nSpreadSeed`, which the rest of the cone
  throws whole (`Weapon.pellet_directions`, `tests/run_shotgun_checks.gd`).
  One report a pull. The pattern's shape is inferred; the Local check in
  `reference/research/combat.md` (R5) gives the real one.)*
  *Audited 2026-10-02: [R5 pattern parity](../research/shooting-audit-2026-10-02.md)
  now has the seeded radial-stratum table, firing-index lookup, 64-pellet
  boundary and per-pellet inaccuracy roll. The current repeated pattern
  plus shared offset remains an approximation; parity is not implemented.*
  *(2026-09-30, Sid's playtest: the Nova, XM1014 and Sawed-Off load a
  shell at a time (`m_bReloadsSingleShells`) rather than the whole tube
  after one: the reload clip's intro, its loop once a shell with the shell
  going in at `WPN_RELOAD_ADD_AMMO`, then its outro (`timings.csv`,
  `WeaponClips`); the arms and the loop's sounds repeat for every shell; a
  shot after `m_flDisallowAttackAfterReloadStartDuration` with a shell in
  stops the reload. The body others see still plays its reload clip once.)*
- [ ] **R6. Random recoil.** Weapons marked "Random" kick by Recoil Amount
  with the two variances rather than by a pattern file. Needs how CS turns
  those into degrees; research first. *(Researched 2026-09-24,
  `reference/research/combat.md`: every gun has a recoil seed, so
  "Random" kicks are probably a fixed sequence; the conversion to degrees
  is in no file and comes from a demo.)* *(2026-09-26, playtest issue 14:
  every gun with no pattern file now kicks the view and the weapon model
  by a PROVISIONAL amount, the AK-47's per-round kick times its
  `m_flRecoilMagnitude` over the AK's 30 (`WeaponData.view_kick_up`),
  leaning by `m_nRecoilSeed` and the round where the angle variance is not
  zero, and shrunk by the scoped magnitude when scoped. Its bullets do not
  climb: they stay on the cone and the per-shot penalty until the demo
  gives their path. That demo also decides whether the magnitude-scaled
  kick stays.)*
  *Audited 2026-10-02: [R6 binary findings](../research/shooting-audit-2026-10-02.md)
  recover tier0's RNG, 64-entry per-mode recoil generator, full-auto
  smoothing/attenuation and aim-punch constants. A demo can validate the
  port, but is no longer needed to guess the magnitude-to-velocity rule.
  The seeded bullet paths remain to implement.*
- [ ] **R7. The R8's hammer.** Its first round waits on a trigger pull delay;
  the sheet says "see note". Research first. *(Researched 2026-09-24,
  `reference/research/combat.md`: the shot is postponed to a set tick and
  fraction; the delay, about 0.2 s by community wikis, comes from a demo.)*
  *Audited 2026-10-02: [R7 binary findings](../research/shooting-audit-2026-10-02.md)
  establish 13 ticks (203.125 ms at 64 Hz), preserving the start fraction;
  primary/alternate cycles are 0.50/0.40 s. Mixed-button and cancellation
  cases remain local validation for the eventual implementation.*
- [x] **R8. Slots, switching, drop and pick up.** `Inventory` keeps each
  carried gun and its rounds through switching; 1 to 5, Q and wheel-down
  `invnext` select items, while wheel-up remains jump. G throws a physical
  drop on its extracted hull, walking takes an eligible item, and E takes
  the item looked at or swaps the gun in its occupied slot. PR #163 adds
  ground gun/grenade/bomb prompts using that same 80-unit use search.
  Bots buy and show whatever they hold. Bullets push native dropped guns;
  remaining blast impulses and CS2 comparison work are recorded under
  roadmap item 12.
- [x] **R9. Buy menu and money.** `Economy`, `BuyRules` and `BuyMenu` use
  weapon prices and kill awards, round/loss/plant/defuse income, buy zones,
  time and affordability. Purchases, refunds and Ctrl-click buy-and-throw
  are wired into competitive mode. Loadout selection and the short-handed
  bonus remain open in `reference/cs2-systems.md` (sections 2 and 3).
- [x] **R10. Tracers.** *(done 2026-09-24, with the muzzle flashes:
  `src/effects/`, `reference/weapons/effects.md`)* Every round of a gun
  with tracers, as CS2's client overrides the sheet's every-third
  (`cl_tracer_frequency_override 1`); none silenced. Each gun's own effect
  from its `.vpcf`: speed, length, width, colour, and a noscope's 200 units.
- [x] **R11. Penetration and tagging** for every weapon, off the game's
  penetration and tagging power (roadmap items 2 and 7). Tagging is done
  (PR #27): every weapon tags with its own figure, which `WeaponVData` reads
  from the game (PR #28; the sheet agrees). Penetration is done (roadmap
  item 7): every weapon goes through walls by its own `m_flPenetration`.
- [x] **R12. HUD per weapon.** `HealthAmmoCenter` shows ammo/reserve and
  `WeaponSelection` shows extracted item icons and what is carried; scoped
  weapons control crosshair/dot visibility. Mode indicators depend on R3's
  unfinished burst/silencer controls; this does not mark R3 complete.
- [x] **R13. Cross-check the sheet against CS2's own weapons.vdata** *(the check is done, locally, 2026-09-22: `vdata.md` has it, 914 values agree, and the one real difference, the Desert Eagle's jump inaccuracy, is flagged to Sid; runtime fields are now imported)*, which
  SteamDatabase's GameTracking-CS2 repository publishes decompiled.
  `WeaponVData` imports the spread and final recovery fields the sheet lacks;
  the Desert Eagle discrepancy stays recorded in `vdata.md`.
  *Done 2026-09-30: the spread is kept apart (`WeaponData.spread`), and the
  final recovery times blend in over their rounds on the recoil index
  (`WeaponData.recovery_time`). Audited 2026-10-02:
  [CS2 truncates the decaying float index before linear interpolation](../research/shooting-audit-2026-10-02.md).
  Our continuous blend, two-cycle index decay delay and missing 0.1 cutoff
  still need correction. The tenfold penalty recovery agrees; airborne
  recovery/state floors and vertical-speed inaccuracy also need parity
  work. The [follow-up](../research/shooting-followup-2026-10-02.md) also
  recovers immediate zoom mode/floor recovery and additive landing penalties
  from raw coefficients times fall speed. Our linear zoom blend and fixed/max
  landing cone still need correction. R13's data import is complete,
  not those formula fixes.*

## Not in the sheet

The knife, the Zeus, the six grenades and the bomb are all in scope. Their
numbers and their Local and Remote work are in `reference/cs2-systems.md`.
