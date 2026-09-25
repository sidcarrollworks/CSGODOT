# Does CS2 read every gun ahead?

Research for the open question in `reference/performance.md` ("Against
CS2"): whether to read every gun's model before play, as CS2 might. Written
2026-09-25 from CS2 1.41.8.4 (build 2000917) as installed on Sid's machine,
from community sources, and from measurements of this build on Sid's
machine (RTX 4070 Ti, Godot 4.7.2).

**How each claim is marked.** *Read* is read from CS2's shipped files:
resources decoded with Source2Viewer-CLI (`-b DATA`, `-b RERL`), or strings
and data tables in its DLLs. *Measured* is something run here. *Community*
comes from players, modders and reverse-engineered SDKs (AlliedModders'
hl2sdk `cs2` branch, CS2Fixes, CounterStrikeSharp). *Inferred* is a reasoned
guess from the above. Nothing here comes from Valve's leaked CS:GO source.
One research agent fetched a copy of it while this was researched; what it
said was dropped, and the copies were deleted.

## The short version

- **CS2 very likely precaches every gun but the Desert Eagle, as the server
  starts or the map changes, not at first pickup.** `server.dll` and
  `client.dll` each carry a table of registrations into a resource manifest
  named `GameSessionManifest` (65 on the server, 73 on the client), each
  `{name, group, 0, source file, line}` (*Read*, checked twice). It covers
  33 of the 34 guns (`weapon_csbasegun.cpp` lines 86 to 120,
  `weapon_csbaseshotgun.cpp`, `weapon_cz75a.cpp`, `weapon_elite.cpp`), the
  knife, the Zeus, the C4, the healthshot, the molotov and incendiary, the
  player, and the grenade projectiles. Each gun's record is paired in its
  static initializer with `weapon_<gun>.ventr`, an entity-class entry the
  engine's resource manifest takes (`CEntityResourceManifest::AddResourceInternal`
  knows `ventr` and `vrgrp`), and the server adds the group as
  `GameSessionManifest.vrgrp` (*Read*). Community plugin frameworks build
  their own precaches in the same step, which their docs say runs "only
  when initial startup / changing map" (*Community*: CounterStrikeSharp's
  `OnServerPrecacheResources`, CS2Fixes). Nobody has watched it happen: the
  Local check below would.
- **Why the Desert Eagle has no record is unknown.** Its class (`CDEagle`) is
  registered as an entity the same way as the CZ75's, which has one
  (*Read*). The HE, flash, smoke and decoy have no weapon record either, but
  a `GameStartup` group hard-codes all six grenade world models (*Read*).
- **The map brings no guns.** dust2's `de_dust2.vmap_c` has 1,463 external
  references and its entity lump none of them a weapon (*Read*).
  `scripts/weapons.vdata_c` names each gun's model, skeleton and tracer only
  as weak references (no reference block), so reading it loads nothing
  (*Read*). pak01 ships only 6 resource manifests, none for weapons: any
  weapon precache is built by code (*Read*).
- **What is not precached can still load.** CS2's resource system has a
  blocking "just in time" load for a resource no loaded manifest holds (a
  hitch: `Resource "%s" was not precached but was loaded by a just in time
  blocking load.`, printed only when the `ResourceSystem { SpewBlockingLoads }`
  key is set in `gameinfo.gi`), and it loads manifests in the background too
  (`CAsyncResourceDataRequest`, `ResourceManifestLoadPriority_t`) (*Read*,
  strings in `resourcesystem.dll` and `engine2.dll`). CS2 sets
  `r_skip_precache_validation_check 1` in `game/csgo/gameinfo.gi`.
- **Every gun's first-person clips come with the player's view-model graph.**
  `animation/graphs/viewmodel/viewmodel.vnmgraph_c` references 65 graphs
  (every gun's variation of `viewmodel_gun`, the grenades, the C4, the
  knives), and each variation references its clips (*Read*); that they
  load together is *Inferred* from how Source 2 resolves references. This
  build reads them ahead the same way (`RigModel.read_ahead`).
