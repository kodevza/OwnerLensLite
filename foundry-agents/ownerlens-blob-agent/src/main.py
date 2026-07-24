import asyncio
import json
import os
from datetime import datetime, timezone
from typing import Annotated
from uuid import uuid4

from agent_framework import Agent, tool
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings


STORAGE_ACCOUNT_NAME = os.environ["OWNERLENS_STORAGE_ACCOUNT_NAME"]
RESULTS_CONTAINER = os.environ["OWNERLENS_RESULTS_CONTAINER"]


@tool
def save_ownerlens_result(
    result: Annotated[str, "The final OwnerLens result to persist. Use JSON when possible."],
    blob_name: Annotated[
        str | None,
        "Optional blob name. If omitted, a timestamped name is generated under results/.",
    ] = None,
) -> str:
    """Persist an OwnerLens result to Azure Blob Storage using Entra authentication."""
    credential = DefaultAzureCredential()
    account_url = f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
    blob_service = BlobServiceClient(account_url=account_url, credential=credential)
    container = blob_service.get_container_client(RESULTS_CONTAINER)

    try:
        container.create_container()
    except Exception:
        pass

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    safe_blob_name = blob_name or f"results/{timestamp}-{uuid4().hex}.json"
    if not safe_blob_name.endswith((".json", ".txt", ".md")):
        safe_blob_name = f"{safe_blob_name}.json"

    payload = result
    content_type = "application/json"
    try:
        payload = json.dumps(json.loads(result), indent=2, ensure_ascii=False)
    except json.JSONDecodeError:
        content_type = "text/plain; charset=utf-8"

    blob_client = container.get_blob_client(safe_blob_name)
    blob_client.upload_blob(
        payload.encode("utf-8"),
        overwrite=True,
        content_settings=ContentSettings(content_type=content_type),
    )

    return json.dumps(
        {
            "storage_account": STORAGE_ACCOUNT_NAME,
            "container": RESULTS_CONTAINER,
            "blob_name": safe_blob_name,
            "url": blob_client.url,
        }
    )


async def main() -> None:
    credential = DefaultAzureCredential()
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
    )
    agent = Agent(
        client=client,
        instructions=(
            "You are OwnerLens Blob Writer. Produce concise OwnerLens analysis results "
            "and persist final results to Azure Blob Storage using save_ownerlens_result. "
            "When asked to save data, call the tool and return the blob URL, container, "
            "and blob name. Do not ask for storage keys or connection strings."
        ),
        tools=[save_ownerlens_result],
        default_options={"store": False},
    )
    server = ResponsesHostServer(agent)
    await server.run_async()


if __name__ == "__main__":
    asyncio.run(main())
