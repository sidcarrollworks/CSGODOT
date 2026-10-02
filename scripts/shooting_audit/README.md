# Local shooting audit tools

Read-only helpers for the [October 2 shooting audit](../../reference/research/shooting-audit-2026-10-02.md).
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

The PE helper exports metadata/SHA-256, ASCII shooting strings with RVA/VA,
and `*-targets.tsv` for `AuditIndex.java`. It handles PE32+ binaries, not
arbitrary executable formats.

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

## Validation

```powershell
python -m unittest discover -s scripts/shooting_audit -p 'test_*.py'
```

Fixtures cover inheritance, nested-field exclusion, cycles, array/enum
normalization and the changed/new/missing distinction. The October 2 pass
also ran the helpers against all three installed binaries and fresh vdata,
and compiled/executed both Java scripts in Ghidra.
