[CmdletBinding()]
param(
    # Optional: only needed if Blender is installed outside the normal location.
    [string]$BlenderPath = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$generator = Join-Path $PSScriptRoot "create_retro_fantasy_hero.py"
$outputDirectory = Join-Path $projectRoot "assets\models\characters"
$outputFile = Join-Path $outputDirectory "retro_fantasy_hero.glb"

if (-not (Test-Path $generator)) {
    throw "Blender-generatorn saknas: $generator"
}

$candidates = @()
if ($BlenderPath) {
    $candidates += $BlenderPath
}
if ($env:BLENDER_EXE) {
    $candidates += $env:BLENDER_EXE
}
$blenderRoot = "C:\Program Files\Blender Foundation"
if (Test-Path $blenderRoot) {
    $candidates += Get-ChildItem -Path $blenderRoot -Filter "blender.exe" -File -Recurse |
        Sort-Object FullName -Descending |
        ForEach-Object { $_.FullName }
}

$blenderExe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $blenderExe) {
    throw "Hittade inte Blender. Kör igen med: .\tools\blender\build_hero.ps1 -BlenderPath 'C:\sökväg\blender.exe'"
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Write-Host "Skapar retro-fantasy-hjälten med Blender..."
& $blenderExe --background --python $generator -- $outputFile
if ($LASTEXITCODE -ne 0) {
    throw "Blender misslyckades med felkod $LASTEXITCODE."
}
if (-not (Test-Path $outputFile)) {
    throw "Blender avslutades men skapade ingen GLB-fil."
}

Write-Host ""
Write-Host "KLART: $outputFile" -ForegroundColor Green
Write-Host "Öppna Godot igen så importeras modellen automatiskt."
