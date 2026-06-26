#!/bin/sh
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Missing ${ENV_FILE}. Copy .env.example to .env and configure local paths." >&2
  exit 1
fi

load_env() {
  normalized="${TMPDIR:-/tmp}/gaia-local-env.$$"
  tr -d '\r' < "$1" > "${normalized}"
  set -a
  . "${normalized}"
  set +a
  rm -f "${normalized}"
}

load_env "${ENV_FILE}"

STATE_DIR="${REPO_ROOT}/_state/runner"
PID_FILE="${STATE_DIR}/local.pids"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${REPO_ROOT}/_state/cache}"
HF_HOME="${HF_HOME:-${REPO_ROOT}/_state/huggingface}"
INSPECT_LOG_DIR="${INSPECT_LOG_DIR:-${REPO_ROOT}/_state/inspect-logs}"
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-${REPO_ROOT}/playwright-browsers}"

LOCAL_MODEL_HOST="${LOCAL_MODEL_HOST:-127.0.0.1}"
LOCAL_MODEL_PORT="${LOCAL_MODEL_PORT:-18082}"
BASE_MODEL_API_BASE_URL="http://${LOCAL_MODEL_HOST}:${LOCAL_MODEL_PORT}/v1"
BASE_MODEL_API_KEY="${BASE_MODEL_API_KEY:-local}"
BASE_MODEL_NAME="${BASE_MODEL_NAME:-local-gguf}"

SCAFFOLD_PORT="${SCAFFOLD_PORT:-19080}"
SCAFFOLD_API_KEY="${SCAFFOLD_API_KEY:-local}"
SCAFFOLD_MODEL_NAME="${SCAFFOLD_MODEL_NAME:-gaia-scaffold-baseline}"
GAIA_MODEL_BASE_URL="http://127.0.0.1:${SCAFFOLD_PORT}/v1"
GAIA_MODEL_API_KEY="${SCAFFOLD_API_KEY}"
GAIA_MODEL_NAME="${SCAFFOLD_MODEL_NAME}"

GAIA_TASK="${GAIA_TASK:-inspect_evals/gaia_level1}"
GAIA_SPLIT="${GAIA_SPLIT:-validation}"
GAIA_MAX_CONNECTIONS="${GAIA_MAX_CONNECTIONS:-1}"
GAIA_MAX_ATTEMPTS="${GAIA_MAX_ATTEMPTS:-1}"
GAIA_SANDBOX="${GAIA_SANDBOX:-local}"
GAIA_RUN_TIMEOUT="${GAIA_RUN_TIMEOUT:-7200}"

NO_PROXY="localhost,127.0.0.1,0.0.0.0,::1${NO_PROXY:+,${NO_PROXY}}"
no_proxy="${NO_PROXY}"
INSPECT_DISABLE_PROXY=1
HF_HUB_OFFLINE=1
HF_DATASETS_OFFLINE=1
TRANSFORMERS_OFFLINE=1

export REPO_ROOT STATE_DIR PID_FILE XDG_CACHE_HOME HF_HOME INSPECT_LOG_DIR
export PLAYWRIGHT_BROWSERS_PATH LOCAL_MODEL_HOST LOCAL_MODEL_PORT
export BASE_MODEL_API_BASE_URL BASE_MODEL_API_KEY BASE_MODEL_NAME
export SCAFFOLD_PORT SCAFFOLD_API_KEY SCAFFOLD_MODEL_NAME
export GAIA_MODEL_BASE_URL GAIA_MODEL_API_KEY GAIA_MODEL_NAME
export GAIA_TASK GAIA_SPLIT GAIA_MAX_CONNECTIONS GAIA_MAX_ATTEMPTS GAIA_SANDBOX
export NO_PROXY no_proxy INSPECT_DISABLE_PROXY
export HF_HUB_OFFLINE HF_DATASETS_OFFLINE TRANSFORMERS_OFFLINE

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy

if [ -n "${LOCAL_PYTHON:-}" ]; then
  PYTHON_BIN="${LOCAL_PYTHON}"
elif [ -n "${CONDA_PREFIX:-}" ] && [ -x "${CONDA_PREFIX}/bin/python" ]; then
  PYTHON_BIN="${CONDA_PREFIX}/bin/python"
elif [ -x "${REPO_ROOT}/.venv/bin/python" ]; then
  PYTHON_BIN="${REPO_ROOT}/.venv/bin/python"
else
  echo "No Python runtime found. Activate conda, create .venv, or set LOCAL_PYTHON." >&2
  exit 1
fi

