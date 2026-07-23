function Invoke-GraphPagedRequest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [Parameter(Mandatory = $true)]
    [string]$OperationName
  )

  $items = @()
  $nextUri = $Uri

  while ($nextUri) {
    $currentUri = $nextUri
    $response = Invoke-RestRequestWithRetry `
      -OperationName $OperationName `
      -Request {
        return Invoke-MgGraphRequest -Method GET -Uri $currentUri -OutputType PSObject -ErrorAction Stop
      }

    $items += @($response.value)

    $nextLinkProperty = $response.PSObject.Properties["@odata.nextLink"]
    $nextUri = if ($nextLinkProperty) { $nextLinkProperty.Value } else { $null }
  }

  return $items
}
