# Local weapon and grenade audit tools

Read-only helpers for the [October 2 shooting audit](../../reference/research/shooting-audit-2026-10-02.md)
and [grenade audit](../../reference/research/grenade-audit-2026-10-02.md).
They fingerprint binaries, compare fresh weapon data, and export selected
Ghidra references/functions. They do not load/execute Valve DLLs, attach to
CS2, or modify game files. These are research tools, not runtime dependencies.

Requires Python 3.9+ (standard library only), Source2Viewer CLI, Ghidra and
its supported JDK. This pass used Python 3.13, Source2Viewer 20.0, Ghidra
12.1.4 and JDK 25. Use native Windows paths for Java configuration; Ghidra's
launcher can select its saved JDK without a JAVA_HOME override. Download
Ghidra from its official release and verify the archive digest.

Run from the repository root. Example PowerShell setup; change the install
and tool paths for the machine:

```powershell
$cs2Game = 'D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\game'
$source2Cli = 'C:\Users\squid\Downloads\cli-windows-x64\Source2Viewer-CLI.exe'
$ghidraHeadless = 'C:\Users\squid\.codex\tools\ghidra\ghidra_12.1.4_PUBLIC\support\analyzeHeadless.bat'
$auditOut = '.godot\shooting-audit'
$auditProjects = Join-Path $env:USERPROFILE 'Documents\CS2ShootingAudit\projects'
New-Item -ItemType Directory -Force "$auditOut\raw", $auditProjects | Out-Null
```

Ghidra project paths must have no component beginning with a dot. Its project
folder is therefore outside `.godot`; exported results can go inside it.
Keep DLLs, decoded assets, logs, databases and decompiler output uncommitted.

## Fresh data and binary identity

```powershell
Get-Content "$cs2Game\csgo\steam.inf"
python scripts/shooting_audit/pe_strings.py --out "$auditOut\raw" `
  "$cs2Game\csgo\bin\win64\server.dll" `
  "$cs2Game\csgo\bin\win64\client.dll" `
  "$cs2Game\bin\win64\tier0.dll"
& $source2Cli -i "$cs2Game\csgo\pak01_dir.vpk" -f 'scripts/weapons.vdata_c' -b DATA `
  > "$auditOut\raw\weapons.vdata.txt"
python scripts/shooting_audit/compare_vdata.py "$auditOut\raw\weapons.vdata.txt" `
  --out "$auditOut\raw"
```

The PE helper exports metadata/SHA-256, selected ASCII strings with RVA/VA,
and `*-targets.tsv` for `AuditIndex.java`. It handles PE32+ binaries, not
arbitrary executable formats.
Use `--pattern` to select another case-insensitive regex; omitting it keeps
the original shooting anchors.

The data helper resolves `_base` inheritance and reads scalar/one-line-array
fields in the CLI's text format, like `scripts/weapon_tables.gd`. Its report
distinguishes changes, newly present fields, fields absent from that decode,
and missing weapons. It does not compare arbitrary nested resources,
regenerate the CSV, or fail merely because a data value changed. Override
`--table` to compare another CSV. Text hashes depend on CLI formatting,
encoding and line endings; DLL hashes are the binary anchors.

## Ghidra analysis

Import modules into separate projects; never process the same project from
two headless instances at once. Initial analysis can take several minutes.
Check completion, timeouts and warnings before trusting a function.

```powershell
& $ghidraHeadless $auditProjects CS2_Shooting_Server `
  -import "$cs2Game\csgo\bin\win64\server.dll" -max-cpu 2 `
  -scriptPath scripts/shooting_audit `
  -postScript AuditIndex.java "$auditOut\raw\server-targets.tsv" "$auditOut\server" `
  -log "$auditOut\server-analysis.log"
& $ghidraHeadless $auditProjects CS2_Shooting_Client `
  -import "$cs2Game\csgo\bin\win64\client.dll" -max-cpu 2 `
  -scriptPath scripts/shooting_audit `
  -postScript AuditIndex.java "$auditOut\raw\client-targets.tsv" "$auditOut\client" `
  -log "$auditOut\client-analysis.log"
& $ghidraHeadless $auditProjects CS2_Shooting_Tier0 `
  -import "$cs2Game\bin\win64\tier0.dll" -max-cpu 2 `
  -log "$auditOut\tier0-analysis.log"