if [ ! -x "${PYTHON_BIN}" ]; then
  echo "Python is not executable: ${PYTHON_BIN}" >&2
  exit 1
fi

runtime_bin="$(dirname "${PYTHON_BIN}")"
INSPECT_BIN="${LOCAL_INSPECT_BIN:-${runtime_bin}/inspect}"
TOOL_SUPPORT_BIN="${LOCAL_TOOL_SUPPORT_BIN:-${runtime_bin}/inspect-tool-support}"
PATH="${runtime_bin}:${PATH}"
export PYTHON_BIN INSPECT_BIN TOOL_SUPPORT_BIN PATH

if [ ! -x "${INSPECT_BIN}" ]; then
  echo "Inspect executable not found next to Python: ${INSPECT_BIN}" >&2
  exit 1
fi

if [ ! -x "${TOOL_SUPPORT_BIN}" ]; then
  echo "inspect-tool-support not found: ${TOOL_SUPPORT_BIN}" >&2
  exit 1
fi

"${PYTHON_BIN}" - <<'PY'
required = ("fastapi", "httpx", "inspect_ai", "inspect_evals.gaia", "uvicorn")
missing = []
for module in required:
    try:
        __import__(module)
    except ImportError:
        missing.append(module)
if missing:
    raise SystemExit("Missing Python modules: " + ", ".join(missing))
PY

: "${GAIA_DATASET_DIR:?Set GAIA_DATASET_DIR in .env}"
: "${LOCAL_MODEL_PATH:?Set LOCAL_MODEL_PATH in .env}"
if [ -z "${LOCAL_LLAMA_SERVER:-}" ] && [ -n "${LLAMA_SERVER_BIN:-}" ]; then
  LOCAL_LLAMA_SERVER="${LLAMA_SERVER_BIN}"
fi
: "${LOCAL_LLAMA_SERVER:?Set LOCAL_LLAMA_SERVER in .env}"
export GAIA_DATASET_DIR LOCAL_MODEL_PATH LOCAL_LLAMA_SERVER

if [ ! -d "${GAIA_DATASET_DIR}/2023/${GAIA_SPLIT}" ]; then
  echo "Invalid GAIA dataset: expected ${GAIA_DATASET_DIR}/2023/${GAIA_SPLIT}" >&2
  exit 1
fi

gaia_cache_parent="${XDG_CACHE_HOME}/inspect_evals/gaia_dataset"
gaia_cache_path="${gaia_cache_parent}/GAIA"
mkdir -p "${gaia_cache_parent}"
if [ -L "${gaia_cache_path}" ]; then
  rm -f "${gaia_cache_path}"
elif [ -e "${gaia_cache_path}" ]; then
  echo "Cannot link local GAIA: cache path already exists: ${gaia_cache_path}" >&2
  echo "Move it away or point GAIA_DATASET_DIR to that directory." >&2
  exit 1
fi
ln -s "${GAIA_DATASET_DIR}" "${gaia_cache_path}"

if [ "${GAIA_SANDBOX}" = "local" ]; then
  if ! mkdir -p /shared_files 2>/dev/null || [ ! -w /shared_files ]; then
    echo "/shared_files must exist and be writable for GAIA_SANDBOX=local." >&2
    echo "Run: sudo mkdir -p /shared_files && sudo chown \"$(id -u):$(id -g)\" /shared_files" >&2
    exit 1
  fi
fi

FEATURES="
FEATURE_EXAMPLE
FEATURE_BUDGET_TRACKER
FEATURE_VOI
FEATURE_SELF_CONSISTENCY
FEATURE_SHORT_MAK
FEATURE_ACON
FEATURE_ADAPTIVE_BON
FEATURE_CATTS
FEATURE_BAVT
FEATURE_RANKED_VOTING
FEATURE_PICSAR
FEATURE_MOB
FEATURE_STRUCTURED_NOTES
FEATURE_RESUM
FEATURE_HIAGENT
FEATURE_CONTEXT_COMPACTION
FEATURE_COMPLEXITY_CONSISTENCY
FEATURE_LLM_JUDGE
"

for feature in ${FEATURES}; do
  export "${feature}=0"
done

run_label="baseline"
if [ -n "${GAIA_FEATURE:-}" ]; then
  feature_found=0
  for feature in ${FEATURES}; do
    if [ "${feature}" = "${GAIA_FEATURE}" ]; then
      feature_found=1
      break
    fi
  done
  if [ "${feature_found}" -ne 1 ]; then
    echo "Unknown GAIA_FEATURE: ${GAIA_FEATURE}" >&2
    exit 1
  fi
  export "${GAIA_FEATURE}=1"
  run_label="${GAIA_FEATURE}"
