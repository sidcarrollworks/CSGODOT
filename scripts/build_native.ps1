# Builds the game's native code (native/src: the movement's step) on Windows.
# PowerShell 7 or Windows PowerShell 5.1:
#   powershell -ExecutionPolicy Bypass -File scripts/build_native.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/build_native.ps1 -Release
#
# Without the library the game runs as it always did: the script runs the
# movement's step (PlayerBody). With it the native code runs the step, and
# every check file holds it to the script's result, bit for bit.
#
# It needs git, Python 3 and Visual Studio's C++ tools (SCons finds them).
# godot-cpp is fetched at a pinned commit into the build directory
# (.godot/native-build, or -BuildDirectory, or CSGODOT_NATIVE_BUILD), and
# SCons goes into a virtual environment there when Python has none. The
# first build compiles godot-cpp, a few minutes; later ones only what
# changed. Safe to run again.
param(
    [string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$BuildDirectory = $env:CSGODOT_NATIVE_BUILD,
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
# godot-cpp 10.0.0-stable: a tag can be moved, a commit cannot.
$godotCppCommit = '507ed9d840c01a3c5b2a39af8bb4000bfac30bf5'
$godotCppUrl = 'https://github.com/godotengine/godot-cpp.git'
$sconsVersion = '4.8.1'

$projectPath = (Resolve-Path -LiteralPath $ProjectDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'project.godot'))) {
    throw 'ProjectDirectory must contain project.godot.'
}
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $projectPath '.godot/native-build'
}
New-Item -ItemType Directory -Path $BuildDirectory -Force | Out-Null
$buildPath = (Resolve-Path -LiteralPath $BuildDirectory).Path

$python = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $python) { $python = (Get-Command python3 -ErrorAction SilentlyContinue) }
if (-not $python) { throw 'Python 3 is needed to build (SCons runs on it).' }
$python = $python.Source

$godotCpp = Join-Path $buildPath 'godot-cpp'
$at = ''
if (Test-Path -LiteralPath (Join-Path $godotCpp '.git')) {
    $at = (& git -C $godotCpp rev-parse HEAD 2>$null)
}
if ($at -ne $godotCppCommit) {
    Write-Output "Fetching godot-cpp at $godotCppCommit"
    if (Test-Path -LiteralPath $godotCpp) { Remove-Item -LiteralPath $godotCpp -Recurse -Force }
    New-Item -ItemType Directory -Path $godotCpp -Force | Out-Null
    & git -C $godotCpp init -q
    & git -C $godotCpp remote add origin $godotCppUrl
    & git -C $godotCpp fetch -q --depth 1 origin $godotCppCommit
    if ($LASTEXITCODE -ne 0) { throw 'godot-cpp could not be fetched.' }
    & git -C $godotCpp -c advice.detachedHead=false checkout -q FETCH_HEAD
}

& $python -m SCons --version *> $null
if ($LASTEXITCODE -ne 0) {
    $venv = Join-Path $buildPath 'venv'
    $venvPython = Join-Path $venv 'Scripts/python.exe'
    if (-not (Test-Path -LiteralPath $venvPython)) {
        & $python -m venv $venv
        & $venvPython -m pip install -q "scons==$sconsVersion"
        if ($LASTEXITCODE -ne 0) { throw 'SCons could not be installed.' }
    }
    $python = $venvPython
}

$targets = @('template_debug')
if ($Release) { $targets += 'template_release' }
$jobs = [Math]::Max(2, [Environment]::ProcessorCount - 2)
Push-Location (Join-Path $projectPath 'native')
try {
    foreach ($target in $targets) {
        Write-Output "Building the native code for windows x86_64, $target"
        & $python -m SCons "godot_cpp=$godotCpp" platform=windows arch=x86_64 "target=$target" "-j$jobs"
        if ($LASTEXITCODE -ne 0) { throw "The build of $target failed." }
    }
} finally {
    Pop-Location
}

# Godot finds the library by this file, which is put beside it only once
# there is a library: a listed extension with none is three errors at every
# start.
$addon = Join-Path $projectPath 'addons/csgodot_native'
New-Item -ItemType Directory -Path $addon -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectPath 'native/csgodot_native.gdextension') -Destination (Join-Path $addon 'csgodot_native.gdextension') -Force

$godot = $env:GODOT
if (-not $godot) {
    $found = Get-ChildItem -Path (Join-Path $HOME 'Desktop'), (Join-Path $HOME 'Downloads') -Filter 'Godot_v4*win64.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'console' } | Sort-Object Name | Select-Object -Last 1
    if ($found) { $godot = $found.FullName }
}
if ($godot) {
    # The import pass lists the extension for the game to load.
    & $godot --headless --path $projectPath --import *> (Join-Path $buildPath 'import.log')
    Write-Output 'Built, and listed for Godot to load. Restart Godot if this project is open.'
} else {
    Write-Output 'Built. No Godot binary was found to list it with: open the project in the editor once.'
}
