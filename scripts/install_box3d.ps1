# Builds debug/release from pinned sources plus the opt-in projectile trace.
# Requires Git, Python 3 and Visual Studio C++ Build Tools. Cached after first run.
param([string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot), [string]$BuildDirectory = '')
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectDirectory).Path
$python = Get-Command python -ErrorAction Stop
$buildArgs = @((Join-Path $projectPath 'scripts/build_box3d_projectiles.py'), '--project', $projectPath)
if ($BuildDirectory) { $buildArgs += @('--build-directory', $BuildDirectory) }
& $python.Source @buildArgs
if ($LASTEXITCODE -ne 0) { throw "Box3D build failed ($LASTEXITCODE)." }
