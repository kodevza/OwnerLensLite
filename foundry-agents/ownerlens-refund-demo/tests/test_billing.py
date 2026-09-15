import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
BILLING = ROOT / "services" / "billing"
sys.path.insert(0, str(BILLING))
os.environ["AUTH_MODE"] = "disabled"

from app.main import app  # noqa: E402


def test_refund_creates_negative_adjustment_and_payment_result():
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/refunds",
            json={
                "account_id": "acc-1",
                "amount": "49.90",
                "currency": "pln",
                "reason": "Campaign goodwill",
                "campaign_id": "CMP-1",
                "payment_reference": "pay-1",
            },
        )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["adjustment"]["amount"] == "-49.90"
    assert body["adjustment"]["currency"] == "PLN"
    assert body["adjustment"]["status"] == "refund_submitted"
    assert body["payment"]["status"] == "settled"


def test_bdr_creates_a_charge_and_payment_result():
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/bdrs",
            json={
                "account_id": "acc-1",
                "amount": "49.90",
                "currency": "pln",
                "reason": "Monthly subscription charge",
                "payment_reference": "pay-2",
            },
        )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["bdr"]["amount"] == "49.90"
    assert body["bdr"]["currency"] == "PLN"
    assert body["bdr"]["status"] == "charge_submitted"
    assert body["payment"]["status"] == "settled"


def test_billing_package_includes_async_managed_identity_transport():
    requirements = (BILLING / "requirements.txt").read_text().lower()
    assert "aiohttp" in requirements


def test_agent_secret_bootstrap_writes_shell_safe_environment_values():
    bootstrap = (ROOT / "scripts" / "bootstrap-agent-secret.sh").read_text()
    assert "%q" in bootstrap
