#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCE_GROUP="${1:?usage: bootstrap-agent-secret.sh <resource-group> [deployment-name]}"
DEPLOYMENT_NAME="${2:-ownerlens-refund-demo}"

OUTPUTS="$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" --query properties.outputs -o json)"
AGENT_CLIENT_ID="$(jq -r '.agentClientId.value' <<<"$OUTPUTS")"
TENANT_ID="$(jq -r '.tenantId.value' <<<"$OUTPUTS")"
BILLING_SCOPE="$(jq -r '.billingApiScope.value' <<<"$OUTPUTS")"
BILLING_URL="$(jq -r '.billingUrl.value' <<<"$OUTPUTS")"

END_DATE="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) + timedelta(days=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))
PY
)"

SECRET="$(az ad app credential reset \
  --id "$AGENT_CLIENT_ID" \
  --append \
  --display-name "ownerlens-demo-local-agent" \
  --end-date "$END_DATE" \
  --query password -o tsv)"

ENV_FILE="$ROOT_DIR/.env.agent"
{
  printf 'AZURE_TENANT_ID=%q\n' "$TENANT_ID"
  printf 'AGENT_CLIENT_ID=%q\n' "$AGENT_CLIENT_ID"
  printf 'AGENT_CLIENT_SECRET=%q\n' "$SECRET"
  printf 'BILLING_API_SCOPE=%q\n' "$BILLING_SCOPE"
  printf 'BILLING_API_URL=%q\n' "$BILLING_URL"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Created $ENV_FILE (mode 600). Secret expires in 30 days. Do not commit it."
