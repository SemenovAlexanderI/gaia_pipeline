from __future__ import annotations

import asyncio
from typing import Any, Protocol


class ModelClient(Protocol):
    async def chat_completions(self, payload: dict[str, Any]) -> dict[str, Any]:
        ...


def choice_text(response: dict[str, Any]) -> str:
    choices = response.get("choices") or []
    if not choices:
        return ""

    choice = choices[0]
    if "message" in choice:
        return str(choice.get("message", {}).get("content") or "")
    return str(choice.get("text") or "")


def score_text(text: str) -> tuple[int, int, int]:
    words = {word.strip(".,:;!?()[]{}\"'").lower() for word in text.split()}
    words.discard("")
    return (1 if text.strip() else 0, len(words), len(text))


class Scaffold:
    def __init__(self, model_client: ModelClient, candidates: int) -> None:
        self.model_client = model_client
        self.candidates = candidates

    async def chat_completions(self, payload: dict[str, Any]) -> dict[str, Any]:
        responses = await asyncio.gather(
            *(self.model_client.chat_completions(payload) for _ in range(self.candidates))
        )
        return max(responses, key=lambda response: score_text(choice_text(response)))
