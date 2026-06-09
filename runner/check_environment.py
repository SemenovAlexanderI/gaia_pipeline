from importlib.metadata import version
from shutil import which

import fastapi  # noqa: F401
import httpx  # noqa: F401
import inspect_ai  # noqa: F401
import inspect_evals.gaia  # noqa: F401
import openai  # noqa: F401
import playwright  # noqa: F401
import uvicorn  # noqa: F401

print(f"inspect-ai={version('inspect-ai')}")
print(f"inspect-evals={version('inspect-evals')}")

if which("inspect-tool-support") is None:
    raise RuntimeError("inspect-tool-support executable is not available on PATH")
