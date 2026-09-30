# The AUG's and SG 553's scope view

What CS2 shows when the AUG or SG 553 scopes, how this build draws it, and
what is still inferred. Written 2026-09-30 for Sid's playtest ask ("the ssg
needs a real scoped view like this example from cs2", with a CS2 screenshot).

## Sources

| Tag | Source | Date or build |
|---|---|---|
| *GT* | SteamDatabase/GameTracking-CS2 `master`: `game/csgo/steam.inf`, `game/csgo/pak01_dir.txt` (the VPK's file list), `DumpSource2/convars.txt`, `game/csgo/pak01_dir/resource/csgo_english.txt` | CS2 1.41.8.6, client 2000919, built Sep 28 2026 |
| *WV* | `reference/weapons/vdata.csv`, from CS2's `scripts/weapons.vdata` | 1.41.8.2 |
| *AG* | `reference/animgraph/viewmodel.md` and `parameters.md`, from CS2's `viewmodel_gun.vnmgraph` | 1.41.8.3 |
| *Valve* | Valve's CS2 release notes, `ckreisl/cs-updates-as-json` `data/cs2/updates_raw.json` | to 2026-09-22 |
| *Sid* | Sid's CS2 screenshot, 3838 x 2158, dust2, playing a T bot | 2026-09-28 build (its corner stamp) |

## The screenshot is the SG 553

The screenshot shows the gun raised to the eye: a scope housing with four
hex bolts filling the middle of the screen, a clear round lens with a black
rim, the world magnified inside it and a green dot in its middle. That is
the SG 553 (or AUG) view, not the SSG 08's:

- The dot is the AUG's and SG 553's scope dot. CS2's settings call it that
  ("Scope dot scale", "Use crosshair color for scope dot",
  `cl_ironsight_usecrosshaircolor`, *GT*), and it is green because the
  crosshair is. Valve: "Adjusted AUG and SG 553 scope dot sizes" and "Added
  game options for dot scale and sniper rifle scope thickness"
  (2025-10-02).
- The ammo reads 19 with 3 magazines; the SSG 08 holds 10 (*WV*
  `m_iMaxClip1`). The player is a T, and the SG 553 is the T's.
- The SSG 08, AWP, SCAR-20 and G3SG1 set `m_bHideViewModelWhenZoomed`
  (*WV*): scoped, the gun goes away and the full-screen black scope is
  drawn (`panorama/images/hud/scope/`, *GT*), as `ScopeOverlay` already
  does. The AUG and SG 553 do not, and alone carry the iron-sight fields.

Asked of Sid in the thread whether he wants it on the SG 553 and AUG, as
CS2 has it (built here), or on the SSG anyway.

## How CS2 builds it

- **The gun comes up to the eye.** The first-person graph's Idle is "a 1D
  blend on `weapon_ironsight_amount` of idle at 0, IronsightPose at 1"
  (*AG*), and `weapon_is_using_ironsights` is "weapon_type is one of
  weapon_sg556, weapon_aug, weapon_temp and weapon_ironsight_amount >= 0.1"
  (*AG*). While it is, the gun's normal firing clip is not played (the ATK
  states' slot is empty for them, *AG*). Both sets carry `ironsight_fidget`
  and `ironsight_shoot` clips (`reference/weapons/models.md`).
- **How fast.** `m_flIronSightPullUpSpeed` 10 and
  `m_flIronSightPutDownSpeed` 8 on both (*WV*). Read here as the share of
  the way a second, so 0.1 s up and 0.125 s down (*Inferred*: the names,
  and the zoom's own 0.1 s in, `m_flZoomTime1`).
- **The field of view.** The world zooms to `m_nZoomFOV1` 45 over 0.1 s
  (*WV*). `m_flIronSightFOV` is 45 too (*WV*). Read here as the arms' field
  of view at the eye, where the hip's is `viewmodel_fov` 68 (*Inferred*:
  as the world's it would repeat the zoom's). With both at 45 the scope is
  drawn true to its model, and its axis, which the pose puts through the
  eye, lands in the middle of the screen whatever the field of view.
- **Steadiness.** `m_flIronSightLooseness` 0.03 and
  `m_flIronSightPivotForward` 8 (SG 553) and 10 (AUG) (*WV*): the gun barely
  sways at the eye. Here the walk bob and turn sway fade out as the gun comes
  up; the kick still moves it.
- **The lens.** The scope's glass is its own material:
  `materials/models/weapons/v_models/rif_sg556/rif_sg556_scope_glass` and
  `rif_aug/rif_aug_scope_glass`, beside `shared/scope/scope_sg556`,
  `scope_aug`, `scope_lens_dirt`, `scope_filter` and
  `scope_dot_white_color` (*GT*). The render state is not in the file
  list: `r_csgo_stencil_sniper_zoom` (development only, *GT*) and Valve's
  "Fixed AUG scope stencil filter bug near water surfaces" (2025-02-04)
  say the lens is a stencil. Sid's screenshot shows the lens clear and the
  view through it continuous with the world at the zoom's field of view
  (*Inferred* by eye: no extra magnification in the lens).
- **The dot.** `scope_dot_white` tinted, red by default or the crosshair's
  colour with `cl_ironsight_usecrosshaircolor` (*GT*; the default colour
  is from memory, unverified). Sized by "Scope dot scale".
- **The crosshair** is not drawn while up (Sid's screenshot).

## What this build does

- `WeaponData.iron_sight_fov`, `iron_sight_pull_up_speed`,
  `iron_sight_put_down_speed` from the three vdata fields; `has_iron_sight`
  true for the AUG and SG 553 only.
- `Weapon.iron_sight_amount(now)`: 0 to 1, up at the pull-up speed from the
  press that scopes, down at the put-down speed from the one that unscopes.
  View only.
- `ViewModel.raise_to_eye`: fades into `ironsight_fidget` (the pose at the
  eye, *Inferred* to be IronsightPose's clip) over the rest of the way up,
  back to the idle over the way down; fires `ironsight_shoot` while up; a
  shot or reload running is left to finish first. The glass surfaces
  (`scope_glass`, `scope_lens` in the material name) get
  `scope_lens.gdshader`, a faint tint drawn as the arms are.
- `PlayerView._follow_scope`: the arms' field of view goes from 68 to 45
  with the amount, and the muzzle flash follows it (`ARMS_FOV_META`).
- `IronSightOverlay`: the dot in the crosshair's colour once the gun is 90%
  up, and the crosshair put away (`GameHud.shows_crosshair`). Where the
  gun's model is not extracted (the cloud, CI), a drawn stand-in housing
  and black rim, sized off Sid's screenshot.
- `tests/run_iron_sight_checks.gd`.

Nothing new needs extracting: the SG 553's and AUG's models and clips come
with the `weapons` and `weapon-animations` steps Sid has already run.

## Not done, and Local checks

1. **The look beside CS2.** Scope the SG 553 and the AUG on dust2 beside
   CS2: where the scope sits, its size, whether the lens reads clear, the
   dot's size and colour.
2. **IronsightPose's clip.** Whether the SG 553's variation of
   `viewmodel_gun.vnmgraph` puts `ironsight_fidget` in IronsightPose: in the
   extracted `graph_data.txt`, the `viewmodel_gun.vnmgraph+sg556` entry's
   clip for that node.
3. **`m_flIronSightFOV`.** If the scope looks too big or too small against
   CS2's, the reading above is wrong and the arms keep 68: one line in
   `PlayerView._follow_scope`.
4. **The outside of the lens.** `scope_filter` suggests CS2 filters the
   world round the scope; Sid's screenshot looks slightly soft there. Not
   drawn here.
5. **The dot's default colour** (red, from memory) against "Use crosshair
   color for scope dot"; this build always takes the crosshair's.
6. The lens dirt (`scope_lens_dirt`) is drawn clear, not dirty.

## Players' critiques

- None found for the AUG and SG 553 scope view itself in Valve's notes;
  Valve's own changes were the dot's size and usability at range
  (2025-01-28 "Adjusted scope dot on AUG/SG to be more useable at range",
  2025-10-02 the dot size and scale option).
