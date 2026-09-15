import os

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi


def install_entra_openapi(app: FastAPI) -> None:
    def custom_openapi():
        if app.openapi_schema:
            return app.openapi_schema

        schema = get_openapi(
            title=app.title,
            version=app.version,
            description=app.description,
            routes=app.routes,
        )
        tenant_id = os.getenv("ENTRA_TENANT_ID", "{tenant-id}")
        api_scope = os.getenv("API_SCOPE", "api://payment-api/.default")
        schema.setdefault("components", {}).setdefault("securitySchemes", {})["entraOAuth2"] = {
            "type": "oauth2",
            "description": "Microsoft Entra ID app-only OAuth 2.0 client credentials.",
            "flows": {
                "clientCredentials": {
                    "tokenUrl": f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
                    "scopes": {api_scope: "Application permissions Refund.Execute or Charge.Execute"},
                }
            },
        }
        for path, operations in schema.get("paths", {}).items():
            if path.startswith("/api/"):
                for operation in operations.values():
                    if isinstance(operation, dict):
                        operation["security"] = [{"entraOAuth2": [api_scope]}]
        app.openapi_schema = schema
        return app.openapi_schema

    app.openapi = custom_openapi
