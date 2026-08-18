function Get-OwnerLensEnterpriseApplicationTableRows {
  param([object]$Report)

  $sp = $Report.enterpriseApplication
  @([pscustomobject]@{
      Name = $sp.displayName
      ObjectId = $sp.objectId
      AppId = $sp.appId
      AccountEnabled = $sp.accountEnabled
      CreatedAt = $Report.meta.createdAt
    })
}

function Show-OwnerLensEnterpriseApplicationTable {
  param([object]$Report)

  Write-RichRule "Enterprise Application" -Style "cyan"
  Get-OwnerLensEnterpriseApplicationTableRows -Report $Report |
    Write-RichTable -Property Name, ObjectId, AppId, AccountEnabled, CreatedAt -Box Square
  Write-Host ""
}
