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
  (*WV*). `m_flIronSightFOV` is 45 too (*WV*). Treating that as the arms'
  projection was disproved by Sid's 2026-10-01 playtest: the scope was far
  too small. The extra viewmodel framing needed to match CS2 is inferred.
  The arms projection here is calibrated from the screenshots below;
  the world still uses the game's 45 and aiming is unchanged.
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
- `ViewModel.raise_to_eye`: fades into `ironsight_fidget` (confirmed as
  IronsightPose's clip in both extracted graph variations) over the rest of the way up,
  back to the idle over the way down; fires `ironsight_shoot` while up; a
  shot or reload running is left to finish first. The glass surfaces
  (`scope_glass`, `scope_lens` in the material name) get
  `scope_lens.gdshader`, black at the hip and fading to a faint clear tint
  at the eye. It changes the glass's transparency, without cutting the
  housing mesh or rendering a second view. Each model owns its glass material.
- `PlayerView._follow_scope`: the arms' field of view goes from 68 to the
  model's calibrated scoped framing (SG 553: 9; AUG: 10) with the amount,
  and the muzzle flash follows it (`ARMS_FOV_META`). These are viewmodel
  values, not changes to the vdata or the world zoom. The lens shader and
  the housing use the same instance-uniform slot (10), so their projections
  agree even though the clear lens has no light-probe uniforms.
- `IronSightOverlay`: the dot in the crosshair's colour once the gun is 90%
  up, and the crosshair put away (`GameHud.shows_crosshair`). Where the
  gun's model is not extracted (the cloud, CI), a drawn stand-in housing
  and black rim, sized off Sid's screenshot.
- The test range uses the same scope dot and crosshair visibility as comp.
- `iron_sight_focus.gdshader` slightly blurs the complete scene outside
  the central lens, including the gun and distant background, as Sid
  clarified from the CS2 reference on 2026-10-01. The clear circle uses
  the same 46%-of-height framing as the lens. A canvas layer below the
  HUD reads the finished 3D frame, so transparent effects are included
  and the dot and HUD stay sharp. The blur fades with the gun's raised
  amount; at the hip the layer is hidden and draws no screen-copy pass.
  Its mipmap level 1.5 at 1080p and two-pixel edge feather are visual
  approximations, scaled with resolution, rather than extracted CS2 values.
- `tests/run_iron_sight_checks.gd`, including the view's scope/hip projections
  and, where extracted, the real model/clip setup.

Nothing new needs extracting: the SG 553's and AUG's models and clips come
with the `weapons` and `weapon-animations` steps Sid has already run.

## Local framing measurement, 2026-10-01

Sid's [PR review screenshots](https://github.com/sidcarrollworks/CSGODOT/pull/169#issuecomment-5938980088)
show the SG 553's clear opening about 330 pixels across in a 720-pixel-high
scaled view of CS2 (46% of the image height), against about 70 pixels in
the corresponding game screenshot. The sight clip aligns the lens with
the eye, but using the vdata's 45 for the arms produces that small view.

Rendered 1920 x 1080 test-range captures with the extracted models were
used to fit the arms' projection: SG 553 at 9 and AUG at 10 give openings
about 490–500 pixels across. Values are Source's horizontal-at-4:3 FOV,
converted by `ViewModelProjection`, so sizing follows screen height at
other resolutions and aspect ratios. The different values account for
the models' different lens diameters and scope tube lengths. These are
measured visual approximations; a direct CS2 AUG comparison remains open.
The pose and model distance stay as exported, preserving the tube's
proportions. Scoping changes no bullet, recoil, zoom, or movement rules.

The extracted `graph_data.txt` maps IronsightPose to `ironsight_fidget_aug`
and `ironsight_fidget_sg556` in the corresponding graph variations.

With the scene frozen in the scoped pose, turning the focus pass off/on/off
preserved the lens's central 220 x 180 pixels exactly and left all 2,610
white HUD text pixels in the sampled region unchanged. The outside wall
changed as expected. On the RTX 4070 Ti at 1920 x 1080, median viewport GPU
time over 210 warmed frames per variant was 0.364 / 0.493 / 0.364 ms:
about 0.13 ms for the scoped screen copy, mipmaps and filter. At 3786 x 2130
(the window's near-4K size), it was 1.686 / 2.149 / 1.682 ms, about 0.46 ms.
These are isolated test-range render costs, not competitive-match timings.

Both local model exports were checked for missing external files: all
14 AUG and nine SG 553 textures and both geometry buffers are present,
as are the 15 first-person clip exports and their buffers. The additional
CS2 `scope_filter` and `scope_lens_dirt` assets are not separately extracted;
the focus filter and clear tint here approximate their appearance.

## Not done, and Local checks

1. **The look beside CS2.** Scope the SG 553 and the AUG on dust2 beside
   CS2: where the scope sits, its size, whether the lens reads clear, the
   dot's size and colour.
2. **AUG comparison.** Its current framing uses the SG screenshot's
   opening size; compare directly with an AUG in CS2 before treating it as exact.
3. **Scoped framing.** Further visual tuning belongs in
   `ViewModel.IRON_SIGHT_ARMS_FOV`; the game's world zoom remains 45.
4. **Focus tuning.** Compare the slight outside-lens blur directly with
   CS2, especially under recoil: its central circular mask is fitted to
   the reference, not a stencil taken from the animated glass geometry.
5. **The dot's default colour** (red, from memory) against "Use crosshair
   color for scope dot"; this build always takes the crosshair's.
6. The lens dirt (`scope_lens_dirt`) is drawn clear, not dirty.

## Players' critiques

- None found for the AUG and SG 553 scope view itself in Valve's notes;
  Valve's own changes were the dot's size and usability at range
  (2025-01-28 "Adjusted scope dot on AUG/SG to be more useable at range",
  2025-10-02 the dot size and scale option).
