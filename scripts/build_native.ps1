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

# A program run from here is judged by its exit code. What it writes to
# stderr is an error record to Windows PowerShell 5.1 wherever the output is
# redirected, and under 'Stop' git's progress or a compiler's warning would
# end the script: so programs run with errors continuing.
function Invoke-Program {
    param([string]$Program, [string[]]$Arguments, [switch]$Quietly)
    $ErrorActionPreference = 'Continue'
    if ($Quietly) {
        & $Program @Arguments *> $null
    } else {
        & $Program @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
    }
}

function Get-Head {
    param([string]$Checkout)
    $ErrorActionPreference = 'Continue'
    if (-not (Test-Path -LiteralPath (Join-Path $Checkout '.git'))) { return '' }
    $head = (& git -C $Checkout rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { return '' }
    return "$head".Trim()
}

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
if ((Get-Head $godotCpp) -ne $godotCppCommit) {
    Write-Output "Fetching godot-cpp at $godotCppCommit"
    if (Test-Path -LiteralPath $godotCpp) { Remove-Item -LiteralPath $godotCpp -Recurse -Force }
    New-Item -ItemType Directory -Path $godotCpp -Force | Out-Null
    Invoke-Program git @('-C', $godotCpp, 'init', '-q')
    Invoke-Program git @('-C', $godotCpp, 'remote', 'add', 'origin', $godotCppUrl)
    Invoke-Program git @('-C', $godotCpp, 'fetch', '-q', '--depth', '1', 'origin', $godotCppCommit)
    if ($LASTEXITCODE -ne 0) { throw 'godot-cpp could not be fetched.' }
    Invoke-Program git @('-C', $godotCpp, '-c', 'advice.detachedHead=false', 'checkout', '-q', 'FETCH_HEAD')
    if ((Get-Head $godotCpp) -ne $godotCppCommit) { throw 'godot-cpp is not at its pinned commit.' }
}

Invoke-Program $python @('-m', 'SCons', '--version') -Quietly
if ($LASTEXITCODE -ne 0) {
    $venv = Join-Path $buildPath 'venv'
    $venvPython = Join-Path $venv 'Scripts/python.exe'
    $made = Test-Path -LiteralPath $venvPython
    if ($made) {
        Invoke-Program $venvPython @('-m', 'SCons', '--version') -Quietly
        $made = $LASTEXITCODE -eq 0
    }
    if (-not $made) {
        # None, or one that no longer runs SCons (kept from another Python).
        if (Test-Path -LiteralPath $venv) { Remove-Item -LiteralPath $venv -Recurse -Force }
        Invoke-Program $python @('-m', 'venv', $venv)
        if ($LASTEXITCODE -ne 0) { throw 'No virtual environment could be made for SCons.' }
        Invoke-Program $venvPython @('-m', 'pip', 'install', '-q', "scons==$sconsVersion")
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
        Invoke-Program $python @('-m', 'SCons', "godot_cpp=$godotCpp", 'platform=windows', 'arch=x86_64', "target=$target", "-j$jobs")
        if ($LASTEXITCODE -ne 0) { throw "The build of $target failed." }
        $library = Join-Path $projectPath "addons/csgodot_native/bin/libcsgodot_native.windows.$target.x86_64.dll"
        if (-not (Test-Path -LiteralPath $library)) { throw "The build of $target left no library at $library." }
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
    # The import pass lists the extension for the game to load. Godot is
    # waited for (it is no console program, and PowerShell would go on
    # without it), and what it says is kept beside the build.
    $log = Join-Path $buildPath 'import.log'
    $project = '"{0}"' -f $projectPath
    Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', $project, '--import') `
        -Wait -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    # Built is not loaded: Godot is asked.
    $asked = Join-Path $buildPath 'loaded.log'
    $loaded = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', $project, '--script', 'scripts/native_loaded.gd') `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $asked -RedirectStandardError "$asked.err"
    Get-Content -LiteralPath $asked, "$asked.err" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'NATIVE|ERROR' } | Out-Host
    if ($loaded.ExitCode -ne 0) {
        throw "Built, but Godot does not load it: see $asked.err and $log.err."
    }
    Write-Output 'Built, and Godot loads it. Restart Godot if this project is open.'
} else {
    Write-Output 'Built. No Godot binary was found to list it with: open the project in the editor once.'
}
