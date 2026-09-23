# Every gun's files

Written by `scripts/weapon_tables.gd` on 2026-09-22 from what `scripts/extract_assets.sh weapons` extracted out of CS2 1.41.8.1. Do not edit by hand: re-run the extraction, or the script on its own. Paths are relative to the roots below; a dash is something the extraction did not produce.

- Models: `res://assets/weapons/weapons/models/<folder>/`, one glTF for the gun and one for its magazine.
- First person: `res://assets/characters/animation/anims/viewmodel/<set>/`, one glTF per clip, each carrying the arms' and the gun's skeletons. The shared `_default_` sets are the M4A1-S's (`rifle/_default_rifle`) and the USP-S's (`pistol/_default_pistol`); SMGs, shotguns, snipers and machine guns are all `rifle/` sets.
- Third person: `res://assets/characters/animation/anims/world/<set>/`, the gun's own draw, idle, reload and fire, standing and crouched, over the shared locomotion of `rifle/_default_rifle` or `pistol/_default_pistol`.
- Skeletons: `res://assets/characters/animation/skeletons/weapons/<name>.vnmskel`.
- Icons: `res://assets/hud/panorama/images/icons/equipment/<class less weapon_>.svg`, from `scripts/extract_assets.sh hud`; the M4A1-S and USP-S have `_off` icons for the silencer off.
- The sniper scope's overlay: `res://assets/hud/panorama/images/hud/scope/`, `scope_circle_png.png`, `scope_lens_tga.png`, `scope_line_blur_tga.png`; the game composes it in code: the mask's opening over the lens's tint, with the cross drawn in the soft line.

