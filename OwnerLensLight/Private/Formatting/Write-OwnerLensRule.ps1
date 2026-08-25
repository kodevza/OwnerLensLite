function Write-OwnerLensRule {
  param(
    [Parameter(Position = 0)]
    [string]$Text,

    [string]$Style = "cyan",

    [switch]$SurroundWithBlankRules
  )

  if ($SurroundWithBlankRules) {
    Write-RichRule "" -Style $Style
  }

  Write-RichRule $Text -Style $Style

  if ($SurroundWithBlankRules) {
    Write-RichRule "" -Style $Style
  }
}
