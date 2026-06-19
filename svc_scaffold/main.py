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
from __future__ import annotations

import os

from svc_scaffold.api.openai_compatible import create_app as create_openai_compatible_app
from svc_scaffold.clients.openai_compatible import OpenAICompatibleModelClient
from svc_scaffold.core import Scaffold


base_model_client = OpenAICompatibleModelClient(
    os.environ["BASE_MODEL_API_BASE_URL"],
    os.environ["BASE_MODEL_API_KEY"],
    os.environ["BASE_MODEL_NAME"],
)

if os.getenv("CATTS_ENABLED") == "1":
    from svc_scaffold.clients.catts import CATTSModelClient
    model_client = CATTSModelClient(
        base_model_client,
        n_samples=int(os.getenv("CATTS_N_SAMPLES", "3")),
        entropy_threshold=float(os.getenv("CATTS_ENTROPY_THRESHOLD", "0.9")),
    )
else:
    model_client = base_model_client

scaffold = Scaffold(model_client)
app = create_openai_compatible_app(scaffold, model_client)