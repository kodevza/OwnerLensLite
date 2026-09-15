import json
import os
import sys
from decimal import Decimal

import httpx
from azure.identity import ClientSecretCredential


def required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise SystemExit(f"Missing environment variable: {name}")
    return value


def main() -> None:
    tenant_id = required("AZURE_TENANT_ID")
    client_id = required("AGENT_CLIENT_ID")
    client_secret = required("AGENT_CLIENT_SECRET")
    billing_scope = required("BILLING_API_SCOPE")
    billing_url = required("BILLING_API_URL")

    credential = ClientSecretCredential(
        tenant_id=tenant_id,
        client_id=client_id,
        client_secret=client_secret,
    )
    token = credential.get_token(billing_scope)

    payload = {
        "account_id": "acc-100042",
        "amount": "49.90",
        "currency": "PLN",
        "reason": "Summer 2026 campaign refund requested by chatbot",
        "campaign_id": "SUMMER-2026",
        "payment_reference": "pay_20260907_001",
    }

    with httpx.Client(timeout=15.0) as client:
        response = client.post(
            f"{billing_url.rstrip('/')}/api/v1/refunds",
            json=payload,
            headers={"Authorization": f"Bearer {token.token}"},
        )

    print(f"HTTP {response.status_code}")
    try:
        print(json.dumps(response.json(), indent=2))
    except Exception:  # noqa: BLE001
        print(response.text)

    if response.is_error:
        sys.exit(1)


if __name__ == "__main__":
    main()