- **Textures are streamed, so a precached gun costs little video memory
  until it is drawn.** Every weapon texture is stored mip by mip, each mip
  compressed on its own, with a 1 KB fallback image (*Read*: the `.vtex_c`
  headers). The DX11 and Vulkan render systems carry a streaming pool with a
  memory limit (`CTextureStreamingHelper::RemoveMipLevelsForTextures`,
  "TEXTURESTREAMING: Filled %d fallback textures", "Setting texture pool
  size from available GPU memory"), and `game/csgo_core/gameinfo.gi` sets
  `MinStreamingPoolSizeMB 500` and `AllowPartialMipChainImmediateTexLoads 1`
  (*Read*). Valve's notes mention texture streaming fixes (2023-06-20) and
  Vulkan defragmentation "to help alleviate texture streaming overhead"
  (2025-09-26) (*Read*). The budget and top-mip convars
  (`r_texture_budget_dynamic`, `r_texture_stream_max_resolution`) are
  development-only, so their defaults cannot be read in a release build;
  at Sid's Texture Detail High there may be no cap at all (*Community*,
  *Inferred*).
- **The AK-47's own textures** are four 4096x4096 maps (colour BC7, normal
  BC5, roughness BC5, AO BC4): 74.7 MiB with every mip, 56 of it the top
  mip, 4.7 MiB from mip 2 (1024) down (*Read*). The guns' main textures
  together (251 of them, leaving out skin inputs and sticker masks) are
  2,786 MiB with every mip and 171 MiB from mip 2 down; 33 of them (49 MiB)
  have a single mip and cannot shrink (*Read*, summed).
- **Skins are made on the GPU when needed.** One manifest,
  `compmatcache/composite_inputs.vrman_c`, lists every gun's and knife's
  compositing inputs, and the client prewarms them
  (`CompositeInputsPrewarm`, `custom_weapon_prewarm.vmat`) (*Read*). A short
  freeze the first time a skin or nametag is seen is a long-standing
  complaint (*Community*), and CS:GO's own notes fixed "micro hitches"
  picking up weapons with custom finishes (2014-05-02, *Read*). Nothing
  here draws skins yet.

## Ours, measured

On Sid's machine, 2026-09-25, the 34 gun models the game loads, files in
the disk cache:

- **A gun is 49 MiB of textures and 2.7 MiB of mesh**: 1,665 MiB and 91 MiB
  for all 34 (the renderer's own texture and buffer counters, matching the
  imported `.ctex` sizes to 0.4 MiB). 86% is the 4096 set. Colour and ORM
  import as BC1 (0.5 byte a pixel) and normal maps as BC5 (1 byte a pixel,
  46% of the total), with a third more for mips.
- **The 85 MB a gun (2.9 GB for 34) first written in performance.md was
  wrong.** It was `RENDER_VIDEO_MEM_USED` while all 34 loaded at once on
  worker threads. In Godot 4.7.2 that sums the Vulkan allocator's bytes over
  every heap, system memory included
  (`RenderingDeviceDriverVulkan::get_total_memory_used`), and every first
  upload of a texture or buffer goes through a transfer worker, one per
  upload in flight up to the processor count (16 here), each keeping a
  staging buffer in system memory sized to its largest upload (32 MiB for a
  4096 BC5 map) until the renderer shuts down (`rendering_device.cpp`,
  4.7.2-stable) (*Read*). Measured: 34 at once held 0.7 to 1.0 GiB more
  than `load()` or one at a time (1,882 MiB against 2,554 to 2,778), none
  of it on the card (`nvidia-smi` rose 2.0 GiB either way), and it was
  still held 900 frames later. The 16 x 32 MiB does not account for all of
  it; the rest is unexplained.
