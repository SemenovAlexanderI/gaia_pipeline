# from __future__ import annotations

# import os

# from svc_scaffold.api.openai_compatible import create_app as create_openai_compatible_app
# from svc_scaffold.clients.openai_compatible import OpenAICompatibleModelClient
# from svc_scaffold.core import Scaffold


# model_client = OpenAICompatibleModelClient(
#     os.environ["BASE_MODEL_API_BASE_URL"],
#     os.environ["BASE_MODEL_API_KEY"],
#     os.environ["BASE_MODEL_NAME"],
# )
# scaffold = Scaffold(model_client)

# app = create_openai_compatible_app(scaffold, model_client)

# main.py
import os
from svc_scaffold.clients.openai_compatible import OpenAICompatibleClient
from svc_scaffold.clients.catts import CATTSModelClient
from svc_scaffold.core import Scaffold

def build_scaffold() -> Scaffold:
    base_client = OpenAICompatibleClient(
        base_url=os.environ["BASE_MODEL_BASE_URL"],
        api_key=os.environ.get("BASE_MODEL_API_KEY", ""),
        model=os.environ["BASE_MODEL_NAME"],
    )

    if os.getenv("CATTS_ENABLED") == "1":
        client = CATTSModelClient(
            base_client,
            n_samples=int(os.getenv("CATTS_N_SAMPLES", "3")),
            entropy_threshold=float(os.getenv("CATTS_ENTROPY_THRESHOLD", "0.9")),
        )
    else:
        client = base_client

    return Scaffold(client)