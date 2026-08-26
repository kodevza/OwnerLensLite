#requires -Version 7.0

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$modulePath = Join-Path $repoRoot "OwnerLensLite"
$outputRoot = Join-Path $repoRoot "artifacts"
$outputPath = Join-Path $outputRoot "OwnerLensLite"

Remove-Item -Path $outputPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $outputPath -ItemType Directory -Force | Out-Null

Copy-Item -Path (Join-Path $modulePath "*") -Destination $outputPath -Recurse -Force

Test-ModuleManifest (Join-Path $outputPath "OwnerLensLite.psd1") | Out-Null

Write-Host "Built module at $outputPath"
