from __future__ import annotations

from typing import Any

import httpx


class OpenAICompatibleModelClient:
    name = "openai_compatible"

    def __init__(self, base_url: str, api_key: str, model: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model

    def headers(self) -> dict[str, str]:
        if not self.api_key:
            return {}
        return {"Authorization": f"Bearer {self.api_key}"}

    async def health(self) -> None:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{self.base_url}/models", headers=self.headers())
        response.raise_for_status()

    async def chat_completions(self, payload: dict[str, Any]) -> dict[str, Any]:
        request = dict(payload)
        request["model"] = self.model
        request["stream"] = False

        async with httpx.AsyncClient(timeout=None) as client:
            response = await client.post(
                f"{self.base_url}/chat/completions",
                headers=self.headers(),
                json=request,
            )

        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise RuntimeError(f"{exc}; response={response.text}") from exc
        return response.json()
