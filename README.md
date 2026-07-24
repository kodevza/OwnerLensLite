# OwnerLens Light

OwnerLens Light is a small local PowerShell module for inspecting one Microsoft Entra Enterprise Application / service principal and showing evidence-backed Azure dependencies.

The script resolves a service principal by object ID, app ID, or exact display name, then reports:

- Azure RBAC scopes where the service principal has access.
- Azure resource, resource group, and subscription dependencies implied by those RBAC scopes.
- Recent Azure Monitor activity log entries that match the service principal identifiers.
- Recent Azure Monitor activity callers under RBAC scopes assigned to the service principal.
- Microsoft Graph app role assignments and delegated permission grants.
- Group memberships, service principal owners, and application registration owners.

Activity log matches are low-confidence usage evidence. They show recent access signals, not ownership proof.
The RBAC scope activity caller view uses Azure Activity Logs, so it covers management-plane operations under the relevant subscription/resource group/resource scopes. It does not prove data-plane access such as blob reads/writes, secret reads, database queries, or application requests; those require resource diagnostic logs, usually routed to Log Analytics.
Blob data-plane evidence uses the `StorageBlobLogs` Log Analytics table and looks for `GetBlob`, `PutBlob`, `PutBlock`, `PutBlockList`, `AppendBlock`, and `CopyBlob` by default.

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
Import-Module ./OwnerLensLight/OwnerLensLight.psd1 -Force
Invoke-OwnerLensLight -EnterpriseApplication "<service-principal-object-id-or-app-id>"
```

Write a JSON report:

```powershell
./Invoke-OwnerLensLight.ps1 -EnterpriseApplication "<app-id>" -OutputPath ./reports/app-dependencies.json
```

Include blob data-plane evidence from a Log Analytics workspace that receives Storage Account diagnostic logs:

```powershell
./Invoke-OwnerLensLight.ps1 `
  -EnterpriseApplication "<app-id>" `
  -SubscriptionIds "sub-id-1,sub-id-2" `
  -LogAnalyticsWorkspaceId "<workspace-guid>" `
  -ActivityDays 30
```

The blob data-plane section reports storage accounts under the Enterprise Application's RBAC scopes, recent read/publish operations, and participants grouped by object ID, app ID, and UPN together when Azure logs them together. This matters for agent-style flows where communication can be bidirectional: a user may publish blobs to the agent while a service principal reads them, or the service principal may publish data that users read later. The signed-in Azure identity must be able to query the Log Analytics workspace, and the relevant Storage Accounts must have diagnostic settings sending blob logs to that workspace.

Configure blob read/write diagnostic logs for storage accounts:

```powershell
./scripts/Set-StorageBlobReadDiagnosticLogs.ps1 `
  -WorkspaceId "<workspace-guid>" `
  -WhatIf
```

Remove `-WhatIf` to create or update the `ownerlens-blob-read-logs` diagnostic setting on each Blob service. By default the script scans all enabled subscriptions visible to the current Az account and enables `StorageRead` plus `StorageWrite`, which records blob reads and writes in `StorageBlobLogs`. Use `-SubscriptionIds` to limit the scan. If the workspace cannot be resolved from its GUID, use `-WorkspaceResourceId` with the full ARM resource ID.

Show only potential owner candidates as TSV for easier copying:

```powershell
./Invoke-OwnerLensLight.ps1 -EnterpriseApplication "<app-id>" -OutputTable
```

The candidate TSV includes the candidate value, whether it came from a user, group, tag, or another source, a human-readable confidence value (`HIGH`, `MED`, or `LOW`), whether the evidence is `Direct` or `Indirect`, a short signal (`OWNER`, `TAG`, `RBAC`, `LOG`, or `MEMBERSHIP`), and concrete `evidenceId` values. For Azure signals, evidence ids are ARM resource ids or scopes such as `/subscriptions/.../resourceGroups/.../providers/...`. Tag candidates found directly on the inspected Enterprise Application use `TAG`; tag candidates found on Azure dependency resources use `RBAC`, because the tag is on a resource reached through RBAC assigned to the inspected service principal. Only configured owner tag names are promoted to owner candidates. User owner tags produce `User` candidates from the tag value, group owner tags produce `Group` candidates from the tag value, and generic tag owner tags produce `Tag` candidates such as `costCenter=12345`. When no candidate evidence is found, the TSV returns a `NotFound` row with relationship `None`, signal `NONE`, and evidence id `not-found`.

Configure owner tag names when your tenant uses different tag keys:

```powershell
./Invoke-OwnerLensLight.ps1 `
  -EnterpriseApplication "<app-id>" `
  -UserOwnerTagNames "ownerMail","technicalOwner" `
  -GroupOwnerTagNames "ownerGroup","team" `
  -TagOwnerTagNames "owner","costCenter","billingCode" `
  -OutputTable
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

The GitHub Actions workflow uses the same signing model as the main OwnerLens package pipeline: Azure OIDC login plus Azure Artifact Signing. It signs all module `.ps1`, `.psm1`, and `.psd1` files, verifies Authenticode signatures and timestamps, then publishes the module to PowerShell Gallery as `OwnerLensLight` with prerelease label `preview`.

Required repository secrets:

- `AZURE_CLIENT_ID`: federated identity client ID for Azure login.
- `AZURE_TENANT_ID`: Azure tenant ID.
- `AZURE_SUBSCRIPTION_ID`: Azure subscription ID.
- `ARTIFACT_SIGNING_ENDPOINT`: Azure Artifact Signing endpoint.
- `ARTIFACT_SIGNING_ACCOUNT_NAME`: Azure Artifact Signing account name.
- `ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME`: Azure Artifact Signing certificate profile name.
- `PSGALLERY_API_KEY`: PowerShell Gallery API key allowed to publish `OwnerLensLight`.

Configure them from local environment variables or a local `.env.github-secrets` file:

```powershell
./scripts/Set-OwnerLensLightGitHubSecrets.ps1
```

The dotenv file should use `NAME=value` lines. It is ignored by git.
