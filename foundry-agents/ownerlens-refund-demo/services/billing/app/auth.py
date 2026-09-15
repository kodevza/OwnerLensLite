import base64
import json
import os
from dataclasses import dataclass

from fastapi import Header, HTTPException, status


@dataclass(frozen=True)
class Caller:
    object_id: str | None
    client_id: str | None
    roles: tuple[str, ...]


def _decode_client_principal(header: str) -> Caller:
    try:
        raw = base64.b64decode(header).decode("utf-8")
        payload = json.loads(raw)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Easy Auth principal header",
        ) from exc

    claims = payload.get("claims", [])
    roles: list[str] = []
    object_id = None
    client_id = None

    oid_types = {
        "oid",
        "http://schemas.microsoft.com/identity/claims/objectidentifier",
    }
    appid_types = {
        "appid",
        "azp",
        "http://schemas.microsoft.com/identity/claims/applicationid",
    }

    for claim in claims:
        typ = claim.get("typ")
        val = claim.get("val")
        if typ in {"roles", "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"}:
            roles.append(val)
        elif typ in oid_types:
            object_id = val
        elif typ in appid_types:
            client_id = val

    return Caller(object_id=object_id, client_id=client_id, roles=tuple(roles))


def require_role(required_role: str):
    def dependency(
        x_ms_client_principal: str | None = Header(default=None, alias="X-MS-CLIENT-PRINCIPAL"),
    ) -> Caller:
        # Local mode is deliberately explicit. Azure is configured with AUTH_MODE=easyauth.
        if os.getenv("AUTH_MODE", "disabled").lower() == "disabled":
            return Caller(object_id="local-dev", client_id="local-dev", roles=(required_role,))

        if not x_ms_client_principal:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing Easy Auth principal",
            )

        caller = _decode_client_principal(x_ms_client_principal)
        if required_role not in caller.roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required app role: {required_role}",
            )
        return caller

    return dependency


def require_refund_request_role(
    x_ms_client_principal: str | None = Header(default=None, alias="X-MS-CLIENT-PRINCIPAL"),
) -> Caller:
    return require_role("Refund.Request")(x_ms_client_principal)


require_bdr_create_role = require_role("Charge.Request")
