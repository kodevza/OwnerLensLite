function Get-ObjectProperty {
  param(
    [object]$Object,
    [string]$PropertyName
  )

  if (-not $Object) {
    return $null
  }

  $property = $Object.PSObject.Properties[$PropertyName]
  if (-not $property) {
    return $null
  }

  return $property.Value
}
