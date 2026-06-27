from __future__ import annotations

import json
import os
from typing import Any

import httpx

MAX_TOKENS_OUT = int(os.getenv("BASE_MODEL_MAX_TOKENS", "8192"))
CTX_LIMIT = int(os.getenv("BASE_MODEL_CONTEXT_LIMIT", "131072"))
CONTEXT_TRUNCATE = os.getenv("BASE_MODEL_CONTEXT_TRUNCATE", "1") == "1"
FAIL_SOFT = os.getenv("BASE_MODEL_FAIL_SOFT", "1") == "1"


def _message_size(message: Any) -> int:
    return len(json.dumps(message, ensure_ascii=False, default=str))


def _truncate_messages(messages: list[Any]) -> list[Any]:
    """Keep system + recent messages when the request would exceed the context budget."""
    if not CONTEXT_TRUNCATE or MAX_TOKENS_OUT <= 0 or CTX_LIMIT <= MAX_TOKENS_OUT:
        return messages

    max_input_chars = (CTX_LIMIT - MAX_TOKENS_OUT) * 3
    if sum(_message_size(message) for message in messages) <= max_input_chars:
        return messages

    kept_end: list[Any] = []
    budget = max_input_chars
    for message in reversed(messages):
        size = _message_size(message)
        if budget - size <= 0:
            break
        kept_end.insert(0, message)
        budget -= size

    if (
        messages
        and isinstance(messages[0], dict)
        and messages[0].get("role") == "system"
        and messages[0] not in kept_end
    ):
        kept_end.insert(0, messages[0])

    return kept_end


def _soft_error_response(model: str, detail: str) -> dict[str, Any]:
    return {
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": f"Error: {detail[:300]}"},
                "finish_reason": "stop",
            }
        ],
        "model": model,
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


class ModelClientHTTPError(RuntimeError):
    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


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
        async with httpx.AsyncClient(timeout=10, trust_env=False) as client:
            response = await client.get(f"{self.base_url}/models", headers=self.headers())
        response.raise_for_status()

    async def chat_completions(self, payload: dict[str, Any]) -> dict[str, Any]:
        request = dict(payload)
        request["model"] = self.model
        request["stream"] = False
        if MAX_TOKENS_OUT > 0:
            request.setdefault("max_tokens", MAX_TOKENS_OUT)
        if isinstance(request.get("messages"), list):
            request["messages"] = _truncate_messages(request["messages"])

        timeout = float(os.getenv("BASE_MODEL_REQUEST_TIMEOUT", "1800"))
        try:
            async with httpx.AsyncClient(timeout=timeout, trust_env=False) as client:
                response = await client.post(
                    f"{self.base_url}/chat/completions",
                    headers=self.headers(),
                    json=request,
                )
        except httpx.TimeoutException as exc:
            raise ModelClientHTTPError(
                504,
                f"Base model request timed out after {timeout:g} seconds",
            ) from exc
        except httpx.RequestError as exc:
            raise ModelClientHTTPError(502, f"Base model connection failed: {exc}") from exc

        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            try:
                detail = response.json().get("error", {}).get("message", response.text)
            except Exception:
                detail = response.text
            if FAIL_SOFT:
                return _soft_error_response(self.model, detail)
            detail = detail[:4000]
            raise ModelClientHTTPError(response.status_code, detail) from exc
        return response.json()
