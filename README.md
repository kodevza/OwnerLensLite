# OwnerLens Light

OwnerLens Light is a small local PowerShell module for inspecting one Microsoft Entra Enterprise Application / service principal and showing evidence-backed Azure dependencies.

The script resolves a service principal by object ID, app ID, or exact display name, then reports:

- Azure RBAC scopes where the service principal has access.
- Azure resource, resource group, and subscription dependencies implied by those RBAC scopes.
- Recent Azure Monitor activity log entries that match the service principal identifiers.
- Microsoft Graph app role assignments and delegated permission grants.
- Group memberships and owners.

Activity log matches are low-confidence usage evidence. They show recent access signals, not ownership proof.

## Requirements

- PowerShell 7.
- `Az` PowerShell module.
- `Microsoft.Graph.Authentication` PowerShell module.
- Azure and Microsoft Graph permissions sufficient to read role assignments, resources, activity logs, service principals, owners, groups, and permission grants.

Install modules when needed:

```powershell
Install-Module Az -Scope CurrentUser
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Usage

Run from this directory:

```powershell
./Invoke-OwnerLensLight.ps1 -EnterpriseApplication "<service-principal-object-id-or-app-id>" -SubscriptionIds "sub-id-1,sub-id-2" -ActivityDays 30
```

Or import the module directly:

```powershell
Import-Module ./ownerlens/ownerlens.psd1 -Force
Invoke-OwnerLensLight -EnterpriseApplication "<service-principal-object-id-or-app-id>"
```

Write a JSON report:

```powershell
./Invoke-OwnerLensLight.ps1 -EnterpriseApplication "<app-id>" -OutputPath ./reports/app-dependencies.json
```

Skip Azure Monitor activity logs when you only need static access/dependency evidence:

```powershell
./Invoke-OwnerLensLight.ps1 -EnterpriseApplication "<app-id>" -SkipActivityLogs
```

By default, when `-SubscriptionIds` is omitted, the script inspects only the current Azure subscription from `Get-AzContext`.

## Authentication

The script can start interactive login if no context exists:

- `Connect-MgGraph -Scopes Application.Read.All,Directory.Read.All,Group.Read.All`
- `Connect-AzAccount`

Use `-SkipLogin` when running in an environment that already provides both contexts.

## Tests

```powershell
Invoke-Pester ./tests
```

## Publishing

The GitHub Actions workflow signs all module `.ps1`, `.psm1`, and `.psd1` files, then publishes the module to PowerShell Gallery as `ownerlens` with prerelease label `preview`.

Required repository secrets:

- `CODE_SIGNING_CERTIFICATE_BASE64`: base64-encoded PFX code-signing certificate.
- `CODE_SIGNING_CERTIFICATE_PASSWORD`: password for the PFX.
- `PSGALLERY_API_KEY`: PowerShell Gallery API key allowed to publish `ownerlens`.
