import json
import os

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv


load_dotenv()


def main() -> None:
    agent_name = os.environ["FOUNDRY_HOSTED_AGENT_NAME"]
    smoke_blob_name = os.environ["OWNERLENS_SMOKE_BLOB_NAME"]
    with (
        DefaultAzureCredential() as credential,
        AIProjectClient(
            endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
            credential=credential,
        ) as project_client,
    ):
        with project_client.get_openai_client(agent_name=agent_name) as openai_client:
            response = openai_client.responses.create(
                input=(
                    "Save the test OwnerLens result to blob_name "
                    f"'{smoke_blob_name}'. JSON result: "
                    '{"status":"ok","source":"foundry-hosted-agent-smoke"}'
                )
            )
            print(response.output_text)


if __name__ == "__main__":
    main()
