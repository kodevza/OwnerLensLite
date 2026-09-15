#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCE_GROUP="${1:-rg-ownerlens-refund-demo}"
LOCATION="${2:-westeurope}"
PREFIX="${3:-olrefund}"
DEPLOYMENT_NAME="ownerlens-refund-demo"

for cmd in az jq zip python3; do
  command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

az account show >/dev/null
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none

PAYMENT_OWNER_OBJECT_ID="${PAYMENT_OWNER_OBJECT_ID:-$(az ad signed-in-user show --query id -o tsv)}"
if [[ -z "$PAYMENT_OWNER_OBJECT_ID" ]]; then
  echo "Could not resolve payment owner. Export PAYMENT_OWNER_OBJECT_ID=<Entra object id>." >&2
  exit 1
fi

echo "Deploying Azure + Entra resources; Payment owner object id: $PAYMENT_OWNER_OBJECT_ID"
set +e
az deployment group create \
  -g "$RESOURCE_GROUP" \
  -n "$DEPLOYMENT_NAME" \
  -f "$ROOT_DIR/infra/main.bicep" \
  -p prefix="$PREFIX" location="$LOCATION" paymentOwnerObjectId="$PAYMENT_OWNER_OBJECT_ID" \
  -o none
DEPLOY_RC=$?
set -e

# Graph/managed-identity objects can be briefly eventually consistent. A second idempotent
# deployment resolves that without manual intervention.
if [[ $DEPLOY_RC -ne 0 ]]; then
  echo "Initial deployment hit a dependency/replication failure; retrying once..."
  sleep 10
  az deployment group create \
    -g "$RESOURCE_GROUP" \
    -n "$DEPLOYMENT_NAME" \
    -f "$ROOT_DIR/infra/main.bicep" \
    -p prefix="$PREFIX" location="$LOCATION" paymentOwnerObjectId="$PAYMENT_OWNER_OBJECT_ID" \
    -o none
fi

OUTPUTS="$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" --query properties.outputs -o json)"
BILLING_APP="$(jq -r '.billingFunctionName.value' <<<"$OUTPUTS")"
PAYMENT_APP="$(jq -r '.paymentFunctionName.value' <<<"$OUTPUTS")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

package_service() {
  local service="$1"
  local out="$2"
  (cd "$ROOT_DIR/services/$service" && zip -qr "$out" . -x 'local.settings.json' 'local.settings.sample.json' '__pycache__/*' '*.pyc')
}

package_service billing "$TMP_DIR/billing.zip"
package_service payment "$TMP_DIR/payment.zip"

# Current Flex Consumption CLI routes this command through the supported deployment path.
az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$BILLING_APP" --src "$TMP_DIR/billing.zip" --build-remote true -o none
az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$PAYMENT_APP" --src "$TMP_DIR/payment.zip" --build-remote true -o none

"$ROOT_DIR/scripts/bootstrap-agent-secret.sh" "$RESOURCE_GROUP" "$DEPLOYMENT_NAME"

jq -r '"Billing Swagger: " + .billingDocsUrl.value + "\nPayment Swagger: " + .paymentDocsUrl.value + "\nBilling API: " + .billingUrl.value + "\nPayment API: " + .paymentUrl.value' <<<"$OUTPUTS"
echo
echo "Run demo:"
echo "  set -a; source '$ROOT_DIR/.env.agent'; set +a"
echo "  python3 -m pip install -r '$ROOT_DIR/agent/requirements.txt'"
echo "  python3 '$ROOT_DIR/agent/client.py'"