```

After analysis, export selected functions from the ledger. These addresses
are **only for the DLL hashes recorded in the audit**:

```powershell
& $ghidraHeadless $auditProjects CS2_Shooting_Server -process server.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditDecompile.java "$auditOut\server\decompiled" `
    1809fb9d0 180a1fdd0 1809b7340 1809b7640 180298e90 180a09130
& $ghidraHeadless $auditProjects CS2_Shooting_Tier0 -process tier0.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditDecompile.java "$auditOut\tier0\decompiled" `
    18015e640 18015e070 18015e740
```

The decompiler helper exports callers/callees and pseudocode for an existing
function at/containing each VA. `NO FUNCTION` means unresolved, not absent
behavior. The index helper exports string xrefs, functions and relevant
symbols. RTTI class labels, serialized field names and tier0 exports are
starting points when addresses change.

Pseudocode is an aid to reading instructions. Wrong float return types,
missing register arguments and function-boundary errors occur. Check XMM
instructions, constants, unwind ranges, call sites and field serialization
before recording a formula. Preserve operation order/float32 rounding in a port.

## Actions, zoom, landing and camera follow-up

The [follow-up ledger](../../reference/research/shooting-followup-2026-10-02.md)
uses the same DLL hashes. Export its central paths from the analyzed
projects (additional supporting methods are listed in that ledger):

```powershell
& $ghidraHeadless $auditProjects CS2_Shooting_Server -process server.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditDecompile.java "$auditOut\server\decompiled" `
    180b15ec0 180a179c0 180a15ac0 1809f0d90 1809fd6c0 1809fd5d0 `
    180a20b40 180a1fdd0 180abdf20 180ab4c40 180ad3cb0 180a16a90 `
    180a37f20 180a45890 180c776b0 180a982f0 1800da670 1800cb240
& $ghidraHeadless $auditProjects CS2_Shooting_Client -process client.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditDecompile.java "$auditOut\client\decompiled" `
    180829980 1808283f0 180820480 18085dd90 180a74440 18088b760 `
    180882790 1808533c0 18084e0c0 18082ce60 1808a6420

$silencerGraphs = 'animation/graphs/viewmodel/viewmodel_gun.vnmgraph+m4a1s.vnmgraph_c,' +
  'animation/graphs/viewmodel/viewmodel_gun.vnmgraph+usp.vnmgraph_c'
& $source2Cli -i "$cs2Game\csgo\pak01_dir.vpk" -f $silencerGraphs -b DATA `
  > "$auditOut\raw\silencer-graphs.txt"
$silencerClips = 'animation/anims/viewmodel/rifle/_default_rifle/silencer_attach_rifle.vnmclip_c,' +
  'animation/anims/viewmodel/rifle/_default_rifle/silencer_detach_rifle.vnmclip_c,' +
  'animation/anims/viewmodel/pistol/_default_pistol/silencer_attach_pistol.vnmclip_c,' +
  'animation/anims/viewmodel/pistol/_default_pistol/silencer_detach_pistol.vnmclip_c'
& $source2Cli -i "$cs2Game\csgo\pak01_dir.vpk" -f $silencerClips -b DATA `
  > "$auditOut\raw\silencer-clips.txt"
```

Use `m_nodePaths` to associate graph node indices with states. Inspect each
state's `m_timedRemainingEvents` and child clip's data-slot/resource mapping;
completion need not appear in the clip's ID-event list. Confirm mode-array
getters in disassembly and resolve each module's vtable independently.
Keep local captures separate from static findings: these commands do not
measure wall-clock lockouts or visible recoil interpolation.

## Validation

```powershell
python -m unittest discover -s scripts/shooting_audit -p 'test_*.py'
```

Seven fixtures cover inheritance, nested-field exclusion, cycles, array/enum
normalization, the changed/new/missing distinction, PE identity/address mapping,
custom string filtering and non-PE rejection. The October 2 pass
also ran the helpers against all three installed binaries and fresh vdata,
and compiled/executed both Java scripts in Ghidra.

## Grenades and throws

Use the same hash-matched server/client projects; the directory name
`shooting_audit` is historical. The grenade pass adds custom string selection
without changing the default shooting scan:

