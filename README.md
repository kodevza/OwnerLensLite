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

The GitHub Actions workflow uses the same signing model as the main OwnerLens package pipeline: Azure OIDC login plus Azure Artifact Signing. It signs all module `.ps1`, `.psm1`, and `.psd1` files, verifies Authenticode signatures and timestamps, then publishes the module to PowerShell Gallery as `ownerlens` with prerelease label `preview`.

Required repository secrets:

- `AZURE_CLIENT_ID`: federated identity client ID for Azure login.
- `AZURE_TENANT_ID`: Azure tenant ID.
- `AZURE_SUBSCRIPTION_ID`: Azure subscription ID.
- `ARTIFACT_SIGNING_ENDPOINT`: Azure Artifact Signing endpoint.
- `ARTIFACT_SIGNING_ACCOUNT_NAME`: Azure Artifact Signing account name.
- `ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME`: Azure Artifact Signing certificate profile name.
- `PSGALLERY_API_KEY`: PowerShell Gallery API key allowed to publish `ownerlens`.

Configure them from local environment variables or a local `.env.github-secrets` file:

```powershell
./scripts/Set-OwnerLensLightGitHubSecrets.ps1
```

The dotenv file should use `NAME=value` lines. It is ignored by git.
