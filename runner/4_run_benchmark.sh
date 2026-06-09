#!/bin/sh
set -aue

GAIA_MODEL_BASE_URL="${SCAFFOLD_MODEL_API_BASE_URL}"
GAIA_MODEL_API_KEY="dummy"

trap 'touch "${REPO_ROOT}/_state/runner/${RUN_TASK_NAME}.ready"' EXIT

"${REPO_ROOT}/_state/.venv/bin/inspect" eval "${GAIA_TASK}" \
  --model "openai-api/gaia_model/${SCAFFOLD_MODEL_NAME}" \
  --sandbox "${GAIA_SANDBOX}" \
  --limit "${GAIA_SAMPLE_START}-${GAIA_SAMPLE_END}" \
  --max-connections "${GAIA_MAX_CONNECTIONS}" \
  --max-samples "${GAIA_MAX_SAMPLES}" \
  -T "split=${GAIA_SPLIT}" \
  -T "max_attempts=${GAIA_MAX_ATTEMPTS}"
