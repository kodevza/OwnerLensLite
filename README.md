# OwnerLensLite

OwnerLensLite is a local PowerShell module for building an evidence-backed ownership and dependency assessment for a Microsoft Entra Enterprise Application (service principal). It correlates Microsoft Graph relationships with Azure RBAC, Activity Log, and optional Azure Storage data-plane evidence so that every reported ownership candidate is traceable to its source.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/OwnerLensLite?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/OwnerLensLite)
[![PowerShell Gallery downloads](https://img.shields.io/powershellgallery/dt/OwnerLensLite?label=downloads)](https://www.powershellgallery.com/packages/OwnerLensLite)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

![OwnerLensLite demo](demo.gif)

It is designed to answer:

- Where does this service principal have Azure access?
- What Graph relationships exist around it?
- Which users, groups, tags, RBAC neighbors, or operational actors are plausible owner candidates?
- What exact evidence caused each candidate to appear?

OwnerLensLite does **not** treat the nearest human as the owner. Explicit ownership is strong evidence; RBAC proximity, memberships, and activity are weaker signals.

## Requirements

- PowerShell 7+
- `Az`
- `Microsoft.Graph.Authentication`
- `PwshRichLite` 0.1.0+

```powershell
# OwnerLensLite is distributed through the PowerShell Gallery.
Install-Module OwnerLensLite -Scope CurrentUser

# Install these runtime dependencies if they are not already available.
Install-Module Az -Scope CurrentUser
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Quick start

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<service-principal-object-id-or-app-id>"
```

`-EnterpriseApplication` accepts:

- service-principal object ID,
- application/client ID (`appId`),
- exact service-principal display name.

Scan explicit subscriptions:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -SubscriptionIds "sub-id-1,sub-id-2"
```

If `-SubscriptionIds` is omitted, only the current Azure subscription from `Get-AzContext` is inspected.

During collection, the command prints timestamped progress updates. Azure updates identify the current subscription and report completed stages such as resource/RBAC discovery, Activity Log collection, and optional Log Analytics queries.

# Authentication and permissions

OwnerLensLite uses separate Microsoft Graph and Azure sessions. If no context exists, interactive authentication starts automatically unless `-SkipLogin` is used.

## Microsoft Graph

Default delegated scopes:

```text
Application.Read.All
Directory.Read.All
Group.Read.All
```

When `-SignInUser` is used, OwnerLensLite also requests:

```text
AuditLog.Read.All
```

These scopes commonly require tenant administrator consent.

Graph calls performed:

| Evidence | Endpoint |
|---|---|
| Resolve service principal | `/servicePrincipals/{id}` or filtered `/servicePrincipals` |
| Resolve backing application | `/applications?$filter=appId eq ...` |
| Service-principal owners | `/servicePrincipals/{id}/owners` |
| Application owners | `/applications/{id}/owners` |
| App-role assignments | `/servicePrincipals/{id}/appRoleAssignments` |
| Delegated grants | `/oauth2PermissionGrants?$filter=clientId eq ...` |
| Directory memberships | `/servicePrincipals/{id}/memberOf` |
| Referenced resource SPs | `/servicePrincipals/{resourceId}` |
| Optional user sign-ins | `/auditLogs/signIns` |

Scopes can be overridden with `-Scopes`.

## Azure

For a normal read-only assessment, a practical baseline is:

```text
Reader
```

on every scanned subscription.

The script reads data equivalent to:

```text
Get-AzSubscription
Get-AzResource
Get-AzResourceGroup
Get-AzRoleAssignment
Get-AzDiagnosticSetting
Microsoft.Insights/eventtypes/management/values/read
```

This is used for subscriptions, resources, resource groups, tags, RBAC assignments, Azure Activity Logs, and diagnostic settings.

## Log Analytics

If `-LogAnalyticsWorkspaceId` is used, the caller must be able to query that workspace and read `StorageBlobLogs`.

Use an appropriately scoped:

```text
Log Analytics Data Reader
```

or the broader:

```text
Log Analytics Reader
```

## Configuring Storage diagnostics

`./scripts/Set-StorageBlobReadDiagnosticLogs.ps1` writes diagnostic settings and therefore needs a permission equivalent to:

```text
Microsoft.Insights/diagnosticSettings/write
```

`Monitoring Contributor` is one practical built-in option when scoped appropriately.

# What is checked

## Microsoft Graph evidence

OwnerLensLite collects:

1. **Enterprise Application / service principal metadata**
   - object ID,
   - backing application object ID,
   - app ID,
   - display names,
   - service-principal type,
   - publisher,
   - account-enabled state,
   - owner organization,
   - URLs,
   - service-principal names,
   - service-principal tags.

2. **Explicit owners**
   - service-principal owners,
   - application-registration owners.

3. **API dependencies**
   - app-role assignments,
   - delegated OAuth permission grants,
   - referenced resource service principals.

4. **Directory relationships**
   - objects returned by `servicePrincipal/memberOf`.

5. **Optional user sign-ins**
   - enabled with `-SignInUser`,
   - constrained by `-ActivityDays`,
   - requires `AuditLog.Read.All`.

User sign-ins are report evidence only; they are not directly promoted to owner candidates.

## Azure RBAC evidence

For every selected subscription OwnerLensLite executes the equivalent of:

```powershell
Get-AzRoleAssignment -ObjectId <service-principal-object-id>
```

For every assignment it records:

- subscription,
- role-assignment ID,
- exact RBAC scope,
- principal metadata,
- role-definition ID/name,
- condition and condition version,
- Storage data-plane role classification.

Scopes are classified as:

```text
Subscription
ResourceGroup
Resource
ManagementGroup
Unknown
```

Resource Group and resource scopes are enriched with resource metadata and tags where available.

## Same-scope RBAC principals

For every unique scope assigned to the inspected service principal:

```powershell
Get-AzRoleAssignment -Scope <same-scope>
```

OwnerLensLite collects other principals assigned on that **exact same scope**.

These become low-confidence owner candidates. The current logic does not increase confidence because another principal has a stronger role; shared scope itself is the signal.

## Azure tags

OwnerLensLite checks owner-like tags in two places:

- directly on the inspected service principal,
- on the Azure Resource Group/resource represented by an RBAC dependency.

Only configured tag names are promoted to owner candidates.

A direct service-principal tag is stronger than a tag reached indirectly through Azure RBAC.

## Azure Activity Logs

Unless `-SkipActivityLogs` is used, Activity Logs are collected for the selected window.

Defaults:

```text
ActivityDays       = 30
MaxActivityRecords = 5000 per subscription
```

Two forms of evidence are built.

### Activity matching the inspected service principal

A log matches when one of these matches the inspected identity:

- caller object ID,
- caller app ID,
- caller equal to app ID,
- caller name equal to service-principal display name.

### Activity below inspected RBAC scopes

OwnerLensLite also finds management-plane events whose authorization scope or resource ID is equal to or below a scope assigned to the inspected service principal.

Callers are grouped primarily by object ID, then app ID, caller, or caller name.

Other callers active under those scopes can become low-confidence owner candidates.

Activity Logs are **management-plane evidence**, not proof of Blob, Key Vault secret, database, or application-level access.

## Diagnostic settings

OwnerLensLite checks:

- subscription Activity Log diagnostic settings,
- Storage Blob/Table/Queue diagnostic settings where relevant.

It detects destinations including:

- Log Analytics,
- Storage Account,
- Event Hub,
- Marketplace Partner.

## Storage data-plane RBAC

The current Storage role classifier recognizes:

```text
Storage Blob Data Reader
Storage Blob Data Contributor
Storage Blob Data Owner
Storage Table Data Reader
Storage Table Data Contributor
Storage Queue Data Reader
Storage Queue Data Contributor
Storage Queue Data Message Processor
```

When the inspected service principal has one of these roles, OwnerLensLite finds Storage Accounts below the assignment scope and checks the corresponding Blob/Table/Queue service.

## StorageBlobLogs

Enable data-plane evidence with:

```powershell
-LogAnalyticsWorkspaceId "<workspace-guid>"
```

OwnerLensLite queries `StorageBlobLogs` only for Storage Accounts reached through recognized Storage data-plane RBAC roles.

Default operations:

```text
GetBlob
PutBlob
PutBlock
PutBlockList
AppendBlock
CopyBlob
```

Override them with `-BlobReadOperationNames`.

Collected fields can include requester object/app/tenant IDs, UPN, IP, user agent, authentication type, operation, safe URI, object key, and whether the requester matches the inspected service principal.

General Blob participants are displayed as evidence but are **not** currently promoted to owner candidates.

## User-delegation SAS generator

For SAS-authenticated Blob events OwnerLensLite extracts SAS metadata and correlates `skoid` with `GetUserDelegationKey` events in `StorageBlobLogs`.

If correlation succeeds, the principal that generated the user-delegation SAS is promoted as an owner candidate. This is separate from the principal that later used the SAS.

# Owner candidate scoring

Owner candidate creation and promotion are centralized in:

```text
OwnerLensLite/Private/Get-OwnerCandidate.ps1
```

The central policy is `$OwnerCandidatePolicy`:

```powershell
$OwnerCandidatePolicy = @{
  ExplicitOwner = @{
    Enabled = $true
    Score = 95
    Signal = "OWNER"
  }
  ExplicitOwnerTag = @{
    Enabled = $true
    Score = 80
    Signal = "TAG"
  }
  DirectoryRelationship = @{
    Enabled = $true
    Score = 30
    Signal = "MEMBERSHIP"
  }
  SharedRbacScope = @{
    Enabled = $true
    ScoreByCandidateType = @{
      User = 35
      Group = 30
      Default = 30
    }
    Signal = "RBAC"
  }
  OperationalActivity = @{
    Enabled = $true
    Score = 25
    Signal = "LOG"
  }
  CredentialGenerator = @{
    Enabled = $true
    Score = 40
    Signal = "SAS"
  }
}
```

Current mapping:

| Rule | Evidence | Score | Confidence | Relationship | Signal |
|---|---|---:|---|---|---|
| `ExplicitOwner` | Graph owner | 95 | HIGH | Direct | OWNER |
| `ExplicitOwnerTag` | owner tag directly on SP | 80 | HIGH | Direct | TAG |
| `DirectoryRelationship` | `memberOf` | 30 | LOW | Indirect | MEMBERSHIP |
| `SharedRbacScope` User | user on exact same scope | 35 | LOW | Indirect | RBAC |
| `SharedRbacScope` Group/default | same-scope principal or dependency tag | 30 | LOW | Indirect | RBAC |
| `OperationalActivity` | Azure activity relationship | 25 | LOW | Indirect | LOG |
| `CredentialGenerator` | user-delegation SAS generator | 40 | LOW | Indirect | SAS |

Confidence thresholds:

```text
score >= 80  -> HIGH
score >= 50  -> MED
score < 50   -> LOW
```

With the default policy no rule currently produces `MED`.

## Important: scores are not cumulative

The current implementation does **not** add multiple evidence signals together.

```text
RBAC = 35
LOG  = 25
```

does not become `60 / MED`.

Instead, separate evidence rows are created. The current model is **best-signal ranking**, not cumulative scoring.

The rich Owner Candidates table shows raw evidence rows. `-OutputTable` groups by `candidate + candidateType`, keeps the highest confidence, merges signal/relationship values, and includes up to four evidence IDs.

The full JSON report preserves every candidate evidence row.

# Changing scoring

Scoring is currently code configuration, not a CLI or external config file.

Edit:

```text
OwnerLensLite/Private/Get-OwnerCandidate.ps1
```

Example: make same-scope users `MED`:

```powershell
SharedRbacScope = @{
  Enabled = $true
  ScoreByCandidateType = @{
    User = 55
    Group = 30
    Default = 30
  }
  Signal = "RBAC"
}
```

Disable a promotion source without removing its evidence from the report:

```powershell
OperationalActivity = @{
  Enabled = $false
  Score = 25
  Signal = "LOG"
}
```

Confidence thresholds are centralized in `ConvertTo-OwnerConfidence` in the same file.

# Configuring owner tags

Runtime parameters:

```powershell
-UserOwnerTagNames
-GroupOwnerTagNames
-TagOwnerTagNames
```

Defaults:

```text
User:
  userOwner
  technicalOwner
  businessOwner

Group:
  groupOwner
  ownerGroup
  teamOwner
  team

Generic:
  owner
  serviceOwner
  appOwner
  applicationOwner
  productOwner
  ownedBy
  costCenter
  costCentre
  cost-center
  cost_center
```

Example:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -UserOwnerTagNames "ownerMail","technicalOwner" `
  -GroupOwnerTagNames "ownerGroup","team" `
  -TagOwnerTagNames "owner","costCenter","billingCode"
```

Promotion behavior:

- User tag value -> `User` candidate.
- Group tag value -> `Group` candidate.
- Generic tag -> `Tag` candidate as `name=value`.

Direct service-principal tags are parsed when stored as either `name=value` or `name:value`.

Source affects the relationship:

```text
SP tag              -> Direct / TAG
Azure dependency tag -> Indirect / RBAC
```

# Candidate promotion map

| Source evidence | Promoted candidate | Default confidence |
|---|---|---|
| Service-principal Graph owner | owner | HIGH |
| Application-registration Graph owner | owner | HIGH |
| Configured tag directly on SP | User / Group / Tag | HIGH |
| `servicePrincipal/memberOf` | directory object | LOW |
| Other principal on exact same Azure RBAC scope | principal | LOW |
| Configured tag on RBAC dependency | User / Group / Tag | LOW |
| Activity matched to inspected SP | activity caller | LOW |
| Other caller active under inspected SP scope | caller | LOW |
| User-delegation SAS generator | generator | LOW |

If no candidates exist, the report emits a `NotFound` row with signal `NONE` and evidence ID `not-found`.

# RBAC Relationship Tree

Normal invocation displays the RBAC tree:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -SubscriptionIds "<subscription-id>"
```

For the richest tree:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -SubscriptionIds "<subscription-id>" `
  -ActivityDays 30 `
  -LogAnalyticsWorkspaceId "<workspace-guid>"
```

Tree inputs:

```text
azure.roleAssignments
azure.resourceDependencies
azure.coAssignedRoleCandidates
azure.rbacScopeActivityCallers
azure.storageAccountsWithRbac
azure.blobReadCallers
```

Conceptually:

```text
Service Principal: my-app
└── ResourceGroup: rg-app
    ├── scope: /subscriptions/.../resourceGroups/rg-app
    ├── roles for inspected SP
    │   └── Contributor
    ├── tags
    │   ├── owner=platform-team
    │   └── costCenter=CC-1042
    ├── other principals on same scope
    │   ├── Alice Example (User)
    │   │   └── Reader
    │   └── Platform Team (Group)
    │       └── Contributor
    ├── recent activity callers
    │   └── Alice Example (... events=8, lastSeen=...)
    └── storage accounts with data-plane read
        └── stappdata
            ├── diagnostics=QueryableInLogAnalytics
            └── blob data-plane participants
```

The tree means:

```text
service principal
  -> RBAC scope
    -> roles / tags / neighboring principals / activity / Storage evidence
```

It does **not** mean that every neighboring principal is an owner.

`-SkipActivityLogs` removes Activity Log collection and activity-based candidates. Without `-LogAnalyticsWorkspaceId`, Storage RBAC and diagnostics can still be shown, but Blob participants cannot be populated.

# Table output

## Full rich evidence tables

Use `-Verbose`:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -SubscriptionIds "<subscription-id>" `
  -Verbose
```

Possible sections:

1. Enterprise Application
2. Summary
3. Azure RBAC Relationship Tree
4. Azure Activity Evidence
5. Azure RBAC Scope Activity Callers
6. Azure RBAC Scope Activity Evidence
7. Azure Activity Diagnostic Settings
8. Storage Accounts With Data-Plane Read
9. Storage Diagnostic Settings
10. Blob Data-Plane Participants
11. Blob Reads By Object
12. Blob Data-Plane Evidence
13. Graph App Role Assignments
14. Graph Delegated Permission Grants
15. Graph Group Memberships
16. Graph User Sign-Ins
17. Graph User Sign-In Locations
18. Owner Candidates

Empty sections are skipped.

Use this mode when you need to inspect individual evidence rows: exact role assignments, callers, operations, diagnostics, Blob participants, Graph permissions, or candidate evidence IDs.

## Owner Candidates TSV

`-OutputTable` is **not** the full evidence-table mode. It returns only grouped owner candidates:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -OutputTable
```

Columns:

```text
candidate
type
confidence
relationship
signal
evidenceId
```

For automation or deeper analysis prefer `-OutputJson`.

# Full JSON report

## Export do pliku JSON

Najprostszy eksport zapisz do wskazanego pliku przez `-OutputPath`. Katalog
docelowy zostanie utworzony automatycznie, jeśli jeszcze nie istnieje.

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id-lub-service-principal-object-id>" `
  -OutputPath "./reports/ownerlens.json"
```

Przykład z danymi Blob data-plane (wymaga identyfikatora workspace, do którego
trafiają `StorageBlobLogs`):

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id-lub-service-principal-object-id>" `
  -LogAnalyticsWorkspaceId "<log-analytics-workspace-id>" `
  -OutputPath "./reports/ownerlens.json"
```

Po zakończeniu raport jest w `./reports/ownerlens.json`. Parametr `-OutputJson`
zwraca JSON na standardowe wyjście, co jest przydatne w pipeline'ach lub gdy
nie chcesz od razu zapisywać pliku:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -OutputJson
```

Report shape:

```text
meta
enterpriseApplication
summary
azure
  subscriptions
  roleAssignments
  coAssignedRoleCandidates
  resourceDependencies
  activityEvidence
  rbacScopeActivityEvidence
  rbacScopeActivityCallers
  activityDiagnosticSettings
  storageAccountsWithRbac
  blobReadEvidence
  blobReadCallers
  blobReadObjects
graph
  owners
  appRoleAssignments
  oauth2PermissionGrants
  memberOf
  resourceServicePrincipals
  userSignIns
ownerCandidates
notes
```

Each raw candidate row contains:

```text
candidate
candidateType
confidence
relationship
signal
evidenceId
evidenceSource
evidenceValue
reason
```

# Storage Blob diagnostic setup

Preview:

```powershell
./scripts/Set-StorageBlobReadDiagnosticLogs.ps1 `
  -WorkspaceId "<workspace-guid>" `
  -WhatIf
```

Apply:

```powershell
./scripts/Set-StorageBlobReadDiagnosticLogs.ps1 `
  -WorkspaceId "<workspace-guid>"
```

The helper enables Blob diagnostic logging to the selected workspace; the default configuration includes `StorageRead` and `StorageWrite`.

Then run:

```powershell
Invoke-OwnerLensLite `
  -EnterpriseApplication "<app-id>" `
  -LogAnalyticsWorkspaceId "<workspace-guid>" `
  -ActivityDays 30
```

# Current limitations

- Scoring is hard-coded in `$OwnerCandidatePolicy`; there is no external scoring configuration yet.
- Evidence scores are not cumulative.
- Numeric score is converted to `HIGH/MED/LOW` and is not stored in each candidate row.
- Same-scope RBAC uses proximity only; role semantics do not increase ownership confidence.
- Activity Logs cover management-plane activity only.
- Blob evidence depends on Storage diagnostic logs being available in Log Analytics.
- General Blob participants are not promoted; correlated user-delegation SAS generators are.
- User sign-ins are optional report evidence and are not directly promoted.
- Only configured owner-like tag names are promoted.
- Exact display-name resolution can be ambiguous; object ID or app ID is preferable.

# Tests

```powershell
Invoke-Pester ./tests
```

# References

- [Microsoft Graph servicePrincipal resource type](https://learn.microsoft.com/graph/api/resources/serviceprincipal?view=graph-rest-1.0) and [application resource type](https://learn.microsoft.com/graph/api/resources/application?view=graph-rest-1.0)
- [Azure built-in roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles) and [Azure RBAC overview](https://learn.microsoft.com/azure/role-based-access-control/overview)
- [Azure Activity Log](https://learn.microsoft.com/azure/azure-monitor/essentials/activity-log) and [diagnostic settings](https://learn.microsoft.com/azure/azure-monitor/essentials/diagnostic-settings)
- [Azure Blob Storage monitoring data reference](https://learn.microsoft.com/azure/storage/blobs/monitor-blob-storage-reference)
