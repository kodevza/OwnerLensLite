import os
import tempfile
import time
import zipfile
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AgentEndpointConfig,
    CodeConfiguration,
    CodeDependencyResolution,
    FixedRatioVersionSelectionRule,
    HostedAgentDefinition,
    ProtocolConfiguration,
    ProtocolVersionRecord,
    ResponsesProtocolConfiguration,
    VersionSelector,
)
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv


load_dotenv()

PROJECT_ENDPOINT = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
MODEL_DEPLOYMENT = os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"]
AGENT_NAME = os.environ["FOUNDRY_HOSTED_AGENT_NAME"]
STORAGE_ACCOUNT_NAME = os.environ["OWNERLENS_STORAGE_ACCOUNT_NAME"]
RESULTS_CONTAINER = os.environ["OWNERLENS_RESULTS_CONTAINER"]
SOURCE_DIR = Path(__file__).parent / "src"


def create_code_zip(source_dir: Path) -> Path:
    zip_path = Path(tempfile.gettempdir()) / f"{AGENT_NAME}.zip"
    excluded_parts = {".git", ".venv", "__pycache__", ".env"}
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zip_file:
        for path in source_dir.rglob("*"):
            if not path.is_file():
                continue
            if any(part in excluded_parts for part in path.parts):
                continue
            zip_file.write(path, path.relative_to(source_dir))
    return zip_path


def wait_for_active_version(project_client: AIProjectClient, version: str) -> None:
    for attempt in range(60):
        details = project_client.agents.get_version(
            agent_name=AGENT_NAME,
            agent_version=version,
        )
        status = details["status"]
        print(f"Provisioning status: {status} (attempt {attempt + 1}/60)")
        if status == "active":
            return
        if status == "failed":
            raise RuntimeError(f"Hosted agent provisioning failed: {dict(details)}")
        time.sleep(10)
    raise RuntimeError("Timed out waiting for the hosted agent version to become active.")


def main() -> None:
    code_zip_path = create_code_zip(SOURCE_DIR)
    with (
        code_zip_path.open("rb") as code_stream,
        DefaultAzureCredential() as credential,
        AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential) as project_client,
    ):
        created = project_client.agents.create_version_from_code(
            agent_name=AGENT_NAME,
            description="Hosted OwnerLens agent that writes final results to Azure Blob Storage with Entra auth.",
            definition=HostedAgentDefinition(
                cpu="1",
                memory="2Gi",
                code_configuration=CodeConfiguration(
                    runtime="python_3_13",
                    entry_point=["python", "main.py"],
                    dependency_resolution=CodeDependencyResolution.REMOTE_BUILD,
                ),
                environment_variables={
                    "FOUNDRY_PROJECT_ENDPOINT": PROJECT_ENDPOINT,
                    "AZURE_AI_MODEL_DEPLOYMENT_NAME": MODEL_DEPLOYMENT,
                    "OWNERLENS_STORAGE_ACCOUNT_NAME": STORAGE_ACCOUNT_NAME,
                    "OWNERLENS_RESULTS_CONTAINER": RESULTS_CONTAINER,
                },
                protocol_versions=[
                    ProtocolVersionRecord(protocol="responses", version="2.0.0")
                ],
            ),
            code=code_stream,
        )
        print(f"Created hosted agent version {created.version}")
        wait_for_active_version(project_client, created.version)

        project_client.agents.update_details(
            agent_name=AGENT_NAME,
            agent_endpoint=AgentEndpointConfig(
                version_selector=VersionSelector(
                    version_selection_rules=[
                        FixedRatioVersionSelectionRule(
                            agent_version=created.version,
                            traffic_percentage=100,
                        )
                    ]
                ),
                protocol_configuration=ProtocolConfiguration(
                    responses=ResponsesProtocolConfiguration()
                ),
            ),
        )
        details = project_client.agents.get(agent_name=AGENT_NAME)
        print(
            {
                "name": details["name"],
                "version": created.version,
                "status": created["status"],
                "agent_endpoint": details["agent_endpoint"],
            }
        )


if __name__ == "__main__":
    main()
