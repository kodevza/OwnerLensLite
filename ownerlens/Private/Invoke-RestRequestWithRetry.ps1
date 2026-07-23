function Invoke-RestRequestWithRetry {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$OperationName,

    [Parameter(Mandatory = $true)]
    [scriptblock]$Request,

    [ValidateRange(1, 10)]
    [int]$MaxRetryCount = 3,

    [ValidateRange(0, 300)]
    [int]$RetryDelaySeconds = 5
  )

  $attempt = 0
  while ($true) {
    try {
      return & $Request
    } catch {
      $attempt += 1
      if ($attempt -ge $MaxRetryCount) {
        throw
      }

      $delay = $RetryDelaySeconds * [math]::Pow(2, $attempt - 1)
      Write-Warning "$OperationName failed ($attempt/$MaxRetryCount): $($_.Exception.Message). Retrying in $delay seconds."
      Start-Sleep -Seconds $delay
    }
  }
}