- **14% of each gun's textures are for a body never drawn.** Every gun's
  export carries `body_hd` and `body_legacy`; the game hides the second
  (`RigModel.is_spare_body`) but loads its textures: 228.5 MiB for 34. In
  CS2 it is the body for skins marked `"use_legacy_model" "1"` in
  `items_game.txt` (884 paint kits, the old CS:GO finishes such as
  `hy_ddpat`), and the model's default mesh-group mask shows only
  `body_hd` (*Read*). It is not a body for old hardware, as this repo's
  comments said.
- **A model read with `load()` takes 22 to 51 ms** (median 27): 0.95 to
  1.04 s for all 34 on the main thread, 1.23 s one at a time on a worker.
  Nothing was measured with a cold disk cache.
- **What can appear in a competitive match** with the default loadout: the
  21 guns on the two buy menus, the Zeus, the grenades and the C4. When
  this was researched, the game read at match start the models of the 16
  guns a bot may hold (`Competitive._prepare_holding`), and only the clips
  of the rest. Not read then: the Dual Berettas, P250, Tec-9, Five-SeveN
  and Desert Eagle (237 MiB of textures, about 130 ms of `load()`), the Zeus
  (43 MiB) and the grenades' models (about 10.7 MiB each); all are read
  now (below). The other 13 guns (626 MiB) cannot be bought, handed out or
  held by a bot.
- **Godot 4.7 has no texture streaming.** `mipmaps/limit` "is currently not
  implemented", and `process/size_limit` caps a texture once, at import
  (`importing_images.rst`). An imported `.ctex` does hold the 2048 level as
  its mip 1, so a script could build a smaller copy from it (*Inferred*,
  untested).
- The first-person clip scenes hold no images, so reading the 263 of them
  at once uploads no textures.

## What it means for the build here

1. **Read every model that can appear in the match when it loads**, as CS2
   does: both menus, the Zeus and the grenades, on top of the bots' guns.
   About 290 MiB and 150 ms more. Read them with `load()` while the map
   loads or one at a time on a worker, never all at once on workers (the
   staging buffers above). *(Done, perf/read-match-guns-ahead:
   `Competitive._prepare_holding` reads the models of everything on either
   menu, the knife and the bomb with `load()` as the match is set up, 32
   models where it read 18.)*
