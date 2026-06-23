#!/bin/sh
set -aue

pkill -f '[i]nspect eval' 2>/dev/null && sleep 2

if [ "${INSPECT_DISABLE_PROXY:-1}" = "1" ]; then
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy OPENAI_PROXY
fi

set -- eval "${GAIA_TASK}" \
  --model "openai-api/gaia_model/${SCAFFOLD_MODEL_NAME}" \
  --sandbox "${GAIA_SANDBOX}" \
  --max-connections "${GAIA_MAX_CONNECTIONS}" \
  -T "split=${GAIA_SPLIT}" \
  -T "max_attempts=${GAIA_MAX_ATTEMPTS}"

if [ -n "${GAIA_SAMPLE_START:-}" ] && [ -n "${GAIA_SAMPLE_END:-}" ]; then
  set -- "$@" --limit "${GAIA_SAMPLE_START}-${GAIA_SAMPLE_END}"
fi

if [ -n "${GAIA_MAX_SAMPLES:-}" ]; then
  set -- "$@" --max-samples "${GAIA_MAX_SAMPLES}"
fi

"${INSPECT_BIN:-${REPO_ROOT}/.venv/bin/inspect}" "$@"
