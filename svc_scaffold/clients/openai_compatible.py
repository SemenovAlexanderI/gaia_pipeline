from __future__ import annotations

import os
from typing import Any
from urllib.parse import urlparse

import httpx


def local_base_url(base_url: str) -> bool:
    host = urlparse(base_url).hostname
    return host in {"localhost", "127.0.0.1", "0.0.0.0", "::1"}


class OpenAICompatibleModelClient:
    name = "openai_compatible"

    def __init__(self, base_url: str, api_key: str, model: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        default_trust_env = "0" if local_base_url(self.base_url) else "1"
        self.trust_env = os.getenv("MODEL_CLIENT_TRUST_ENV", default_trust_env) == "1"

    def headers(self) -> dict[str, str]:
        if not self.api_key:
            return {}
        return {"Authorization": f"Bearer {self.api_key}"}

    async def health(self) -> None:
        async with httpx.AsyncClient(timeout=10, trust_env=self.trust_env) as client:
            response = await client.get(f"{self.base_url}/models", headers=self.headers())
        response.raise_for_status()

    async def chat_completions(self, payload: dict[str, Any]) -> dict[str, Any]:
        request = dict(payload)
        request["model"] = self.model
        request["stream"] = False

        async with httpx.AsyncClient(timeout=None, trust_env=self.trust_env) as client:
            response = await client.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers(),
                json=request,
            )

        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise UpstreamModelError(exc.response.status_code, response.text) from exc
        return response.json()


class UpstreamModelError(RuntimeError):
    def __init__(self, status_code: int, response_text: str) -> None:
        self.status_code = status_code
        self.response_text = response_text
        super().__init__(f"Upstream model returned {status_code}: {response_text}")
