# Every gun: the todo list

Sid, 2026-09-22: build all the other guns, with every number from the CS2
weapon sheet (`cs2_weapon_sheet.csv`, explained in `README.md` beside this
file). This widens the scope from the AK-47 and M4A1-S alone.

The list is split by where the work can happen:

- **Local** needs Sid's machine: CS2, Source2Viewer-CLI, the extracted
  `assets/`, or someone playing the game. Sid's local agent takes these.
- **Remote** is code, data and headless tests. A project thread (the cloud
  sessions) can do these without the assets, testing against stand-ins.

Neither side waits on the other to start. Local extraction can begin today;
the remote work builds against the sheet and falls back to no model, the way
the two rifles already do when `assets/` is missing.

Rules that apply to both: branch and PR, never main; `assets/` is never
committed; the sheet is the source for every number it has, and anything
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

## Local (Sid's machine)

Roughly in order; L1 to L3 can start at once.

- [ ] **L1. Extract every weapon model.** Widen `list_weapons` and
  `extract_weapons` in `scripts/extract_assets.sh` from `(ak47|m4a1)` to all
  34, still anchored to `^weapons/models/` so keychain charms stay out. Keep
  the glTF, materials and animations flags the rifles use. Print the list the
  filter found, and write the class-to-model-path table it discovers to
  `reference/weapons/models.md` so the remote side can use the names.
- [ ] **L2. Extract the animation sets per weapon class.** First person:
  `animation/anims/viewmodel/<class>/...` for pistol, SMG, shotgun, rifle,
  sniper and machine gun sets, with the skeletons, the way the rifle sets are
  fetched today. Third person: the matching `anims/world/<class>` locomotion,
  shoot, reload and draw clips. Record which clip set each weapon uses.
- [ ] **L3. Extract every weapon's sounds.** Fire, distant fire, the reload's
  parts, draw, and for the modes: silencer on and off, zoom in and out, burst.
  Widen `SOUND_FILTER`; list the files per weapon in
  `reference/weapons/sounds.md` so `WeaponSounds` can be filled in remotely.
- [ ] **L4. Scope overlays.** The scope textures and the zoom sounds for the
  AWP, SSG 08, G3SG1, SCAR-20, AUG and SG 553.
- [ ] **L5. Measure what the sheet does not have**, in CS2, per weapon, into
  `reference/weapons/measured.csv`:
  reload time (to rounds in, and to ready), draw time, and for the snipers the
  zoom levels (FOV per level) and time to scope in. Frame-by-frame, the way
  the recoil timings were taken.
- [ ] **L6. Spray patterns for every "Set Pattern" weapon**, by the procedure
  in `reference/spray_patterns/README.md`, from 496 units at the range's wall
  so every pattern has a known scale: CZ75 Auto, R8 Revolver, XM1014, all
  seven SMGs, Galil AR, FAMAS, M4A4, SG 553 and its scope, AUG and its scope,
  M249, Negev, G3SG1, SCAR-20. Re-take the M4A1-S at 20 rounds while there;
  its plot has 25 (CS:GO's old magazine), and a 496-unit AK spray retires
  `recoil_scale` for both rifles.
- [ ] **L7. Fit each model.** Viewmodel offset per weapon at CS2's
  `viewmodel_fov`, the weapon in the third-person hand, the muzzle point for
  effects. Needs the models on screen.
- [ ] **L8. Playtest each weapon at the range** against the sheet: fatal
  headshot ranges with K and N on the dummy, accurate range, tapping, spray.

## Remote (a project thread)

- [ ] **R1. A weapon registry off the sheet.** One entry per class above:
  sheet row and mode rows, model path, clip set, sound set, slot
  (pistol/primary), pattern file, reload and draw time, all read from files
  (`cs2_weapon_sheet.csv`, and `models.md`, `sounds.md`, `measured.csv` as
  they land). `WeaponLibrary` builds any of the 34 from it; a test builds
  every row and checks it against the sheet. Missing assets fall back to no
  model, as now.
- [ ] **R2. Semi-automatic fire.** "Hold to Shoot: No" fires once a click
  (`WeaponData.automatic` is already read).
- [ ] **R3. Weapon modes.** Right click switches mode where the sheet has
  one: burst (FAMAS, Glock), silencer on and off with its attach time (M4A1-S,
  USP-S), fan fire (R8). A mode reads its own row over the weapon's.
- [ ] **R4. Scopes.** Zoom levels, scoped mobility and accuracy from the
  scoped rows, the sniper unscoping after a shot, the scope overlay (L4) when
  it exists.
- [ ] **R5. Shotguns.** Pellets per shot (Bullets), each traced and damaged
  on its own, shorter range.
- [ ] **R6. Random recoil.** Weapons marked "Random" kick by Recoil Amount
  with the two variances rather than by a pattern file. Needs how CS turns
  those into degrees; research first.
- [ ] **R7. The R8's hammer.** Its first round waits on a trigger pull delay;
  the sheet says "see note". Research first.
- [ ] **R8. Slots, switching, drop and pick up.** Knife, pistol, primary;
  number keys and the scroll wheel (scroll up is jump today; ask Sid); a
  weapon on the ground; bots carrying what they bought.
- [ ] **R9. Buy menu and money.** Price and kill award are in the sheet.
  Belongs with round flow (roadmap phase 4); needs Sid's call on whether the
  economy is in scope.
- [ ] **R10. Tracers.** Every round, every third, or none, per the sheet.
- [ ] **R11. Penetration and tagging** for every weapon, off the sheet's
  penetration and tagging power (roadmap items 2 and 7).
- [ ] **R12. HUD per weapon.** Ammo and reserve, the mode, the weapon's icon
  once extracted.
- [ ] **R13. Cross-check the sheet against CS2's own weapons.vdata**, which
  SteamDatabase's GameTracking-CS2 repository publishes decompiled. Bring in
  what the sheet lacks: the slower recovery after the first rounds of a
  spray (`_final` recovery times and the rounds they blend over) and spread
  apart from inaccuracy. Flag any figure where the two disagree to Sid.

## Not in the sheet, and not on this list yet

Knife, grenades, the Zeus, and the bomb. Each needs its own numbers and Sid's
decision to include it.