```powershell
$auditOut = '.godot\grenade-audit'
New-Item -ItemType Directory -Force "$auditOut\raw" | Out-Null
python scripts/shooting_audit/pe_strings.py --out "$auditOut\raw" `
  --pattern 'grenade|throwstrength|throwtime|pinpull|nextHold|stash|flash|molotov|decoy|smoke' `
  "$cs2Game\csgo\bin\win64\server.dll" "$cs2Game\csgo\bin\win64\client.dll"
& $ghidraHeadless $auditProjects CS2_Shooting_Server -process server.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditIndex.java "$auditOut\raw\server-targets.tsv" "$auditOut\server"
& $ghidraHeadless $auditProjects CS2_Shooting_Client -process client.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditIndex.java "$auditOut\raw\client-targets.tsv" "$auditOut\client"

& $ghidraHeadless $auditProjects CS2_Shooting_Server -process server.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditDecompile.java "$auditOut\server\decompiled" `
    1809acd00 1809c1d20 1809cd2f0 1809c1930 1809ce100 1809adab0 1809adc00 `
    180ab57f0 180adf830 180abe000 180add6f0 180abf740 180acb810 `
    1809cc3a0 1809c5670 180e87c80 180e89790 1809c7ad0 180e88270 `
    1809ae940 1809af090 18039dc30 18039cd80 1803a1380 18039ced0 `
    1809c9ca0 1809b0f50 1809b0b70 1809cdd00 1809cde80 1809ad2c0 `
    1809afd80 1809cda40 1809b9d00 1809b02a0 1809ad010 1809b0fe0 1809cf4b0 `
    18039e840 180de95d0 18094ebf0 18091fe90 `
    18039dea0 1803a0830 1803a02c0 18039d870 1801c08f0 18021ab10 `
    1800b4920 1800b49d0 1800b3490 1800b51d0
& $ghidraHeadless $auditProjects CS2_Shooting_Client -process client.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditDecompile.java "$auditOut\client\decompiled" `
    1807c6b30 1807d70b0 1807d6de0

$grenadeGraphs = 'decoy','flash','he','incendiary','molotov','smoke' |
  ForEach-Object { "animation/graphs/viewmodel/viewmodel_grenade.vnmgraph+$_.vnmgraph_c" }
& $source2Cli -i "$cs2Game\csgo\pak01_dir.vpk" -f ($grenadeGraphs -join ',') -b DATA `
  > "$auditOut\raw\grenade-graphs.txt"
& $source2Cli -i "$cs2Game\csgo\pak01_dir.vpk" `
  -f 'animation/anims/viewmodel/grenade/' -e vnmclip_c -b DATA `
  > "$auditOut\raw\grenade-clips.txt"
```

Never use an empty VPK filter to dump the whole installation. The nonempty
clip prefix includes draw/idle/charge clips; associate each graph's underhand/
overhand data slot with its specific resource rather than assuming one folder.
Compare fresh weapon vdata as above as well.

Start from `CBaseCSGrenade`, `CBaseCSGrenadeProjectile`, each concrete grenade,
`CCSPlayerPawn` and `CCSGameRules` RTTI/vtables. Follow virtual call slots and
writers/readers of throw, stash, detonation and flash fields; indirect callers
need not appear in a direct-call export. Verify short thunks/leaf helpers in
the Listing and follow their jumps even when the exporter says `NO FUNCTION`.
In this build `CCSGameRules +0x1f8` points at `18094fbb0`, which jumps to
`18094ebf0`. Do not copy offsets, vtable entries or addresses onto an updated
binary without rediscovering them. The grenade report records the equations,
constants and unresolved paths; local lineup/flash/smoke captures remain separate.

## Collision callers before the grenade port

The [collision foundation audit](../../reference/research/collision-foundation-2026-10-02.md)
follows the entity push, collision dispatch, trace filtering and result
conversion in the same hash-matched server project. Additional exports:

```powershell
$collisionAuditOut = '.godot\collision-audit'
& $ghidraHeadless $auditProjects CS2_Shooting_Server -process server.dll -noanalysis `
  -scriptPath scripts/shooting_audit `
  -postScript AuditDecompile.java "$collisionAuditOut\server" `
    180e88aa0 180e86890 180e8c720 180e87e10 180c27940 180c28520 `
    180be76a0 180e887a0 180bd6d50 1814a0920 1814a0b90
```

The gameplay trace's end and fraction are copied from one engine result;
solid-state flags and a missing normal are separate concepts. Inspect the
imported collision-interface calls as well as the server wrappers before
claiming the engine's inner sweep tolerances. This audit's addon comparison
uses the pinned v0.4.3 source and local box/triangle fixtures, not an inferred
match between Box3D and CS2's engine solver.
