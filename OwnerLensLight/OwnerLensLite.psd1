@{
  RootModule           = 'OwnerLensLite.psm1'
  ModuleVersion        = '0.1.0'
  GUID                 = '6b7b66f2-1df0-4e37-ae88-6dfec389736a'
  Author               = 'OwnerLens'
  CompanyName          = 'OwnerLens'
  Copyright            = '(c) OwnerLens contributors. All rights reserved.'
  Description          = 'Evidence-backed ownership and dependency assessment for Microsoft Entra service principals across Microsoft Graph, Azure RBAC, Activity Logs, and Azure Storage.'
  PowerShellVersion    = '7.0'
  CompatiblePSEditions = @('Core')
  RequiredModules      = @(
    @{
      ModuleName    = 'PwshRichLite'
      ModuleVersion = '0.1.0'
      GUID          = '8a0fbf7e-2873-4cb8-b6f4-4477983b6117'
    }
  )
  FunctionsToExport    = @(
    'Invoke-OwnerLensLite'
  )
  CmdletsToExport      = @()
  VariablesToExport    = @()
  AliasesToExport      = @()
  PrivateData          = @{
    Name   = 'OwnerLens Lite'
    PSData = @{
      Prerelease   = 'preview1'
      Tags         = @('Azure', 'MicrosoftGraph', 'MicrosoftEntra', 'ServicePrincipal', 'AzureRBAC', 'IdentitySecurity', 'AccessGovernance', 'Ownership', 'DependencyAnalysis', 'Preview')
      LicenseUri   = 'https://www.apache.org/licenses/LICENSE-2.0'
      ProjectUri   = 'https://github.com/kodevza/ownerlenslite'
      ReleaseNotes = 'Preview release for evidence-backed ownership discovery and dependency analysis of Microsoft Entra service principals across Microsoft Graph and Azure.'
    }
  }
}
