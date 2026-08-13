@{
  RootModule = 'OwnerLensLight.psm1'
  ModuleVersion = '0.1.0'
  GUID = '6b7b66f2-1df0-4e37-ae88-6dfec389736a'
  Author = 'OwnerLens'
  CompanyName = 'OwnerLens'
  Copyright = '(c) OwnerLens contributors. All rights reserved.'
  Description = 'Lightweight local Enterprise Application dependency evidence workflow for Azure and Microsoft Entra.'
  PowerShellVersion = '7.0'
  CompatiblePSEditions = @('Core')
  FunctionsToExport = @(
    'Invoke-OwnerLensLight'
  )
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
  PrivateData = @{
    Name = 'OwnerLens Light'
    PSData = @{
      Prerelease = 'preview1'
      Tags = @('OwnerLens', 'Azure', 'Entra', 'EnterpriseApplication', 'ServicePrincipal', 'Preview')
      LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
      ProjectUri = 'https://github.com/kodevza/ownerlens-light'
      ReleaseNotes = 'Initial preview release of the lightweight OwnerLens Enterprise Application dependency inspector.'
    }
  }
}
