# OwnerLens Refund Demo

Small Azure demo designed specifically to produce a useful **workload-identity / ownership graph**.

It contains:

- **Refund Agent** — confidential Entra application + service principal; no explicit human owner.
- **Billing Service** — Python Azure Function + FastAPI; accepts refund requests and creates a negative adjustment; no explicit human owner on its API identity.
- **Billing Caller Identity** — user-assigned managed identity used by Billing to call Payment; no explicit human owner.
- **Payment Service** — Python Azure Function + FastAPI; simulates moving real money; **the only service with an explicit human owner in Entra**.
- **Microsoft Entra app roles** connecting the identities.
- **Azure App Service Easy Auth** protecting all business endpoints.
- FastAPI **Swagger UI**, **ReDoc**, and generated **OpenAPI 3** on both services.

> This is a demo, not a real billing/payment system. State is in memory, there is no ledger persistence, idempotency store, PSP integration, reconciliation, fraud control, or accounting-grade audit trail.

## Graph we want OwnerLens to discover

```text
Refund Agent
Entra Application + Service Principal
owner: <missing>
technical context: AIPlatform
        |
        | appRole: Refund.Request
        v
Billing API
Entra Application + Service Principal
owner: <missing>
technical context: BillingPlatform
        |
        | Function App uses
        v
Billing Caller UAMI
Entra Managed Identity Service Principal
owner: <missing>
        |
        | appRole: Refund.Execute
        v
Payment API
Entra Application + Service Principal
owner: <SIGNED-IN DEPLOYER>
criticality: Financial
        |
        v
Simulated PSP / bank payout
```

The interesting OwnerLens conclusion is not "Payment owner = Agent owner". It is:

> The first strong human ownership signal on a path capable of financial impact exists at Payment Service, while upstream workloads with permission to initiate that path have no explicit owner.

## Request flow

```text
Agent
  | OAuth2 client_credentials
  | scope: Billing API /.default
  v
Billing Function /api/v1/refunds
  | creates Adjustment(amount = -49.90)
  |
  | OAuth2 using user-assigned managed identity
  | scope: Payment API /.default
  v
Payment Function /api/v1/refunds/execute
  |
  v
simulated settled refund
```

`POST /api/v1/bdrs` is the matching debit flow: it creates a BDR (Billing Debit
Request) and invokes `POST /api/v1/charges/execute` on Payment. It uses the
separate `Charge.Request` and `Charge.Execute` application roles.

## Security model

### Agent -> Billing

- Entra application permission / app role: `Refund.Request`
- Billing Enterprise Application has `appRoleAssignmentRequired = true`
- Easy Auth validates issuer + audience and allows only the **Refund Agent client ID**
- Billing code checks the `Refund.Request` role from Easy Auth's `X-MS-CLIENT-PRINCIPAL`

### Billing -> Payment

- Billing does **not** contain a client secret.
- It uses a **user-assigned managed identity**.
- That managed identity receives Payment app role `Refund.Execute`.
- Payment Easy Auth allows only that managed identity's client ID.
- Payment code checks `Refund.Execute` from Easy Auth claims.

### Swagger / OpenAPI

For demo usability these paths are intentionally public:

```text
/health
/docs
/redoc
/openapi.json
```

All `/api/...` routes require Entra authentication. If you want even the API schema private, remove `/docs`, `/redoc`, and `/openapi.json` from `excludedPaths` in `infra/main.bicep`.

## Repository layout

```text
services/
  billing/
    function_app.py
    app/
    requirements.txt
    host.json
  payment/
    function_app.py
    app/
    requirements.txt
    host.json
agent/
  client.py
infra/
  main.bicep
  bicepconfig.json
scripts/
  deploy.sh
  bootstrap-agent-secret.sh
  test-local.sh
tests/
```

## Prerequisites

Local deployment script expects:

- Azure CLI
- Bicep >= `0.36.1` (Microsoft Graph Bicep v1.0 extension)
- `jq`
- `zip`
- Python 3
- an Azure subscription
- enough Azure RBAC to create Function Apps and role assignments
- enough Microsoft Entra permissions to create applications/service principals, assign app roles, and set the Payment owner

Microsoft Graph Bicep is GA and the repo pins:

