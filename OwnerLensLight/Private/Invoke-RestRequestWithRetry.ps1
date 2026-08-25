function Get-RestRetryStatusCode {
  param([object]$ErrorRecord)

  $exception = $ErrorRecord.Exception
  if ($exception -and $exception.Response -and $null -ne $exception.Response.StatusCode) {
    return [int]$exception.Response.StatusCode
  }

  if ($exception -and $exception.Message -match "(?<!\d)(4\d\d|5\d\d)(?!\d)") {
    return [int]$Matches[1]
  }

  return $null
}

function Test-RestRequestShouldRetry {
  param([object]$ErrorRecord)

  $statusCode = Get-RestRetryStatusCode -ErrorRecord $ErrorRecord
  if ($null -eq $statusCode) {
    return $true
  }

  if ($statusCode -in @(400, 401, 403, 404)) {
    return $false
  }

  return ($statusCode -eq 408 -or $statusCode -eq 409 -or $statusCode -eq 429 -or $statusCode -ge 500)
}

function Get-RestRetryAfterSeconds {
  param([object]$ErrorRecord)

  $response = $ErrorRecord.Exception.Response
  if (-not $response -or -not $response.Headers) {
    return $null
  }

  $retryAfter = $null
  try {
    $retryAfter = $response.Headers["Retry-After"]
  } catch {
    $retryAfter = $null
  }

  if ([string]::IsNullOrWhiteSpace([string]$retryAfter)) {
    return $null
  }

  $seconds = 0
  if ([int]::TryParse([string]$retryAfter, [ref]$seconds) -and $seconds -ge 0) {
    return $seconds
  }

  $retryAfterDate = [datetime]::MinValue
  if ([datetime]::TryParse([string]$retryAfter, [ref]$retryAfterDate)) {
    $delay = [math]::Ceiling(($retryAfterDate.ToUniversalTime() - (Get-Date).ToUniversalTime()).TotalSeconds)
    if ($delay -gt 0) {
      return [int]$delay
    }
  }

  return $null
}

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
      if (-not (Test-RestRequestShouldRetry -ErrorRecord $_) -or $attempt -ge $MaxRetryCount) {
        throw
      }

      $retryAfterSeconds = Get-RestRetryAfterSeconds -ErrorRecord $_
      $delaySeconds = if ($null -ne $retryAfterSeconds) {
        [int]$retryAfterSeconds
      } else {
        [int]($RetryDelaySeconds * [math]::Pow(2, $attempt - 1))
      }
      $jitterMilliseconds = if ($delaySeconds -gt 0) { Get-Random -Minimum 0 -Maximum 1000 } else { 0 }
      $statusCode = Get-RestRetryStatusCode -ErrorRecord $_
      $statusText = if ($null -ne $statusCode) { " HTTP $statusCode" } else { "" }

      Write-Warning "$OperationName failed$($statusText) ($attempt/$MaxRetryCount). Retrying in $delaySeconds seconds."
      if ($delaySeconds -gt 0) {
        Start-Sleep -Seconds $delaySeconds
      }
      if ($jitterMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $jitterMilliseconds
      }
    }
  }
}
