$testsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $testsRoot

$localRichModule = Resolve-Path -LiteralPath (Join-Path $repoRoot "../PwshRichLitePwshRichLite/PwshRichLite.psd1") -ErrorAction SilentlyContinue
if ($localRichModule) {
  Import-Module $localRichModule.ProviderPath -Force
}
else {
  Import-Module PwshRichLite -MinimumVersion 0.1.0 -Force -ErrorAction Stop
}

Get-ChildItem -Path (Join-Path $repoRoot "OwnerLensLite/Private") -Filter "*.ps1" -File -Recurse |
  Sort-Object FullName |
  ForEach-Object { . $_.FullName }

. (Join-Path $repoRoot "OwnerLensLite/Public/Invoke-OwnerLensLite.ps1")