2. **Leave `body_legacy` out of the gun imports** (the per-node Skip Import
   in the `.import`'s `_subresources`, or a post-import step), keeping it
   where it is a weapon's only body (the default knives). 14% less, nothing
   visible. It touches `assets/`, so it needs a run on Sid's machine.
   *(Done, the same branch: `scripts/weapon_model_import.gd`, a post-import
   step that `write_import_settings.gd` sets on every weapon model, removes
   the body `RigModel.is_spare_body` would hide. Run on Sid's machine.)*
3. **Leave the 13 guns nobody can get** until loadouts can hold them.
4. **Streaming as CS2 does it**, small mips for every gun and the full set
   for the gun in hand (`RenderingServer.texture_replace` swaps a texture's
   data keeping its RID), would take all 34 to about 170 MiB, but it is work
   of its own: only if memory gets tight.
5. A dropped gun whose model was not read is read on a worker as it falls
   (`DroppedItemView`); with (1) that no longer happens in a match.
6. When skins arrive, the legacy-model paint kits need `body_legacy` back
   for the guns they are on.

Measured for (1) and (2) on Sid's machine once dust2's match has started:
the renderer's own counters, and `Competitive._prepare_holding` timed
around its call (a temporary print), drawn, the files in the disk cache;
one run to warm up, then three, whose mean is given (their spread was 70
to 130 ms).

| | Textures | Mesh buffers | Everything | The read at match start |
|---|---|---|---|---|
| Before: the bots' 18 models, the rest's clips | 2,545 MiB | 345 MiB | 3,418 MiB | 1.46 s |
| Every model that can appear (32) | 2,826 MiB | 356 MiB | 3,709 MiB | 1.67 s |
| And no legacy bodies | 2,683 MiB | 330 MiB | 3,541 MiB | 1.63 s |

So every gun, grenade and piece of kit anyone can take in hand is read
before play for 123 MiB more video memory and 0.17 s more at match start.
The legacy bodies were 143 MiB of textures and 25 MiB of mesh across the
32; leaving them out barely shortens the read (0.04 s, within the spread).
One run each first gave 2.06, 2.15 and 1.40 s: run-to-run spread, not the
change.

## What a Local check would settle

In CS2, an offline match on dust2 with bots, before anyone buys:

- `resource_list weapons/models/negev`, then `deagle` and `awp`: is each
  gun's model resident before anyone holds one? (`resource_list` "List
  loaded resources matching a substring"; `cl_precacheinfo` "Show precache
  info (client)". Neither is a cheat in the 2023 command dumps.)
- `mat_print_textures_size_in_memory weapons/models` before and after
  holding a gun: how many mips an unheld gun keeps.
- For the blocking-load message, a copy of `gameinfo.gi` with
  `ResourceSystem { SpewBlockingLoads 1 }` and a Desert Eagle bought: if it
  prints, the Deagle is read at first use.

## Sources

- CS2 1.41.8.4 on Sid's machine: `game/csgo/pak01_dir.vpk`
  (`scripts/weapons.vdata_c`, `animation/graphs/viewmodel/*.vnmgraph_c`,
  `weapons/models/*/materials/*.vtex_c`, `weapons/models/ak47/weapon_rif_ak47.vmdl_c`,
  `compmatcache/composite_inputs.vrman_c`, `scripts/items/items_game.txt`),
  `game/csgo/maps/de_dust2.vpk`, `game/csgo/gameinfo.gi`,
  `game/csgo_core/gameinfo.gi`, and strings and data in
  `game/csgo/bin/win64/server.dll`, `client.dll`, `game/bin/win64/engine2.dll`,
  `resourcesystem.dll`, `rendersystemdx11.dll`, `rendersystemvulkan.dll`.
- Valve's CS2 and CS:GO update notes, Steam news API, app 730: 2014-05-02,
  2023-06-20, 2023-09-29, 2023-10-04, 2025-09-26.
- AlliedModders hl2sdk, `cs2` branch: `game/shared/igamesystem.h`,
  `public/entity2/entitysystem.h` (github.com/alliedmodders/hl2sdk).
- CS2Fixes, `src/gamesystem.cpp` (github.com/Source2ZE/CS2Fixes);
  CounterStrikeSharp, `src/core/game_system.cpp` and the
  `OnServerPrecacheResources` docs (docs.cssharp.dev).
- Convar and command dumps: ghostcap-gaming/Counter-Strike-2-Command-List
  (2023); saul's release cvar list (gist).
- Steam Community threads on skin and nametag hitches (app 730,
  2024-02-04) and on stutter buying or picking up guns (2023-09-29).
- Godot 4.7.2-stable source: `servers/rendering/rendering_device.cpp`,
  `drivers/vulkan/rendering_device_driver_vulkan.cpp`,
  `scene/resources/compressed_texture.cpp`; Godot 4.7 docs,
  `tutorials/assets_pipeline/importing_images.rst`.
- This build, measured in a drawn (not headless) SceneTree script: each
  model in `reference/weapons/models.md` loaded with `load()`, with
  `load_threaded_request` all at once, and one at a time on a worker, reading
  `RenderingServer.get_rendering_device().get_memory_usage()` (textures,
  buffers, total) and `Performance.RENDER_VIDEO_MEM_USED` before and after,
  `nvidia-smi` for the card and the process's working set for system memory;
  and, per gun, the imported `.ctex` sizes of the textures its glTF's
  materials name, split by the mesh (`body_hd`, `body_legacy`) using them.
