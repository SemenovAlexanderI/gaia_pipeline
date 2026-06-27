from __future__ import annotations

from typing import Any

from inspect_ai import Task, task
from inspect_ai.agent import Agent
from inspect_ai.solver import Solver
from inspect_ai.util import SandboxEnvironmentType
from inspect_evals.gaia.dataset import gaia_dataset
from inspect_evals.gaia.gaia import (
    DATASET_REVISION,
    DEFAULT_MESSAGE_LIMIT,
    EVAL_VERSION,
    default_solver,
)
from inspect_evals.gaia.scorer import gaia_scorer


def _limit(value: int | None) -> int | None:
    if value is None or value <= 0:
        return None
    return value


def _local_gaia(
    *,
    subset: str | None,
    split: str = "validation",
    input_prompt: str | None = None,
    instance_ids: str | list[str] | None = None,
    max_attempts: int = 1,
    code_timeout: int = 180,
    message_limit: int = DEFAULT_MESSAGE_LIMIT,
    time_limit: int | None = None,
    working_limit: int | None = None,
    token_limit: int | None = None,
    turn_limit: int | None = None,
    solver: Solver | Agent | None = None,
    sandbox: SandboxEnvironmentType = ("docker", "compose.yaml"),
) -> Task:
    dataset = gaia_dataset(
        input_prompt=input_prompt,
        split=split,
        subset=subset,
        revision=DATASET_REVISION,
    )

    if instance_ids:
        if isinstance(instance_ids, str):
            instance_ids = [instance_ids]
        dataset = dataset.filter(lambda x: x.id in instance_ids)

    task_kwargs: dict[str, Any] = {
        "dataset": dataset,
        "solver": solver or default_solver(max_attempts=max_attempts, code_timeout=code_timeout),
        "scorer": gaia_scorer() if split == "validation" else None,
        "sandbox": sandbox,
        "message_limit": message_limit,
        "version": EVAL_VERSION.comparability_version,
        "metadata": EVAL_VERSION.to_metadata(),
    }

    for name, value in {
        "time_limit": time_limit,
        "working_limit": working_limit,
        "token_limit": token_limit,
        "turn_limit": turn_limit,
    }.items():
        limited = _limit(value)
        if limited is not None:
            task_kwargs[name] = limited

    return Task(**task_kwargs)


@task
def gaia(
    split: str = "validation",
    input_prompt: str | None = None,
    instance_ids: str | list[str] | None = None,
    max_attempts: int = 1,
    code_timeout: int = 180,
    message_limit: int = DEFAULT_MESSAGE_LIMIT,
    time_limit: int | None = None,
    working_limit: int | None = None,
    token_limit: int | None = None,
    turn_limit: int | None = None,
    solver: Solver | Agent | None = None,
    sandbox: SandboxEnvironmentType = ("docker", "compose.yaml"),
) -> Task:
    return _local_gaia(
        subset=None,
        split=split,
        input_prompt=input_prompt,
        instance_ids=instance_ids,
        max_attempts=max_attempts,
        code_timeout=code_timeout,
        message_limit=message_limit,
        time_limit=time_limit,
        working_limit=working_limit,
        token_limit=token_limit,
        turn_limit=turn_limit,
        solver=solver,
        sandbox=sandbox,
    )


@task
def gaia_level1(
    split: str = "validation",
    input_prompt: str | None = None,
    instance_ids: str | list[str] | None = None,
    max_attempts: int = 1,
    code_timeout: int = 180,
    message_limit: int = DEFAULT_MESSAGE_LIMIT,
    time_limit: int | None = None,
    working_limit: int | None = None,
    token_limit: int | None = None,
    turn_limit: int | None = None,
    solver: Solver | Agent | None = None,
    sandbox: SandboxEnvironmentType = ("docker", "compose.yaml"),
) -> Task:
    return _local_gaia(
        subset="2023_level1",
        split=split,
        input_prompt=input_prompt,
        instance_ids=instance_ids,
        max_attempts=max_attempts,
        code_timeout=code_timeout,
        message_limit=message_limit,
        time_limit=time_limit,
        working_limit=working_limit,
        token_limit=token_limit,
        turn_limit=turn_limit,
        solver=solver,
        sandbox=sandbox,
    )


@task
def gaia_level2(
    split: str = "validation",
    input_prompt: str | None = None,
    instance_ids: str | list[str] | None = None,
    max_attempts: int = 1,
    code_timeout: int = 180,
    message_limit: int = DEFAULT_MESSAGE_LIMIT,
    time_limit: int | None = None,
    working_limit: int | None = None,
    token_limit: int | None = None,
    turn_limit: int | None = None,
    solver: Solver | Agent | None = None,
    sandbox: SandboxEnvironmentType = ("docker", "compose.yaml"),
) -> Task:
    return _local_gaia(
        subset="2023_level2",
        split=split,
        input_prompt=input_prompt,
        instance_ids=instance_ids,
        max_attempts=max_attempts,
        code_timeout=code_timeout,
        message_limit=message_limit,
        time_limit=time_limit,
        working_limit=working_limit,
        token_limit=token_limit,
        turn_limit=turn_limit,
        solver=solver,
        sandbox=sandbox,
    )


@task
def gaia_level3(
    split: str = "validation",
    input_prompt: str | None = None,
    instance_ids: str | list[str] | None = None,
    max_attempts: int = 1,
    code_timeout: int = 180,
    message_limit: int = DEFAULT_MESSAGE_LIMIT,
    time_limit: int | None = None,
    working_limit: int | None = None,
    token_limit: int | None = None,
    turn_limit: int | None = None,
    solver: Solver | Agent | None = None,
    sandbox: SandboxEnvironmentType = ("docker", "compose.yaml"),
) -> Task:
    return _local_gaia(
        subset="2023_level3",
        split=split,
        input_prompt=input_prompt,
        instance_ids=instance_ids,
        max_attempts=max_attempts,
        code_timeout=code_timeout,
        message_limit=message_limit,
        time_limit=time_limit,
        working_limit=working_limit,
        token_limit=token_limit,
        turn_limit=turn_limit,
        solver=solver,
        sandbox=sandbox,
    )