| Class | Sheet row | Folder | Model | Magazine | First person | Third person | Skeleton | Icon |
|---|---|---|---|---|---|---|---|---|
| `weapon_glock` | Glock-18 | `glock18` | `weapon_pist_glock18.gltf` | `weapon_pist_glock18_mag.gltf` | `pistol/pistol_glock18` (8) | `pistol/pistol_glock` (9) | `glock18` | `glock.svg` |
| `weapon_hkp2000` | P2000 | `hkp2000` | `weapon_pist_hkp2000.gltf` | `weapon_pist_hkp2000_mag.gltf` | `pistol/pistol_hkp2000` (8) | `pistol/pistol_hkp2000` (9) | `hkp2000` | `hkp2000.svg` |
| `weapon_usp_silencer` | USP-S (no silencer) | `usp_silencer` | `weapon_pist_usp_silencer.gltf` | `weapon_pist_usp_silencer_mag.gltf` | `pistol/_default_pistol` (11) | `pistol/pistol_usp` (11) | `usp_silencer` | `usp_silencer.svg` |
| `weapon_elite` | Dual Berettas | `elite` | `weapon_pist_elite.gltf` | `weapon_pist_elite_mag.gltf` | `pistol/pistol_elite` (11) | `pistol/pistol_elite` (10) | `elite` | `elite.svg` |
| `weapon_p250` | P250 | `p250` | `weapon_pist_p250.gltf` | `weapon_pist_p250_mag.gltf` | `pistol/pistol_p250` (8) | `pistol/pistol_p250` (9) | `p250` | `p250.svg` |
| `weapon_tec9` | Tec-9 | `tec9` | `weapon_pist_tec9.gltf` | `weapon_pist_tec9_mag.gltf` | `pistol/pistol_tec9` (6) | `pistol/pistol_tec9` (7) | `tec9` | `tec9.svg` |
| `weapon_fiveseven` | Five-SeveN | `fiveseven` | `weapon_pist_fiveseven.gltf` | `weapon_pist_fiveseven_mag.gltf` | `pistol/pistol_fiveseven` (8) | `pistol/pistol_fiveseven` (9) | `fiveseven` | `fiveseven.svg` |
| `weapon_cz75a` | CZ75 Auto | `cz75a` | `weapon_pist_cz75a.gltf` | `weapon_pist_cz75a_mag.gltf` | `pistol/pistol_cz75a` (11) | `pistol/pistol_cz75a` (16) | `cz75a` | `cz75a.svg` |
| `weapon_deagle` | Desert Eagle | `deagle` | `weapon_pist_deagle.gltf` | `weapon_pist_deagle_mag.gltf` | `pistol/pistol_deagle` (9) | `pistol/pistol_deagle` (9) | `deagle` | `deagle.svg` |
| `weapon_revolver` | R8 Revolver | `revolver` | `weapon_pist_revolver.gltf` | - | `pistol/pistol_revolver` (17) | `pistol/pistol_revolver` (10) | `revolver` | `revolver.svg` |
| `weapon_nova` | Nova | `nova` | `weapon_shot_nova.gltf` | - | `rifle/rifle_nova` (5) | `rifle/rifle_nova` (7) | `nova` | `nova.svg` |
| `weapon_xm1014` | XM1014 | `xm1014` | `weapon_shot_xm1014.gltf` | - | `rifle/rifle_xm1014` (6) | `rifle/rifle_xm1014` (7) | `xm1014` | `xm1014.svg` |
| `weapon_sawedoff` | Sawed-Off | `sawedoff` | `weapon_shot_sawedoff.gltf` | - | `rifle/rifle_sawedoff` (5) | `rifle/rifle_sawedoff` (7) | `sawedoff` | `sawedoff.svg` |
| `weapon_mag7` | Mag-7 | `mag7` | `weapon_shot_mag7.gltf` | `weapon_shot_mag7_mag.gltf` | `rifle/rifle_mag7` (5) | `rifle/rifle_mag7` (7) | `mag7` | `mag7.svg` |
| `weapon_mac10` | MAC-10 | `mac10` | `weapon_smg_mac10.gltf` | `weapon_smg_mac10_mag.gltf` | `rifle/rifle_mac10` (5) | `rifle/rifle_mac10` (7) | `mac10` | `mac10.svg` |
| `weapon_mp9` | MP9 | `mp9` | `weapon_smg_mp9.gltf` | `weapon_smg_mp9_mag.gltf` | `rifle/rifle_mp9` (5) | `rifle/rifle_mp9` (7) | `mp9` | `mp9.svg` |
| `weapon_mp7` | MP7 | `mp7` | `weapon_smg_mp7.gltf` | `weapon_smg_mp7_mag.gltf` | `rifle/rifle_mp7` (5) | `rifle/rifle_mp7` (7) | `mp7` | `mp7.svg` |
| `weapon_mp5sd` | MP5-SD | `mp5sd` | `weapon_smg_mp5sd.gltf` | `weapon_smg_mp5sd_mag.gltf` | `rifle/rifle_mp5sd` (6) | `rifle/rifle_mp5sd` (9) | `mp5sd` | `mp5sd.svg` |
| `weapon_ump45` | UMP-45 | `ump45` | `weapon_smg_ump45.gltf` | `weapon_smg_ump45_mag.gltf` | `rifle/rifle_ump45` (5) | `rifle/rifle_ump45` (7) | `ump45` | `ump45.svg` |
| `weapon_p90` | P90 | `p90` | `weapon_smg_p90.gltf` | `weapon_smg_p90_mag.gltf` | `rifle/rifle_p90` (5) | `rifle/rifle_p90` (7) | `p90` | `p90.svg` |
| `weapon_bizon` | PP-Bizon | `bizon` | `weapon_smg_bizon.gltf` | `weapon_smg_bizon_mag.gltf` | `rifle/rifle_bizon` (7) | `rifle/rifle_bizon` (7) | `bizon` | `bizon.svg` |
| `weapon_galilar` | Galil AR | `galilar` | `weapon_rif_galilar.gltf` | `weapon_rif_galilar_mag.gltf` | `rifle/rifle_galilar` (6) | `rifle/rifle_galilar` (7) | `galil` | `galilar.svg` |
| `weapon_famas` | FAMAS | `famas` | `weapon_rif_famas.gltf` | `weapon_rif_famas_mag.gltf` | `rifle/rifle_famas` (5) | `rifle/rifle_famas` (7) | `famas` | `famas.svg` |
| `weapon_ak47` | AK-47 | `ak47` | `weapon_rif_ak47.gltf` | `weapon_rif_ak47_mag.gltf` | `rifle/rifle_ak` (11) | `rifle/rifle_ak` (7) | `ak47` | `ak47.svg` |
| `weapon_m4a1` | M4A4 | `m4a4` | `weapon_rif_m4a4.gltf` | `weapon_rif_m4a4_mag.gltf` | `rifle/rifle_m4a4` (5) | `rifle/rifle_m4a4` (7) | `m4a4` | `m4a1.svg` |
| `weapon_m4a1_silencer` | M4A1-S (no silencer) | `m4a1_silencer` | `weapon_rif_m4a1_silencer.gltf` | `weapon_rif_m4a1_silencer_mag.gltf` | `rifle/_default_rifle` (7) | `rifle/rifle_m4a1_silencer` (9) | `m4a1_silencer` | `m4a1_silencer.svg` |
| `weapon_sg556` | SG 553 | `sg556` | `weapon_rif_sg556.gltf` | `weapon_rif_sg556_mag.gltf` | `rifle/rifle_sg556` (7) | `rifle/rifle_sg556` (7) | `sg556` | `sg556.svg` |
| `weapon_aug` | AUG | `aug` | `weapon_rif_aug.gltf` | `weapon_rif_aug_mag.gltf` | `rifle/rifle_aug` (8) | `rifle/rifle_aug` (7) | `aug` | `aug.svg` |
| `weapon_m249` | M249 | `m249` | `weapon_mach_m249.gltf` | `weapon_mach_m249_mag.gltf` | `rifle/rifle_m249` (7) | `rifle/rifle_m249` (7) | `m249` | `m249.svg` |
| `weapon_negev` | Negev | `negev` | `weapon_mach_negev.gltf` | `weapon_mach_negev_mag.gltf` | `rifle/rifle_negev` (9) | `rifle/rifle_negev` (7) | `negev` | `negev.svg` |
| `weapon_ssg08` | SSG 08 | `ssg08` | `weapon_snip_ssg08.gltf` | `weapon_snip_ssg08_mag.gltf` | `rifle/rifle_ssg08` (10) | `rifle/rifle_ssg08` (7) | `ssg08` | `ssg08.svg` |
| `weapon_awp` | AWP | `awp` | `weapon_snip_awp.gltf` | `weapon_snip_awp_mag.gltf` | `rifle/rifle_awp` (5) | `rifle/rifle_awp` (7) | `awp` | `awp.svg` |
| `weapon_g3sg1` | G3SG1 | `g3sg1` | `weapon_snip_g3sg1.gltf` | `weapon_snip_g3sg1_mag.gltf` | `rifle/rifle_g3sg1` (5) | `rifle/rifle_g3sg1` (7) | `g3sg1` | `g3sg1.svg` |
| `weapon_scar20` | SCAR-20 | `scar20` | `weapon_snip_scar20.gltf` | `weapon_snip_scar20_mag.gltf` | `rifle/rifle_scar20` (8) | `rifle/rifle_scar` (7) | `scar20` | `scar20.svg` |

