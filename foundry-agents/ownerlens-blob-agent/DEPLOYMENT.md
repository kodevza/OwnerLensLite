# OwnerLens Blob Agent Deployment

This is the short deployment record for the hosted Foundry agent:

- Foundry account: `$FOUNDRY_ACCOUNT_NAME`
- Foundry project: `$FOUNDRY_PROJECT_NAME`
- Agent name: `$FOUNDRY_HOSTED_AGENT_NAME`
- Active version after deployment: `$FOUNDRY_ACTIVE_AGENT_VERSION`
- Model deployment: `$AZURE_AI_MODEL_DEPLOYMENT_NAME`
- Storage account: `$OWNERLENS_STORAGE_ACCOUNT_NAME`
- Results container: `$OWNERLENS_RESULTS_CONTAINER`

From the repository root, enter the agent directory and load local deployment values before running commands:

```bash
cd foundry-agents/ownerlens-blob-agent
set -a
. ./.env
set +a
```

## 1. Select Subscription

```bash
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show --output json
```

## 2. Locate Resources

```bash
az graph query -q "Resources | where name in~ ('$FOUNDRY_ACCOUNT_NAME','$OWNERLENS_STORAGE_ACCOUNT_NAME') | project id, name, type, resourceGroup, subscriptionId, location" --output json
```

Project endpoint:

```text
$FOUNDRY_PROJECT_ENDPOINT
```

Existing model deployments:

```bash
az cognitiveservices account deployment list \
  --resource-group "$FOUNDRY_RESOURCE_GROUP" \
  --name "$FOUNDRY_ACCOUNT_NAME" \
  --output table
```

## 3. Install Local Deploy Dependencies

```bash
python3 -m venv .venv-foundry-agent
.venv-foundry-agent/bin/pip install \
  'azure-ai-projects>=2.3.0' \
  azure-identity \
  python-dotenv \
  azure-storage-blob \
  agent-framework-foundry \
  'agent-framework-foundry-hosting>=1.0.0a260630'
```

Validate local Python files:

```bash
.venv-foundry-agent/bin/python -m py_compile src/main.py deploy_hosted_agent.py smoke_test.py
```

## 4. Deploy Hosted Agent

The deployment reads `.env`, zips `src/`, creates a hosted agent version, waits until it is `active`, and routes 100% traffic to the new version.

```bash
.venv-foundry-agent/bin/python deploy_hosted_agent.py
```

Expected final shape:

```text
Created hosted agent version $FOUNDRY_ACTIVE_AGENT_VERSION
Provisioning status: active
agent_endpoint routes 100% traffic to agent_version $FOUNDRY_ACTIVE_AGENT_VERSION
```

Note: an earlier deployment used a model that failed hosted Responses with:

```text
Encrypted content is not supported with this model.
```

The working version uses `$AZURE_AI_MODEL_DEPLOYMENT_NAME`.

## 5. Grant Blob Write Access

After the hosted agent exists, inspect its runtime identity:

```bash
.venv-foundry-agent/bin/python - <<'PY'
import os
from dotenv import load_dotenv
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

load_dotenv(".env")

with DefaultAzureCredential() as cred, AIProjectClient(
    endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
    credential=cred,
) as client:
    agent = dict(client.agents.get(agent_name=os.environ["FOUNDRY_HOSTED_AGENT_NAME"]))
    print(agent["versions"]["latest"]["instance_identity"])
PY
```

Save the runtime identity to `.env` as `FOUNDRY_AGENT_RUNTIME_IDENTITY`.

The current deployment value is available in `$FOUNDRY_AGENT_RUNTIME_IDENTITY`.

Grant it Blob write access:

```bash
az role assignment create \
  --assignee-object-id "$FOUNDRY_AGENT_RUNTIME_IDENTITY" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$OWNERLENS_STORAGE_SCOPE" \
  --output json
```

Verify assignment:

```bash
az role assignment list \
  --assignee "$FOUNDRY_AGENT_RUNTIME_IDENTITY" \
  --scope "$OWNERLENS_STORAGE_SCOPE" \
  --output table
```

## 6. Smoke Test

```bash
.venv-foundry-agent/bin/python smoke_test.py
```

Manual smoke test with visible response:

```bash
.venv-foundry-agent/bin/python - <<'PY'
import os
from dotenv import load_dotenv
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

load_dotenv(".env")

with DefaultAzureCredential() as cred, AIProjectClient(
    endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
    credential=cred,
) as client:
    with client.get_openai_client(agent_name=os.environ["FOUNDRY_HOSTED_AGENT_NAME"]) as openai:
        response = openai.responses.create(input=(
            "Save exactly this JSON to Azure Blob as blob_name "
            f"{os.environ['OWNERLENS_SMOKE_BLOB_NAME']}: "
            f"{{\"status\":\"ok\",\"source\":\"foundry-hosted-agent-smoke\",\"agent\":\"{os.environ['FOUNDRY_HOSTED_AGENT_NAME']}\"}}. "
            "After saving, return only the JSON tool result."
        ))
        print(response.status)
        print(response.error)
        print(response.output_text)
PY
```

Expected response shape:

```json
{
  "storage_account": "<from OWNERLENS_STORAGE_ACCOUNT_NAME>",
  "container": "<from OWNERLENS_RESULTS_CONTAINER>",
  "blob_name": "<from OWNERLENS_SMOKE_BLOB_NAME>",
  "url": "<blob URL>"
}
```

## 7. Verify Blob

```bash
az storage blob show \
  --account-name "$OWNERLENS_STORAGE_ACCOUNT_NAME" \
  --container-name "$OWNERLENS_RESULTS_CONTAINER" \
  --name "$OWNERLENS_SMOKE_BLOB_NAME" \
  --auth-mode key \
  --query "{name:name, container:container, contentLength:properties.contentLength, contentType:properties.contentSettings.contentType, lastModified:properties.lastModified}" \
  --output json
```

Observed verification shape:

```json
{
  "container": "<from OWNERLENS_RESULTS_CONTAINER>",
  "contentLength": "<bytes>",
  "contentType": "application/json",
  "lastModified": "<timestamp>",
  "name": "<from OWNERLENS_SMOKE_BLOB_NAME>"
}
```

## Notes

- The agent uses Entra auth only. No storage connection string or key is passed to agent code.
- The principal that needs Blob RBAC is the hosted agent runtime identity, not the `AgentIdentityBlueprint`.
- The Entra display name for the runtime identity is:

```text
$FOUNDRY_AGENT_RUNTIME_DISPLAY_NAME
```
