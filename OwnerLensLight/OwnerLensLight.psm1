$privateFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot "Private") -Filter "*.ps1" -File
foreach ($functionFile in $privateFunctions) {
  . $functionFile.FullName
}

$publicFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot "Public") -Filter "*.ps1" -File
foreach ($functionFile in $publicFunctions) {
  . $functionFile.FullName
}

Export-ModuleMember -Function @(
  "Invoke-OwnerLensLight"
)
