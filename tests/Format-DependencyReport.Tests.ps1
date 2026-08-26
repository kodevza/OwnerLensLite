BeforeAll {
  . (Join-Path $PSScriptRoot "Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens dependency report formatting" {
  BeforeEach {
    $script:report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId    = "sp-1"
        appId       = "app-1"
        displayName = "App One"
      }
      azure                 = [pscustomobject]@{
        roleAssignments = @()
      }
      ownerCandidates       = @()
    }
    $script:sections = @()

    Mock Write-Host {}
    Mock Write-RichText {}
    Mock Write-RichRule { $script:sections += $Title }
    Mock Write-RichTree {}
    Mock New-OwnerLensAzureRbacTree { "tree" }
    Mock Show-OwnerLensEnterpriseApplicationTable {}
    Mock Show-OwnerLensSummaryTable {}
    Mock Show-OwnerLensAzureActivityEvidenceTable {}
    Mock Show-OwnerLensAzureRbacScopeActivityCallersTable {}
    Mock Show-OwnerLensAzureRbacScopeActivityEvidenceTable {}
    Mock Show-OwnerLensAzureActivityDiagnosticSettingsTable {}
    Mock Show-OwnerLensStorageAccountsWithDataPlaneReadTable {}
    Mock Show-OwnerLensStorageDiagnosticSettingsTable {}
    Mock Show-OwnerLensBlobDataPlaneParticipantsTable {}
    Mock Show-OwnerLensBlobReadsByObjectTable {}
    Mock Show-OwnerLensBlobDataPlaneEvidenceTable {}
    Mock Show-OwnerLensGraphAppRoleAssignmentsTable {}
    Mock Show-OwnerLensGraphDelegatedPermissionGrantsTable {}
    Mock Show-OwnerLensGraphGroupMembershipsTable {}
    Mock Show-OwnerLensGraphUserSignInsTable {}
    Mock Show-OwnerLensGraphUserSignInLocationsTable {}
    Mock Show-OwnerLensOwnerCandidatesTable { $script:sections += "Owner Candidates" }
  }

  It "shows only the Azure RBAC tree and owner candidates by default" {
    Format-DependencyReport -Report $script:report

    Should -Invoke Show-OwnerLensOwnerCandidatesTable -Exactly 1
    Should -Invoke Write-RichRule -Exactly 1 -ParameterFilter { $Title -eq "Azure RBAC Relationship Tree" }
    Should -Invoke Write-RichTree -Exactly 1
    Should -Invoke Show-OwnerLensEnterpriseApplicationTable -Exactly 0
    Should -Invoke Show-OwnerLensSummaryTable -Exactly 0
    Should -Invoke Show-OwnerLensAzureActivityEvidenceTable -Exactly 0
    Should -Invoke Show-OwnerLensGraphAppRoleAssignmentsTable -Exactly 0
    $script:sections | Should -Be @("Azure RBAC Relationship Tree", "Owner Candidates")
  }

  It "shows the full report when requested" {
    Format-DependencyReport -Report $script:report -Full

    Should -Invoke Show-OwnerLensEnterpriseApplicationTable -Exactly 1
    Should -Invoke Show-OwnerLensSummaryTable -Exactly 1
    Should -Invoke Write-RichRule -Exactly 1 -ParameterFilter { $Title -eq "Azure RBAC Relationship Tree" }
    Should -Invoke Write-RichTree -Exactly 1
    Should -Invoke Show-OwnerLensAzureActivityEvidenceTable -Exactly 1
    Should -Invoke Show-OwnerLensGraphAppRoleAssignmentsTable -Exactly 1
    Should -Invoke Show-OwnerLensOwnerCandidatesTable -Exactly 1
  }
}
