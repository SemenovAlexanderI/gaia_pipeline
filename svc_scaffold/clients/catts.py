from __future__ import annotations

import asyncio
import math
import os
from collections import Counter
from typing import Any

import svc_scaffold.openai_helpers as h


def cluster_action(response: dict) -> str:
    calls = h.tool_calls(response)
    if calls:
        name = calls[0].get("function", {}).get("name", "unknown")
        return name
    content = h.message(response).get("content", "")
    # для финального ответа кластеризуем по первым словам
    return "answer:" + " ".join(content.strip().split()[:5])


def entropy(labels: list[str]) -> float:
    n = len(labels)
    if n == 0:
        return 0.0
    counts = Counter(labels)
    return -sum((c / n) * math.log2(c / n) for c in counts.values())


class CATTSModelClient:
    """
    Wrapper над любым ModelClient.
    Для каждого chat_completions вызова:
      1. Генерирует N сэмплов параллельно
      2. Считает entropy над action clusters
      3. При entropy < threshold → majority vote
      4. При entropy >= threshold → LLM Arbiter
    """

    def __init__(self, base_client, n_samples: int = 3,
                 entropy_threshold: float = 0.9):
        self.base = base_client
        self.n_samples = n_samples
        self.entropy_threshold = entropy_threshold

    async def chat_completions(self, payload: dict[str, Any]) -> dict[str, Any]:
        # Добавляем temperature если не задана
        sampling_payload = dict(payload)
        sampling_payload.setdefault("temperature", 0.7)

        # N параллельных сэмплов
        tasks = [
            self.base.chat_completions(sampling_payload)
            for _ in range(self.n_samples)
        ]
        samples = await asyncio.gather(*tasks, return_exceptions=True)

        # Фильтруем ошибки
        valid = [s for s in samples if isinstance(s, dict)]
        if not valid:
            # fallback: один детерминированный вызов
            return await self.base.chat_completions(payload)

        clusters = [cluster_action(r) for r in valid]
        e = entropy(clusters)

        if e < self.entropy_threshold:
            # Консенсус — берём majority
            best_cluster = Counter(clusters).most_common(1)[0][0]
            winner_idx = clusters.index(best_cluster)
            return valid[winner_idx]
        else:
            # Неопределённость — запускаем Arbiter
            return await self._arbiter(payload, valid, clusters)

    async def _arbiter(self, original_payload: dict,
                       candidates: list[dict],
                       clusters: list[str]) -> dict:
        """
        Arbiter через scoring: задаём модели оценить каждый кандидат
        по шкале 1-10 и берём argmax.
        """
        # Формируем описание каждого кандидата
        candidate_descriptions = []
        for i, r in enumerate(candidates):
            calls = h.tool_calls(r)
            if calls:
                import json
                fn = calls[0].get("function", {})
                desc = f"Action {i+1}: call {fn.get('name')}({fn.get('arguments', '{}')})"
            else:
                content = h.message(r).get("content", "")[:200]
                desc = f"Action {i+1}: respond with '{content}'"
            candidate_descriptions.append(desc)

        # Берём последнее user-сообщение как контекст задачи
        last_user = ""
        for msg in reversed(original_payload.get("messages", [])):
            if isinstance(msg, dict) and msg.get("role") == "user":
                content = msg.get("content", "")
                if isinstance(content, str):
                    last_user = content[:500]
                break

        arbiter_messages = [
            {
                "role": "system",
                "content": (
                    "You are an expert evaluator. "
                    "Given a task context and candidate actions, "
                    "score each action 1-10 for correctness and efficiency. "
                    "Respond ONLY with scores in format: 1:7 2:9 3:4"
                )
            },
            {
                "role": "user",
                "content": (
                    f"Task context: {last_user}\n\n"
                    f"Candidates:\n" + "\n".join(candidate_descriptions) +
                    "\n\nScore each candidate (format: 1:score 2:score ...):"
                )
            }
        ]

        arbiter_payload = {
            "model": original_payload.get("model"),
            "messages": arbiter_messages,
            "temperature": 0,
            "max_tokens": 50,
        }

        try:
            arbiter_resp = await self.base.chat_completions(arbiter_payload)
            score_text = h.message(arbiter_resp).get("content", "")
            scores = self._parse_scores(score_text, len(candidates))
            best_idx = scores.index(max(scores))
            return candidates[best_idx]
        except Exception:
            # Arbiter упал — fallback на majority
            best_cluster = Counter(clusters).most_common(1)[0][0]
            return candidates[clusters.index(best_cluster)]

    @staticmethod
    def _parse_scores(text: str, n: int) -> list[float]:
        """Парсит '1:7 2:9 3:4' → [7.0, 9.0, 4.0]"""
        import re
        scores = [5.0] * n  # дефолт
        for match in re.finditer(r'(\d+)\s*:\s*(\d+(?:\.\d+)?)', text):
            idx = int(match.group(1)) - 1
            score = float(match.group(2))
            if 0 <= idx < n:
                scores[idx] = score
        return scores