```json
"br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:1.0.0"
```

Check available Flex Consumption locations before deployment if needed:

```bash
az functionapp list-flexconsumption-locations \
  --query "sort_by(@, &name)[].{Region:name}" -o table
```

## Deploy

Default region is `westeurope`:

```bash
./scripts/deploy.sh rg-ownerlens-refund-demo westeurope olrefund
```

By default, the signed-in Azure user's Entra object ID becomes the explicit Payment owner.

To use someone else:

```bash
export PAYMENT_OWNER_OBJECT_ID=<entra-user-object-id>
./scripts/deploy.sh rg-ownerlens-refund-demo westeurope olrefund
```

The script:

1. creates the resource group,
2. deploys Azure + Entra resources using Bicep,
3. deploys both Python Function apps,
4. creates a **30-day local client secret** for the Refund Agent,
5. writes it to `.env.agent` with mode `600`.

`.env.agent` is gitignored.

## Call the Billing API as the agent

```bash
set -a
source .env.agent
set +a

python3 -m pip install -r agent/requirements.txt
python3 agent/client.py
```

Expected shape:

```json
{
  "adjustment": {
    "account_id": "acc-100042",
    "amount": "-49.90",
    "currency": "PLN",
    "status": "refund_submitted"
  },
  "payment": {
    "status": "settled",
    "provider_reference": "psp-..."
  }
}
```

## OpenAPI

After deploy the Bicep outputs contain:

```text
https://<billing-app>.azurewebsites.net/docs
https://<billing-app>.azurewebsites.net/openapi.json

https://<payment-app>.azurewebsites.net/docs
https://<payment-app>.azurewebsites.net/openapi.json
```

The generated schema includes an Entra OAuth2 **client credentials** security scheme and the application permission required by each API.

## Local tests

The checked-in tests run the business logic with `AUTH_MODE=disabled` and use a local simulated payment result for Billing:

```bash
./scripts/test-local.sh
```

The source itself never defaults Azure deployments to disabled auth; Bicep explicitly sets `AUTH_MODE=easyauth`.

## What OwnerLens should see in Entra

### Explicit ownership

| Identity | Explicit Entra owner |
|---|---|
| Refund Agent app/SP | no |
| Billing API app/SP | no |
| Billing Caller managed identity SP | no |
| Payment API app/SP | **yes** |

### Permission edges

```text
Refund Agent SP
  -- appRoleAssignment: Refund.Request --> Billing API SP

Billing Caller Managed Identity SP
  -- appRoleAssignment: Refund.Execute --> Payment API SP
```

### Additional evidence

Applications and Azure resources include intentionally different context tags such as:

```text
TechnicalTeam:AIPlatform
TechnicalTeam:BillingPlatform
Criticality:Financial
Ownership:MissingHumanOwner
Ownership:Explicit
```

These are evidence/context, not substitutes for an actual Entra owner relationship.

## Production gaps intentionally left in the demo

For a real refund platform you would still need at minimum:

- durable adjustment/ledger storage,
- idempotency keys,
- payment/refund state machine,
- retry/outbox pattern,
- reconciliation,
- immutable audit log,
- limits and fraud controls,
- separation of approval from execution for higher amounts,
- secretless agent authentication where possible (managed identity/workload identity federation instead of a local client secret).

For this OwnerLens demonstration, adding those would mostly add noise rather than improve the ownership graph.

## Official references used for the design

- Azure Functions + FastAPI / ASGI: https://learn.microsoft.com/samples/azure-samples/fastapi-on-azure-functions/fastapi-on-azure-functions/
- Azure Functions infrastructure as code / Flex Consumption: https://learn.microsoft.com/azure/azure-functions/functions-infrastructure-as-code
- Entra OAuth2 client credentials: https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow
- Microsoft Graph app role assignments: https://learn.microsoft.com/graph/api/serviceprincipal-post-approleassignedto
- Microsoft Graph Bicep: https://learn.microsoft.com/graph/templates/bicep/overview-bicep-templates-for-graph
- App Service / Functions authsettingsV2: https://learn.microsoft.com/azure/templates/microsoft.web/sites/config-authsettingsv2
- App Service authentication claims: https://learn.microsoft.com/azure/app-service/configure-authentication-user-identities
