[CmdletBinding()]
param(
    [string]$BlenderPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$packGenerator = Join-Path $PSScriptRoot "create_retro_fantasy_asset_pack.py"
$modelRoot = Join-Path $projectRoot "assets\models"

# Hero first: this also creates assets/models/characters/retro_fantasy_hero.glb.
& (Join-Path $PSScriptRoot "build_hero.ps1") -BlenderPath $BlenderPath

if (-not (Test-Path $packGenerator)) {
    throw "Asset-generatorn saknas: $packGenerator"
}

$candidates = @($BlenderPath, $env:BLENDER_EXE)
$blenderRoot = "C:\Program Files\Blender Foundation"
if (Test-Path $blenderRoot) {
    $candidates += Get-ChildItem -Path $blenderRoot -Filter "blender.exe" -File -Recurse |
        Sort-Object FullName -Descending |
        ForEach-Object { $_.FullName }
}
$blenderExe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $blenderExe) {
    throw "Hittade inte Blender."
}

Write-Host "Skapar miljö, föremål och fiende..."
& $blenderExe --background --python $packGenerator -- $modelRoot
if ($LASTEXITCODE -ne 0) {
    throw "Blender misslyckades när asset-paketet byggdes."
}

$expected = @(
    "characters\retro_fantasy_hero.glb",
    "environment\pine_tree.glb",
    "environment\dead_tree.glb",
    "environment\boulder.glb",
    "environment\ore_node.glb",
    "environment\grass_tuft.glb",
    "environment\mushroom_cluster.glb",
    "props\ancient_chest.glb",
    "props\mana_potion.glb",
    "props\campfire.glb",
    "enemies\moss_goblin.glb"
)
$missing = $expected | Where-Object { -not (Test-Path (Join-Path $modelRoot $_)) }
if ($missing) {
    throw ("Modellbygget blev inte komplett. Saknas: " + ($missing -join ", "))
}

Write-Host ""
Write-Host "KLART: 11 GLB-modeller är exporterade till assets\models." -ForegroundColor Green
Write-Host "Starta Godot; den importerar filerna automatiskt."
