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
| dust2 lighting | Sun, sky, fog, exposure | The glTF's one light gives the sun's direction; `light_environment`, `env_sky`, `env_cubemap_fog` and the `post_processing_volume` in the entity lump give its colour and brightness, the sky material (exported as an equirect HDR `.exr`), the haze and the exposure window. No baked bounce light, which on dust2 is a lot (`bouncescale` 1.75): shadows are lit by the sky and a warm ambient floor instead. |
| dust2 nav mesh | No | Bake our own for bots. |
| Sounds | Yes | |
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
