import importlib.util
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
PAYMENT = ROOT / "services" / "payment"


def test_payment_execute_refund():
    # Isolate the payment app package from billing's same-named `app` package.
    old_modules = {name: module for name, module in sys.modules.items() if name == "app" or name.startswith("app.")}
    for name in list(old_modules):
        sys.modules.pop(name, None)
    sys.path.insert(0, str(PAYMENT))
    os.environ["AUTH_MODE"] = "disabled"
    try:
        from app.main import app

        with TestClient(app) as client:
            response = client.post(
                "/api/v1/refunds/execute",
                json={
                    "adjustment_id": "2fbf40d1-4137-41aa-bb0d-c98f9d7e1482",
                    "account_id": "acc-1",
                    "payment_reference": "pay-1",
                    "amount": "49.90",
                    "currency": "PLN",
                    "reason": "Campaign goodwill",
                },
            )
        assert response.status_code == 201, response.text
        assert response.json()["status"] == "settled"
    finally:
        sys.path.remove(str(PAYMENT))
        for name in list(sys.modules):
            if name == "app" or name.startswith("app."):
                sys.modules.pop(name, None)
        sys.modules.update(old_modules)


def test_payment_execute_charge():
    old_modules = {name: module for name, module in sys.modules.items() if name == "app" or name.startswith("app.")}
    for name in list(old_modules):
        sys.modules.pop(name, None)
    sys.path.insert(0, str(PAYMENT))
    os.environ["AUTH_MODE"] = "disabled"
    try:
        from app.main import app

        with TestClient(app) as client:
            response = client.post(
                "/api/v1/charges/execute",
                json={
                    "bdr_id": "2fbf40d1-4137-41aa-bb0d-c98f9d7e1482",
                    "account_id": "acc-1",
                    "payment_reference": "pay-2",
                    "amount": "49.90",
                    "currency": "PLN",
                    "reason": "Monthly subscription charge",
                },
            )
        assert response.status_code == 201, response.text
        assert response.json()["status"] == "settled"
    finally:
        sys.path.remove(str(PAYMENT))
        for name in list(sys.modules):
            if name == "app" or name.startswith("app."):
                sys.modules.pop(name, None)
        sys.modules.update(old_modules)