fi

mkdir -p "${STATE_DIR}" "${INSPECT_LOG_DIR}" "${HF_HOME}"
: > "${PID_FILE}"

cleanup() {
  status=$?
  if [ -f "${PID_FILE}" ]; then
    while IFS= read -r pid; do
      [ -n "${pid}" ] || continue
      kill "${pid}" 2>/dev/null || true
    done < "${PID_FILE}"
  fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_model() {
  "${PYTHON_BIN}" - <<'PY'
import os
from urllib.request import Request, urlopen

request = Request(f"{os.environ['BASE_MODEL_API_BASE_URL']}/models")
request.add_header("Authorization", f"Bearer {os.environ['BASE_MODEL_API_KEY']}")
try:
    urlopen(request, timeout=5).close()
except Exception:
    raise SystemExit(1)
PY
}

if check_model 2>/dev/null; then
  echo "Using llama-server already running at ${BASE_MODEL_API_BASE_URL}"
else
  sh "${REPO_ROOT}/runner/base_model/local_gguf.sh"
fi

"${PYTHON_BIN}" -m uvicorn svc_scaffold.main:app \
  --host 127.0.0.1 \
  --port "${SCAFFOLD_PORT}" \
  > "${STATE_DIR}/scaffold.stdout" \
  2> "${STATE_DIR}/scaffold.stderr" &
scaffold_pid=$!
echo "${scaffold_pid}" >> "${PID_FILE}"

scaffold_started_at="$(date +%s)"
while ! "${PYTHON_BIN}" - <<'PY'
import os
from urllib.request import urlopen

try:
    urlopen(f"http://127.0.0.1:{os.environ['SCAFFOLD_PORT']}/health", timeout=5).close()
except Exception:
    raise SystemExit(1)
PY
do
  if ! kill -0 "${scaffold_pid}" 2>/dev/null; then
    echo "Scaffold exited during startup:" >&2
    tail -80 "${STATE_DIR}/scaffold.stderr" >&2 || true
    exit 1
  fi
  now="$(date +%s)"
  if [ $((now - scaffold_started_at)) -ge 120 ]; then
    echo "Scaffold startup timed out" >&2
    exit 1
  fi
  sleep 2
done

echo "Runtime:"
echo "  mode:       ${run_label}"
echo "  python:     ${PYTHON_BIN}"
echo "  inspect:    ${INSPECT_BIN}"
echo "  model:      ${LOCAL_MODEL_PATH}"
echo "  dataset:    ${GAIA_DATASET_DIR}"
echo "  task:       ${GAIA_TASK} (${GAIA_SPLIT})"
echo "  eval logs:  ${INSPECT_LOG_DIR}"

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
if [ -n "${GAIA_MESSAGE_LIMIT:-}" ]; then
  set -- "$@" --message-limit "${GAIA_MESSAGE_LIMIT}"
fi

run_status=0
if [ "${GAIA_RUN_TIMEOUT}" -gt 0 ]; then
  if ! command -v timeout >/dev/null 2>&1; then
    echo "GNU timeout is required when GAIA_RUN_TIMEOUT is non-zero." >&2
    exit 1
  fi
  timeout --signal=TERM --kill-after=60 "${GAIA_RUN_TIMEOUT}" \
    "${INSPECT_BIN}" "$@" \
    > "${STATE_DIR}/inspect.stdout" \
    2> "${STATE_DIR}/inspect.stderr" || run_status=$?
else
  "${INSPECT_BIN}" "$@" \
    > "${STATE_DIR}/inspect.stdout" \
    2> "${STATE_DIR}/inspect.stderr" || run_status=$?
fi

if [ "${run_status}" -eq 0 ]; then
  echo "Inspect finished successfully."
elif [ "${run_status}" -eq 124 ]; then
  echo "Inspect exceeded GAIA_RUN_TIMEOUT=${GAIA_RUN_TIMEOUT}s." >&2
else
  echo "Inspect failed with exit code ${run_status}." >&2
fi

echo "  stdout: ${STATE_DIR}/inspect.stdout"
echo "  stderr: ${STATE_DIR}/inspect.stderr"
echo "  evals:  ${INSPECT_LOG_DIR}"

if [ "${run_status}" -ne 0 ]; then
  echo "Last Inspect stderr lines:" >&2
  tail -40 "${STATE_DIR}/inspect.stderr" >&2 || true
fi

exit "${run_status}"
