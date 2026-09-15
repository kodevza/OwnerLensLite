import os

import httpx
from .models import PaymentChargeRequest, PaymentChargeResult, PaymentRefundRequest, PaymentRefundResult


async def execute_refund(payload: PaymentRefundRequest) -> PaymentRefundResult:
    payment_url = os.getenv("PAYMENT_API_URL")
    payment_scope = os.getenv("PAYMENT_API_SCOPE")
    managed_identity_client_id = os.getenv("BILLING_CALLER_CLIENT_ID")

    # Local demo mode: don't require Azure Managed Identity.
    if not payment_url:
        from uuid import uuid4

        return PaymentRefundResult(
            refund_id=uuid4(),
            status="settled",
            provider_reference=f"sim-local-{uuid4().hex[:12]}",
        )

    if not payment_scope or not managed_identity_client_id:
        raise RuntimeError("PAYMENT_API_SCOPE and BILLING_CALLER_CLIENT_ID are required")

    from azure.identity.aio import ManagedIdentityCredential

    credential = ManagedIdentityCredential(client_id=managed_identity_client_id)
    try:
        token = await credential.get_token(payment_scope)
    finally:
        await credential.close()

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            f"{payment_url.rstrip('/')}/api/v1/refunds/execute",
            json=payload.model_dump(mode="json"),
            headers={"Authorization": f"Bearer {token.token}"},
        )
        response.raise_for_status()
        return PaymentRefundResult.model_validate(response.json())


async def execute_charge(payload: PaymentChargeRequest) -> PaymentChargeResult:
    payment_url = os.getenv("PAYMENT_API_URL")
    payment_scope = os.getenv("PAYMENT_API_SCOPE")
    managed_identity_client_id = os.getenv("BILLING_CALLER_CLIENT_ID")

    if not payment_url:
        from uuid import uuid4

        return PaymentChargeResult(
            charge_id=uuid4(), status="settled", provider_reference=f"sim-local-{uuid4().hex[:12]}"
        )

    if not payment_scope or not managed_identity_client_id:
        raise RuntimeError("PAYMENT_API_SCOPE and BILLING_CALLER_CLIENT_ID are required")

    from azure.identity.aio import ManagedIdentityCredential

    credential = ManagedIdentityCredential(client_id=managed_identity_client_id)
    try:
        token = await credential.get_token(payment_scope)
    finally:
        await credential.close()

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            f"{payment_url.rstrip('/')}/api/v1/charges/execute",
            json=payload.model_dump(mode="json"),
            headers={"Authorization": f"Bearer {token.token}"},
        )
        response.raise_for_status()
        return PaymentChargeResult.model_validate(response.json())
