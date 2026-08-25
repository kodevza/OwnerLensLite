function Get-OwnerLensEnterpriseApplicationTableRows {
  param([object]$Report)

  $sp = Get-OwnerLensReportValue -Report $Report -Path "enterpriseApplication"
  @([pscustomobject]@{
      Name = $sp.displayName
      ObjectId = $sp.objectId
      AppId = $sp.appId
      AccountEnabled = $sp.accountEnabled
      CreatedAt = Get-OwnerLensReportValue -Report $Report -Path "meta.createdAt"
    })
}

function Show-OwnerLensEnterpriseApplicationTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Enterprise Application" `
    -Rows (Get-OwnerLensEnterpriseApplicationTableRows -Report $Report) `
    -Property Name, ObjectId, AppId, AccountEnabled, CreatedAt `
    -BlankLineAfter
}
