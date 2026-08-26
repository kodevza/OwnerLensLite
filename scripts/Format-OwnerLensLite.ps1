[CmdletBinding()]
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Path,
  [switch]$Check
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'
$settings = Import-PowerShellDataFile -Path $settingsPath
$maximumLineLength = [int]$settings.Rules.PSAvoidLongLines.MaximumLineLength

Import-Module PSScriptAnalyzer -MinimumVersion 1.20.0 -ErrorAction Stop

if (-not $Path -or $Path.Count -eq 0) {
  $Path = Get-ChildItem -Path $repositoryRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' |
    Where-Object { $_.FullName -notmatch '[/\\](artifacts|foundry-agents[/\\].venv-foundry-agent)[/\\]' } |
    ForEach-Object FullName
}

$files = @(
  $Path |
    ForEach-Object {
      if ([System.IO.Path]::IsPathRooted($_)) {
        $_
      }
      else {
        Join-Path $repositoryRoot $_
      }
    } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    ForEach-Object { Get-Item -LiteralPath $_ }
)

$unformattedFiles = [System.Collections.Generic.List[string]]::new()
$longLines = [System.Collections.Generic.List[string]]::new()
foreach ($file in $files) {
  $original = [System.IO.File]::ReadAllText($file.FullName)
  $relativePath = [System.IO.Path]::GetRelativePath($repositoryRoot, $file.FullName)

  $lineNumber = 0
  $hasLongLine = $false
  foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
    $lineNumber++
    if ($line.Length -gt $maximumLineLength) {
      $longLines.Add("${relativePath}:$lineNumber ($($line.Length) characters)")
      $hasLongLine = $true
    }
  }

  if ($Check -and $hasLongLine) {
    continue
  }

  $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath

  if ($original -eq $formatted) {
    continue
  }

  if ($Check) {
    $unformattedFiles.Add($relativePath)
    continue
  }

  [System.IO.File]::WriteAllText($file.FullName, $formatted, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Formatted $relativePath"
}

if ($unformattedFiles.Count -gt 0) {
  $formattedFileList = $unformattedFiles -join ', '
  $formattingMessage = "PowerShell formatting is required for: $formattedFileList."
  $formattingMessage += ' Run ./scripts/Format-OwnerLensLite.ps1, then stage the updated files.'
  Write-Error $formattingMessage
}

if ($longLines.Count -gt 0) {
  $longLineDetails = $longLines -join [Environment]::NewLine
  Write-Error "Lines must not exceed $maximumLineLength characters:`n$longLineDetails"
}