## The clips in each set

By the name the file carries, less the set's suffix (`draw_ak` is `draw`). `shoot1` is the firing clip; `lookat01` the inspect; a pistol's `_empty` clips are for the last round, with the slide back.

| Class | First person | Third person |
|---|---|---|
| `weapon_glock` | draw, idle, idle_slide_back, lookat01, reload_empty, reload, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload_empty_crouch, reload_empty, reload, shoot |
| `weapon_hkp2000` | draw, idle, idle_slide_back, lookat01, reload_empty, reload, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload_empty_crouch, reload_empty, reload, shoot |
| `weapon_usp_silencer` | draw, draw_silenced, idle, idle_slide_back, lookat01, reload_empty, reload, shoot1, shoot_empty, silencer_attach, silencer_detach | draw_crouch_pistol, draw, idle_crouch, idle, reload_crouch, reload_empty_crouch, reload_empty, reload, shoot, silencer_attach, silencer_detach |
| `weapon_elite` | draw, idle, idle_leftempty, idle_leftrightempty, lookat01, reload, shoot_left1, shoot_leftlast, shoot_right1, shoot_rightlast, ui_keychain | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot_left1, shoot_leftlast, shoot_right1, shoot_rightlast |
| `weapon_p250` | draw, idle, idle_slide_back, lookat01, reload_empty, reload, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload_empty_crouch, reload_empty, reload, shoot |
| `weapon_tec9` | draw, idle, lookat01, reload, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_fiveseven` | draw, idle, idle_slide_back, lookat01, reload_empty, reload, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload_empty_crouch, reload_empty, reload, shoot |
| `weapon_cz75a` | draw2, draw, idle, idle_slide_back, lookat01, reload2, reload2_empty, reload, reload_empty, shoot1, shoot_empty | draw2_crouch, draw2, draw_crouch, draw, idle_crouch, idle, reload2_crouch, reload2, reload2_empty_crouch, reload2_empty, reload_crouch, reload, reload_empty_crouch, reload_empty, shoot_cz75, shoot_empty_cz75 |
| `weapon_deagle` | draw, idle, idle_slide_back, lookat01, lookat02, reload, reload_empty, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, reload_empty_crouch, reload_empty, shoot |
| `weapon_revolver` | chamber_position_anim_revolver_0, chamber_position_anim_revolver_1, chamber_position_anim_revolver_2, chamber_position_anim_revolver_3, chamber_position_anim_revolver_4, chamber_position_anim_revolver_5, chamber_position_anim_revolver_6, chamber_position_anim_revolver_7, draw_2, draw, dryfire, idle, lookat01, prepare_shoot, reload, shoot1, shoot_alt1 | draw2_crouch, draw2, draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot_alt, shoot |
| `weapon_nova` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_xm1014` | bullet_hide, draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_sawedoff` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_mag7` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_mac10` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload__crouch, reload, shoot |
| `weapon_mp9` | draw, idle, lookat01, reload, shoot1 | draw__crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_mp7` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_mp5sd` | draw2, draw, idle, lookat01, reload, shoot1 | draw2_crouch, draw2, draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_ump45` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_p90` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_bizon` | draw, idle, lookat01, lookat01_draw, lookat01_transfix, reload, shoot1 | draw, draw_crouch, idle, idle_crouch, reload, reload_crouch, shoot |
| `weapon_galilar` | draw, idle, lookat01, lookat01_transfix, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_famas` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_ak47` | draw, idle, lookat01, lookat01_draw, lookat01_transfix, lookat03, lookat03_draw, lookat03_transfix, lookat_draw, reload, shoot1 | draw, draw_crouch, idle, idle_crouch, reload, reload_crouch, shoot |
| `weapon_m4a1` | draw, idle, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_m4a1_silencer` | draw, idle, lookat01, reload, shoot1, silencer_attach, silencer_detach | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot, silencer_attach, silencer_detach |
| `weapon_sg556` | draw, idle, ironsight_fidget, ironsight_shoot, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_aug` | draw, idle, ironsight_fidget, ironsight_shoot, lookat01, lookat01_draw, reload, shoot1 | draw, draw_crouch, idle, idle_crouch, reload, reload_crouch, shoot |
| `weapon_m249` | bullet_hide, draw, idle1, idle_from_activity, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_negev` | bullet_hide, draw, empty_reload, idle_from_activity, idle, lookat01, reload, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_ssg08` | draw, draw_ssg08_lgcy, idle, idle_ssg08_lgcy, lookat01, lookat01_ssg08_lgcy, reload, reload_ssg08_lgcy, shoot1, shoot1_ssg08_lgcy | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_awp` | draw, idle, lookat01, reload, shoot1 | draw, draw_crouch, idle, idle_crouch, reload, reload_crouch, shoot |
| `weapon_g3sg1` | draw, idle1, lookat01, reload, shoot1 | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
| `weapon_scar20` | draw, idle, idle_slide_back, lookat01, reload_empty, reload, shoot1, shoot_empty | draw_crouch, draw, idle_crouch, idle, reload_crouch, reload, shoot |
