# Extracting CS2's content

The map, models, animations, sounds and icons are Valve's, extracted from
your own CS2 install into `assets/`, which is gitignored and never
committed. Without them everything still runs on grey-box stand-ins, and
the checks that need them skip. `reference/asset-pipeline.md` has the
measurements behind each step, and what goes wrong.

## Running it

On a machine with CS2 installed, and with
[Source2Viewer-CLI](https://github.com/ValveResourceFormat/ValveResourceFormat/releases)
somewhere it can be found:

```sh
scripts/extract_assets.sh list-map     # see what is inside the dust2 VPK
scripts/extract_assets.sh map          # extract it, then import it into Godot (map de_mirage: another map)
scripts/extract_assets.sh weapons      # every gun: models and animations
scripts/extract_assets.sh equipment    # the bomb and kit, grenades, knives, Zeus
scripts/extract_assets.sh sounds       # the weapons' sounds, footsteps by surface, hits
```

`map` takes a few minutes and a little under two gigabytes. It pulls
thirteen things out of the game: the visible world as glTF with its textures, the
collision hull as a second glTF, the entity lump as text, the nav mesh the
game's bots walk, the volumes of the buy zones, bomb sites and callouts (with
the game's baked bomb damage), the radar and where it lies, CS2's surfaces
(each one's parent, its friction and what a round gets through), the second
texture layer of every material that has one (which a glTF has no room for),
the sky as an HDR panorama, the 3D skybox (the buildings and hills beyond the
map, a small map of their own, drawn behind everything as the game draws it),
the lightmaps the game baked its bounce light into, with the light probes
beside them, which parts of the map can be seen from which (what is not
seen from where you stand is not drawn, as in the game), and the map's
colour grade (its post-processing file: the filmic curve, the bloom and a
colour table, which `--grade cs2` draws with; `reference/research/cs2-post-processing.md`).
`physics`, `entities`, `nav`, `volumes`, `radar`, `surfaces`, `layers`,
`sky`, `skybox`, `lightmaps`, `visibility` and `postprocessing` fetch the
last twelve on their own; all but the lightmaps take seconds. The lightmaps are one 300 MB image, which
Godot's first import spends a few minutes compressing to 90; the probes are
720 small slices that the game packs into one file the first time it runs.

The nav mesh is the game's own, `maps/de_dust2.nav`: the floor cut into
2,242 convex areas, with the links between them that CS2's bots path over,
jumps and drops among them. `src/map/source_nav_mesh.gd` (`SourceNavMesh`)
reads it, after Source 2 Viewer's reader of the undocumented format, and
answers which area is under a point and how to get from one place to
another (`route` for the areas, `find_path` for points to walk through,
`walk_path` for the same pulled taut, which is what the bots walk: from their
spawn to a bomb site and back, jumping and crouching where the mesh says).
Without it they walk straight lines between their spawn points, and the map
says so in the top left. The file ends in the game's analysis of the mesh
(hiding spots, where the two sides meet on each route, how early each team
can reach each area), which is compressed KV3 and not read yet.

The buy zones, bomb sites and callouts are brush entities, which the world's
glTF and collision hull leave out (the world export's world_physics.gltf has
them, but named only by class): each is a small model of its own in the
map's archive, named by its entity. `src/map/brush_volume.gd` (`BrushVolume`) reads them as
convex solids, with a point test and shapes for an `Area3D`: one buy zone a
side, holding its side's 15 spawns, and the two sites, A an L of two boxes,
spanning the boxes the game baked its bomb damage for (A's baked box is its
L's bounds, notch and all, so a plant is tested against the volume). That bake
(`baked_bomb_damage.vdata`) samples 85,697 points on a 10-unit grid; its
boxes and grid are read, its damage values not yet. The radar is the game's
overview image and the text that places it over the map; `MapOverview` goes
from game space to the image and back.

`weapons` fetches every gun with its first- and third-person animations and
the game's weapon tuning, and `hud` the scope overlay and equipment icons.
`equipment` fetches the rest of what a player carries the same way: the bomb
and the defuse kit, the six grenades, the two default knives and the Zeus,
listed with the game's numbers and their clips' timings in
`reference/weapons/equipment.md`; `sounds` brings their sounds with the guns'.
`characters` fetches one player model per side (Phoenix and SAS) with their
skeletons, and the rifle animations, which in CS2 are files of their own:
the first-person set, and the third-person locomotion (eight-way run, walk
and crouch, idles, in-air, jump, shoot). `animgraphs` reads the logic that
plays those clips in CS2, its animation graphs (AnimGraph 2): what the game
tells them, how they blend and layer the clips, and at what speeds, written
out in `reference/animgraph/`; `reference/animgraph2.md` says what they are
and how much they give us. `all` does the lot.

`assets/` can live on another drive: make it a junction (`mklink /J`) and
every script and Godot itself read straight through it.

## Other maps

Every step for one map takes the map's name after it, `de_dust2` when there
is none, so any CS2 defusal map comes out the same way, into
`assets/maps/<name>` with its hull and 3D skybox beside it
(`<name>_physics`, `<name>_skybox`); dust2's paths are the ones they always
were. `map <name>` runs every one of that map's steps, and
`paths <name>` prints where they land without needing CS2:

```sh
scripts/extract_assets.sh map de_mirage     # all of mirage
scripts/extract_assets.sh nav de_inferno    # just inferno's nav mesh
```

Then play it with `maps/play/play.tscn`: set **Map Name** on its root, or
give `--map` on the command line, which wins over the scene's own
(`godot --path . maps/play/play.tscn -- --map de_mirage`; with no scene
named, the main scene, dust2's, takes `--map` too). There are no menus yet
(roadmap item 26). `MapLoader` (`src/map/map_loader.gd`) derives every path
from the name (`MapPaths`) and loads what is there; `Competitive`
(`src/modes/competitive.gd`) plays a match on it: you and the bots, the
match, money and buying in the map's buy zones, the bomb on its sites,
grenades, the HUD. Bots walk to the callouts named `BombsiteA` and
`BombsiteB`, or, where a map names its callouts otherwise, to the middle
of each bomb site's volume. Ladders, doors, breakables and hostage maps are
not built yet (roadmap item 24a).

The script finds everything itself: Source2Viewer-CLI on `PATH` or where the
release zip unpacks to in Downloads, CS2 by way of Steam's library list (so a
second drive is fine), Godot on `PATH` or the desktop, and the resources
inside the VPKs by listing them rather than hardcoding paths, which drift
between game updates. Override with `S2V=`, `CS2_PATH=` and `GODOT=` if it
guesses wrong.

## In the editor

Then open `maps/de_dust2/de_dust2.tscn` and press play. You start at one of
the map's own T spawn points (**Spawn Team** on the scene root switches sides),
colliding with the hull the game itself collides with, player clips included
(which stop you and not your rounds). None of the visible world is solid.

The game builds the map when it runs. In the editor, the scene's
**EditorPreview** node draws the map's geometry as it was exported (no
lightmaps, sky or skybox), so there is something to look at in the 3D view;
it is not saved into the scene and does nothing in the game. After a new
extraction, press **Reload map** in its inspector.

## Checking what came through

```sh
scripts/inspect_assets.sh
```

On Windows, double-click `scripts/inspect_assets.bat`, which runs the same
thing through Git Bash and waits for a keypress rather than closing.

That prints the file layout and then the import inventory: mesh counts, the
bounding box, where collision came from, the spawn points and every distinct
material name. It is the output to send over when an import is misbehaving.

Three things are put right between extraction and import, by scripts that
the commands above run for you (`reference/asset-pipeline.md` has the
measurements behind each). Source 2 Viewer exports overlays and the kasbah
window insets 15.5 units out along their normals, which leaves signs hanging
off their walls and windows standing proud of their holes;
`scripts/prepare_export.gd` moves them back. The same script keeps the paint
that says where a wall is plaster and where it is brick, which arrives in a
vertex attribute Godot would otherwise drop; with that and the second layers,
`src/map/blend_materials.gd` mixes the two the way the game does. And
extracted textures are imported VRAM-compressed with mipmaps, which Godot
does not do by itself for textures it only ever meets headless:
`scripts/write_import_settings.gd` sets that up before each import. It is the
difference between 1 GB of video memory and 4.
