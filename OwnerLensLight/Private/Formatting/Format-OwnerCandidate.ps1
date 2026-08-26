function Format-OwnerTagCandidateValue {
  param(
    [string]$TagName,
    [string]$TagValue,
    [string]$CandidateType
  )

  if ($CandidateType -eq "User" -or $CandidateType -eq "Group") {
    return $TagValue
  }

  return ("{0}={1}" -f $TagName, $TagValue)
}

function ConvertTo-OwnerCandidateTsvField {
  param([object]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return ([string]$Value) -replace "[`t`r`n]+", " "
}

function Format-OwnerCandidateTable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Candidates
  )

  $rows = @($Candidates |
    Group-Object candidate, candidateType |
    ForEach-Object {
      $groupRows = @($_.Group | Sort-Object @{ Expression = { Get-OwnerConfidenceRank -Confidence ([string]$_.confidence) }; Descending = $true }, evidenceId)
      $bestConfidence = [string]$groupRows[0].confidence
      [pscustomobject]@{
        candidate = [string]$groupRows[0].candidate
        type = [string]$groupRows[0].candidateType
        confidence = $bestConfidence
        relationship = [string](($groupRows | Select-Object -ExpandProperty relationship -Unique) -join ",")
        signal = [string](($groupRows | Select-Object -ExpandProperty signal -Unique) -join ",")
        evidenceId = [string](($groupRows | Select-Object -ExpandProperty evidenceId -First 4) -join ",")
      }
    } |
    Sort-Object @{ Expression = { Get-OwnerConfidenceRank -Confidence ([string]$_.confidence) }; Descending = $true }, candidate)

  $columns = @("candidate", "type", "confidence", "relationship", "signal", "evidenceId")
  $lines = @(
    ($columns -join "`t")
    $rows | ForEach-Object {
      $row = $_
      (($columns | ForEach-Object { ConvertTo-OwnerCandidateTsvField -Value $row.$_ }) -join "`t")
    }
  )

  return ($lines -join [Environment]::NewLine)
}
