# Getting CS2 assets in

`scripts/extract_assets.sh` does the extraction and `src/map/map_importer.gd`
does the import. Both have been run against real CS2 content (Source 2 Viewer
20.0, September 2026), and what is written here is what was observed then.
The importer is also tested against glTFs that Godot generates and re-reads,
so the mechanism is checked on machines without the game.

## Tool

[Source 2 Viewer / ValveResourceFormat](https://github.com/ValveResourceFormat/ValveResourceFormat),
which browses VPK archives and decompiles Source 2 assets. It has a
[command line utility](https://s2v.app/ValveResourceFormat/guides/command-line.html)
suitable for scripting, which is what `scripts/extract_assets.sh` uses so
extraction is repeatable rather than a manual chore.

The script deliberately does not hardcode paths inside the VPKs. It lists the
archive and picks out what it needs, because those paths move between game
updates and a hardcoded one fails silently a year from now. `list-map` and
`list-weapons` show what is actually in there.

## What comes out

| Asset | Exports? | Notes |
|---|---|---|
| Weapon and player models | Yes, glTF 2.0 / GLB | Geometry, materials, textures and the skeleton. Animations export automatically. |
| dust2 world geometry | Yes, glTF | 3613 meshes, 4.5M triangles, 648 PNGs. In metres, Y-up. |
| dust2 collision | Yes, glTF | A separate export of `world_physics.vmdl_c`: 39 meshes, 435k triangles, grouped by surface type and by what they interact with. Player clips included. |
| dust2 entities | Yes, text | `default_ents.vents_c` decompiles to key/value text: 15 T and 15 CT spawns, bomb sites, buy zones, the sun. |
| dust2 3D skybox | Yes, glTF | A separate map (`maps/prefabs/de_dust2/de_dust2_skybox.vpk`) built at a sixteenth of the scale around a `sky_camera` at (-8, -308, 202). Imported through MapImporter scaled by 16 about that point, with no collision. Its ground and far buildings are named `*_skybox`, which is why "skybox" is no longer a hint to hide a material; sky domes are found by their `sky.vfx` shader instead. Source 2 draws it in a pass of its own before the world, depth cleared in between; here it is ordinary geometry, and its terrain, at the skybox's own ground level, showed through wherever the map's floor lies below that (eye height under CT spawn's awning, floor at -70). So its materials are replaced by ones that squeeze their depth against the far plane (`src/map/far_materials.gd`, `far.gdshaderinc`, `MapImporter.behind_everything`): the map wins the depth test everywhere and the skybox still sorts among its own parts. Which end of the buffer is far depends on the renderer (Forward+ and Mobile reverse it), which the material is told. |
| Player models | Yes, glTF | `characters/models/*` are stubs. The meshes are the agents under `agents/models/*` with `thirdperson_body`, `thirdperson_default_gloves`, `firstperson_default_gloves_arms` and `firstperson_sleeves` meshes and an 86-94 bone skeleton. Each embeds ~2,000 animations (a gigabyte); asking the export for one clip by name keeps the skeleton and leaves them behind. |
| View model | Assembled at runtime | Each first-person clip's glTF carries two rigs: the 56-bone view-model rig the arms follow and the weapon's own rig (bolt, magazine, trigger, muzzle), as siblings. Nothing in the clip places the weapon rig; in the game it hangs off the arm rig's `wpn` bone, so `ViewModel` pins it there on every skeleton update. The agent's arm meshes are skinned to bones the view-model rig lacks (the forearm twist bones carry weight; spine and legs are bound with none), which are added to the rig at setup under their nearest present ancestor. Bone names match across agent, rig and weapon, so no retargeting. The shared `_default_rifle` clips carry the M4A1-S weapon rig and are that weapon's clips; `rifle_ak` is the AK's. |
| Third-person model | Assembled at runtime | The world locomotion clips (`animation/anims/world/rifle/_default_rifle/`) carry the 74-bone world rig and no weapon rig, with locomotion in place (no root motion track). `PlayerModel` adopts the agent's `thirdperson_*` meshes onto that rig, keeps the weapon on its own skeleton and pins its root bone to the rig's `wpn`. The agent's bind pose and the world rig's rest pose agree bone for bone (checked), which is what makes the adoption exact. |
| First-person body | Assembled at runtime | The same model on the local player, with `head_0`, `neck_0`, `arm_upper_L` and `arm_upper_R` folded to a thousandth (`RigModel.fold_bones`): the skin gathers at those joints, inside the body. It stands 8 units behind the eyes so the collar stays below the view until you look down. Godot's glTF import drops the clips' constant scale tracks, but the fold takes any that survive out of this model's own copies of the clips rather than trusting that; a `SkeletonModifier3D` was tried first and lost to the clip's track in 4.7's update order. |
| Hitboxes | Yes, in the model description | Each agent's `.vmdl_c` decompiles (Source2Viewer-CLI `-d`) to KV3 text with a `HitboxSetList`; the `cstrike` set is 19 `HitboxCapsule`s, each a radius and two points in its `parent_bone`'s space, in units, with a `group_id` in Source's numbering (1 head, 2 chest, 3 stomach, 4/5 arms, 6/7 legs, 8 neck). The decompile also writes the meshes and a few animations out, so it goes through a scratch directory and only the description is kept beside the glTF. `HitboxSet` parses it; `SkinnedHitboxes` puts an unscaled `Hitbox` area per capsule under the bot and moves them to their bones on every skeleton update (physics shapes take no scale, and the model is scaled 39.37 from metres). Bone names differ in case between the description (`leg_upper_l`) and the glTF (`leg_upper_L`). Drawn over the model, the capsules sit on the body standing and running. |
| Death and flinch animations | Deaths yes; flinches not usable yet | `animation/anims/world/shared/death_{chest,gut,rknee}_{a,b}` and `death_rshoulder` are absolute poses over the world rig and play as one-shots that hold their last frame. The `flinch_*` clips beside them are additive: every bone's translation zero and rotation near identity except the part that flinches, meant to be added over the locomotion. Played whole they fold the body to its origin. They wait for an `AnimationTree` add layer and are not extracted. |
| First-person animations | Yes, glTF each | CS2 keeps animations as files: `animation/anims/viewmodel/rifle/{_default_rifle,rifle_ak,rifle_m4a4}/*.vnmclip_c`, over `animation/skeletons/characters/viewmodel.vnmskel_c` (69 bones). Each exports as a glTF with one animation. World-model clips are under `animation/anims/world/`. |
| dust2 lighting | Sun, sky, fog, exposure | The glTF's one light gives the sun's direction; `light_environment`, `env_sky`, `env_cubemap_fog` and the `post_processing_volume` in the entity lump give its colour and brightness, the sky material (exported as an equirect HDR `.exr`), the haze and the exposure window. |
| dust2 lightmaps | Yes, `.exr` + `.png` | `maps/de_dust2/lightmaps/irradiance.vtex_c` (8192 square, BC6H, 78 MB; the sky and bounce light reaching each surface, HDR) and `directional_irradiance.vtex_c` (4096 square: which way that light mostly comes from, in tangent space, and how directional it is). The sun is not in them: CS2 computes it live, with `direct_light_shadows` as its shadow mask, which is not fetched since Godot's shadow map does that job. Every world surface carries lightmap coordinates in the glTF's second UV set, already scaled by Source 2 Viewer to the texture (its `GetScaledLightmapUvAccessor`); a debug render of the game's own chart-colour map (`debug_chart_color.vtex_c`) over the geometry lands one colour on each face with the seams at the edges, which is the alignment check. The shading is Source 2 Viewer's `ComputeLightmapShading` less its curvature term. Godot's ambient is turned off on those surfaces (`ambient_light_disabled`) and the lightmap's result added as emission times albedo and occlusion, which is the same term by another door. `lightmap_energy` 0.4 scales it into Godot's units alongside the sun (measured against a CS2 screenshot of B site: shaded ground 0.27 in both, shaded wall 0.24 against 0.20). |
| dust2 lightmapped props | Yes, in the same maps | Props are `csgo_vertexlitgeneric` (and foliage), merged by model into aggregate nodes, and each placed prop is baked one of three ways, which its second UV set tells: as lightmap charts, laid out at the world's texel density (0.75 a unit on dust2; 1,238 of the 2,010 merged primitives, measured over a sample of triangles, within an eighth to four times the world's median); collapsed onto a single texel of its own in a dense block at one corner of the atlas, which holds that instance's light (the map's light-probe result, baked); or absent. A few models carry their own second UV set instead, ten to forty times denser (`dust_arch_01_pattern`, `dust_wall_braces`, the `dust_shipping_crate_02` set at four to eight), and are left alone. The lit props are 1,339 surfaces on dust2, the awnings' planks and posts among them. |
| dust2 light probes | Not yet | 43 `env_combined_light_probe_volume` entities with `maps/de_dust2/lightmaps/env_light_probe_volume_*_octree.dat` beside the lightmaps: what CS2 lights the remaining props, the players and the weapons with. Until they are read, the ambient for those is the lightmap's average light, (0.44, 0.42, 0.43) on dust2, measured once by `scripts/prepare_export.gd` into `lightmaps/average.json` and set by MapLighting at the lightmapped surfaces' own energy. Neutral grey rather than the sky's blue, which is the difference between a barrel in shade and a barrel in a blue room. |
| dust2 nav mesh | No | Bake our own for bots. |
| Sounds | Yes, one file each | Each sound is a `.vsnd_c` that decompiles to the audio it holds (wav, a few mp3), a few numbered variants to a set: `sounds/weapons/ak47/ak47_01..04` are the AK's shots, `sounds/player/footsteps/sand_01..12` the sand steps, `land_sand_*` the landing. `scripts/extract_assets.sh sounds` fetches the two weapons' shots, reload parts and draws, footsteps and landings for the surfaces the hull names, and the hit feedback (`kevlar*`, `headshot_*`, `bodyshot_kill`): 284 files, 19 MB. `SoundBank` finds a set by the stem its variants share and plays it through one `AudioStreamRandomizer`, so shots overlap. The sound event definitions (`soundevents/game_sounds_weapons.vsndevts_c`) that carry the game's volumes and distances are not fetched; those are by ear. Footsteps map the hull part's material name to a set (`Footsteps.SURFACE_SETS`); Godot's 3D audio is in metres, so the players' `unit_size` is 10 m in inches. Bullet impacts are `sounds/physics/{concrete,surfaces,metal,wood}/*_impact_bullet*` by surface, mapped from the hull part's name like the footsteps. |
| Bullet holes | Yes, png | `materials/decals/{concrete/bullethole_concrete_1-5,plaster/plaster1-2_bullet,metal/bullethole_metal_1-3}_color` decompile to 256-square RGBA pngs with the hole in the alpha; fetched with the sounds into `assets/decals/`. `BulletImpacts` projects one as a `Decal` of 5 units into the surface at each hit, spun at random, up to 96 at once with the oldest reused. |
| Weapon tuning numbers | **No** | See below. |

Docs: [models](https://s2v.app/ValveResourceFormat/guides/exporting-models.html),
[maps](https://s2v.app/ValveResourceFormat/guides/exporting-maps.html).

What dust2 turned out to be:

- **Metres.** The exporter bakes in 0.0254 and the Z-up to Y-up turn: Source
  (x, y, z) inches lands at glTF (y, z, x) x 0.0254. The importer scales by
  exactly 1/0.0254, after which entity coordinates can be used as
  `Vector3(y, z, x)` with no further conversion. Checked by dropping a player
  at all 30 spawn points: each lands on floor.
- **The hull is a separate file.** Exporting the world also writes a
  `world_physics.gltf`, but that one is only the brush entities (buy zones,
  bomb targets, place names). The real hull comes from exporting
  `world_physics.vmdl_c` by itself, and arrives as `world_physics_physics.gltf`.
  Its node names carry the surface type (`physics_group_concrete`, `_wood`,
  `_sand`...) and the interaction layer (`physics_npcclip_playerclip`,
  `physics_csgo_grenadeclip`, `physics_passbullets_*`), which is what
  footsteps, penetration and grenades will want. Player clips do survive, so
  no hand-authored clip layer is needed.
- **Tool and effect geometry comes along** in the visible world: light
  blockers spanning the whole map, light shafts, steam cards. Every material
  carries its vmat path and shader flags as glTF extras, and the importer hides
  anything under `materials/tools/` or `materials/effects/`.
- **Overlays come out a foot off their walls.** glTF has no depth bias, so the
  exporter pushes anything that relies on one out along its vertex normals. It
  pushes 0.3937 m, which is 15.5 units: 0.01 times the inches in a metre, where
  a hundredth of an inch was evidently meant. Every overlay on dust2 (signs,
  wall stains, road markings, the bombsite X) measured exactly 15.50 units off
  the surface behind it. The one solid material affected, the kasbah window
  insets (`F_DEPTH_BIAS`), fares worse, because pushing a shape along its own
  normals inflates it: a window inset compared with its source model fitted
  "position + 15.48 x normal" to a twentieth of a unit, and looked like a flared
  box standing proud of the hole it belongs in. `src/map/export_offset_fix.gd`
  does the arithmetic backwards on the exported `.bin` before Godot imports it,
  leaving a quarter of a unit, which is what Valve's own non-overlay signage
  stands off by. What qualifies is `F_OVERLAY`, `F_DEPTH_BIAS` and the
  `csgo_static_overlay` shader; nothing else on the map was displaced. Worth
  reporting upstream, and worth re-measuring after a Source 2 Viewer update:
  if they fix it, this would over-correct.
- **Most walls and ground are two layers, and a glTF carries one.** 60 of
  dust2's materials are `csgo_lightmappedgeneric` with `F_LAYERS`: two sets of
  textures mixed by a weight painted on the vertices and broken up by a mask,
  so plaster gives way to brick along a ragged edge. The export has the first
  layer only, which made every kasbah wall its rough layer from end to end
  and every change of ground a straight line. Three things put it back:
  - `scripts/extract_assets.sh layers` fetches the 72 textures the glTF had no
    slot for (second-layer colour, second-layer normal with roughness in its
    alpha, and the blend mask), reading their names out of the material
    descriptions the export keeps in each material's extras. A raw decompile
    of a normal texture is identical, channel for channel, to what the glTF
    export writes for layer 1, so they need no conversion.
  - The paint is a float VEC4 vertex attribute, `_TEXCOORD_4`, which Godot's
    importer silently drops: it looks up the names it knows. Renamed to
    `COLOR_0` (`src/map/export_paint_channel.gd`) it arrives as vertex colour,
    bit for bit: every one of the 16.6 million components is an exact multiple
    of 1/255, and Godot stores vertex colour as 8 bits a channel with no sRGB
    conversion. The first component is the weight; the other three are equal
    to each other, differ from the first on 13% of vertices, and are not used
    by this shader.
  - `src/map/blend_material.gdshader` follows Source 2 Viewer's implementation
    of the same shader (`complex.frag.slang`, `ApplyBlendModulation`): weight
    from the paint's first component, mask from the blend texture's green,
    `smoothstep` between mask minus and plus a softness that comes from the
    mask's red (`F_FANCY_BLENDING` 1) or from `g_flBlendSoftness` (2), a
    weight of one being all layer 2, normals mixed as texels. The tinted band
    along the edge (`g_flLayerBorder*`) is not in their implementation, so
    ours is a reading of the parameter names and nothing better.
- **The lightmap is one image, and Godot's importer is not in a hurry.** The
  irradiance decompiles to a 314 MB float `.exr`; the import compresses it to
  BC6H (90 MB), which takes about four minutes the first time. There is no
  way to hand Godot the game's BC6H blocks as they are, which would be
  instant; the decompiler writes pixels, not blocks.
- **Textures need telling.** Godot imports them lossless with no mipmaps
  unless it sees them drawn in the editor, which never happens for a map built
  at runtime. `scripts/write_import_settings.gd` writes the import settings
  ahead of the import: VRAM compression, mipmaps, and normal maps flagged from
  the glTF's materials rather than from filenames. 1 GB of video memory
  instead of 4.
- Importing takes Godot about a minute the first time and seconds after.
  Loading the map at runtime takes a few seconds.

## The weapon numbers are not extractable

Damage, armour ratio, penetration, recoil seeds and the inaccuracy/spread model
live in `scripts/weapons.vdata_c`, and no published artifact carries the
values: the entity schema has the field names with zeroed templates, the item
definitions hold only presentation metadata, and demo streams never carry
static game data.

Source: <https://github.com/CS2OpenDev/CS2OpenDev-SchemaTracker/issues/16>

So making the AK feel right is a measurement job, not an import job:

1. Start from the CS:GO-era weapon scripts, which were plain text and carried
   the recoil and inaccuracy fields. CS2 inherited most of this model.
2. Use published spray patterns as the target to match, e.g.
   [op.gg](https://op.gg/cs2/spray-patterns) and
   [csdb](https://csdb.gg/recoil-patterns/).
3. Fire 30-round sprays at a wall in our build, plot the impacts, and tune
   until the plot overlays the reference.

That means a spray-pattern test range with impact plotting is an early build,
not a late one. It is the same tuning loop the movement HUD provides, pointed
at ballistics instead.

## Licensing

Extracting from your own CS2 installation for a private build is normal modding
practice. Valve's models, textures, sounds and map geometry cannot be
redistributed, and that includes committing them to a public repository, so
`assets/` is gitignored and stays that way.
