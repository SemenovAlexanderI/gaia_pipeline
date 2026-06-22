#!/bin/sh
set -aue

# Local Linux runner. Unlike llama16GB.sh, it neither downloads llama.cpp nor
# assumes a particular CUDA toolkit: it uses the llama-server already in PATH.
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-llama-server}"
LOCAL_MODEL_PATH="${LOCAL_MODEL_PATH:-/home/user/models/Qwen3.5-9B-Q4_K_M.gguf}"
LLAMA_SERVER_HOST="${LLAMA_SERVER_HOST:-127.0.0.1}"
LLAMA_SERVER_PORT="${LLAMA_SERVER_PORT:-18082}"
LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-32768}"
LLAMA_PARALLEL="${LLAMA_PARALLEL:-1}"
LLAMA_THREADS="${LLAMA_THREADS:-4}"
BASE_MODEL_API_BASE_URL="http://127.0.0.1:${LLAMA_SERVER_PORT}/v1"

if ! command -v "${LLAMA_SERVER_BIN}" >/dev/null 2>&1; then
  echo "llama-server was not found: ${LLAMA_SERVER_BIN}" >&2
  echo "Set LLAMA_SERVER_BIN to the full path of your llama-server binary." >&2
  exit 1
fi

if [ ! -f "${LOCAL_MODEL_PATH}" ]; then
  echo "GGUF model was not found: ${LOCAL_MODEL_PATH}" >&2
  echo "Set LOCAL_MODEL_PATH in .env to the downloaded Qwen3.5 GGUF file." >&2
  exit 1
fi

LOG_STDOUT="${REPO_ROOT}/_state/runner/${BASE_MODEL_RUNNER_TYPE}.stdout"
LOG_STDERR="${REPO_ROOT}/_state/runner/${BASE_MODEL_RUNNER_TYPE}.stderr"

"${LLAMA_SERVER_BIN}" \
  --model "${LOCAL_MODEL_PATH}" \
  --alias "${BASE_MODEL_NAME}" \
  --host "${LLAMA_SERVER_HOST}" \
  --port "${LLAMA_SERVER_PORT}" \
  --api-key "${BASE_MODEL_API_KEY}" \
  --ctx-size "${LLAMA_CTX_SIZE}" \
  --n-gpu-layers "999" \
  --threads "${LLAMA_THREADS}" \
  --parallel "${LLAMA_PARALLEL}" \
  --batch-size "512" \
  --ubatch-size "128" \
  --jinja \
  > "${LOG_STDOUT}" \
  2> "${LOG_STDERR}" & pid=$!
echo "${pid}" >> "${PID_FILE}"

check_service() {
  "${VENV_PYTHON}" - <<'PY'
import os
from urllib.request import Request, urlopen

request = Request(f"{os.environ['BASE_MODEL_API_BASE_URL']}/models")
api_key = os.environ.get("BASE_MODEL_API_KEY")
if api_key:
    request.add_header("Authorization", f"Bearer {api_key}")
try:
    urlopen(request, timeout=5).close()
except Exception:
    raise SystemExit(1)
PY
}

echo "Starting ${LLAMA_SERVER_BIN} with ${LOCAL_MODEL_PATH}"
echo "llama-server log: ${LOG_STDERR}"

while ! check_service; do
  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "llama-server exited before becoming healthy. Last log lines:" >&2
    tail -n 80 "${LOG_STDERR}" >&2 || :
    wait "${pid}" || exit $?
    exit 1
  fi
  sleep 2
done

echo "llama-server is ready at ${BASE_MODEL_API_BASE_URL}"
