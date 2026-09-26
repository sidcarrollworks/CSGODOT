# Install the pinned upstream addon for the dropped-gun experiment.
# PowerShell 7 (Windows/Linux/macOS) or Windows PowerShell 5.1:
#   powershell -ExecutionPolicy Bypass -File scripts/install_box3d.ps1
param([string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$version = 'v0.4.3'
$expectedHash = 'AA5880B6DD57AAE89699B16728D379B521B5332BBF84DFC74DBFF912A612DDD3'
$projectPath = (Resolve-Path -LiteralPath $ProjectDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'project.godot'))) {
    throw 'ProjectDirectory must contain project.godot.'
}
$downloadDirectory = Join-Path $projectPath '.godot/box3d-download'
New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
$archivePath = Join-Path $downloadDirectory 'addon.zip'
if (-not (Test-Path -LiteralPath $archivePath) -or
    (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $expectedHash) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/Stink-O/box3d-godot/releases/download/$version/box3d-addon-$version.zip" -OutFile $archivePath
}
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Box3D archive checksum differs from the pinned release. Nothing was installed.'
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $projectPath -Force
Write-Output "Installed Box3D $version in $projectPath/addons/box3d. Restart Godot if this project is open."
