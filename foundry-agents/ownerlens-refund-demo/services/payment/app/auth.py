import base64
import json
import os

from fastapi import Header, HTTPException, status


def require_role(required_role: str):
    def dependency(
        x_ms_client_principal: str | None = Header(default=None, alias="X-MS-CLIENT-PRINCIPAL"),
    ) -> None:
        if os.getenv("AUTH_MODE", "disabled").lower() == "disabled":
            return

        if not x_ms_client_principal:
            raise HTTPException(status_code=401, detail="Missing Easy Auth principal")

        try:
            payload = json.loads(base64.b64decode(x_ms_client_principal).decode("utf-8"))
            claims = payload.get("claims", [])
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=401, detail="Invalid Easy Auth principal") from exc

        roles = {
            claim.get("val")
            for claim in claims
            if claim.get("typ") in {
                "roles",
                "http://schemas.microsoft.com/ws/2008/06/identity/claims/role",
            }
        }
        if required_role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required app role: {required_role}",
            )

    return dependency


def require_refund_execute_role(
    x_ms_client_principal: str | None = Header(default=None, alias="X-MS-CLIENT-PRINCIPAL"),
) -> None:
    return require_role("Refund.Execute")(x_ms_client_principal)


require_charge_execute_role = require_role("Charge.Execute")
