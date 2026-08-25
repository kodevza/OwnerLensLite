function Format-DependencyReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report,

    [switch]$Full
  )

  if (-not $Full) {
    Write-OwnerLensRule -Text "Azure RBAC Relationship Tree" -Style "dim"
    Write-RichTree (New-OwnerLensAzureRbacTree -Report $Report)
    Show-OwnerLensOwnerCandidatesTable -Report $Report
    return
  }

  Write-Host ""
  Write-RichText "[bold cyan]OwnerLens Light[/] [dim]Enterprise Application dependency report[/]"

  Show-OwnerLensEnterpriseApplicationTable -Report $Report
  Show-OwnerLensSummaryTable -Report $Report

  Write-OwnerLensRule -Text "Azure RBAC Relationship Tree" -Style "cyan"
  Write-RichTree (New-OwnerLensAzureRbacTree -Report $Report)

  Show-OwnerLensAzureActivityEvidenceTable -Report $Report
  Show-OwnerLensAzureRbacScopeActivityCallersTable -Report $Report
  Show-OwnerLensAzureRbacScopeActivityEvidenceTable -Report $Report
  Show-OwnerLensAzureActivityDiagnosticSettingsTable -Report $Report
  Show-OwnerLensStorageAccountsWithDataPlaneReadTable -Report $Report
  Show-OwnerLensStorageDiagnosticSettingsTable -Report $Report
  Show-OwnerLensBlobDataPlaneParticipantsTable -Report $Report
  Show-OwnerLensBlobReadsByObjectTable -Report $Report
  Show-OwnerLensBlobDataPlaneEvidenceTable -Report $Report
  Show-OwnerLensGraphAppRoleAssignmentsTable -Report $Report
  Show-OwnerLensGraphDelegatedPermissionGrantsTable -Report $Report
  Show-OwnerLensGraphGroupMembershipsTable -Report $Report
  Show-OwnerLensGraphUserSignInsTable -Report $Report
  Show-OwnerLensGraphUserSignInLocationsTable -Report $Report
  Show-OwnerLensOwnerCandidatesTable -Report $Report
}
