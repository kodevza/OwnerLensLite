function Write-OwnerLensReportTable {
  param(
    [object[]]$Rows,
    [string]$Title,
    [string]$Style = "cyan",
    [string[]]$Property,
    [switch]$SurroundWithBlankRules,
    [switch]$BlankLineAfter
  )

  $tableRows = @($Rows)
  if ($tableRows.Count -eq 0) {
    return
  }

  Write-OwnerLensRule -Text $Title -Style $Style -SurroundWithBlankRules:$SurroundWithBlankRules
  $tableRows | Write-RichTable -Property $Property -Box Square

  if ($BlankLineAfter) {
    Write-Host ""
  }
}
