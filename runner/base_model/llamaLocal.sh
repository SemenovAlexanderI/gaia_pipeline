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
LLAMA_N_GPU_LAYERS="${LLAMA_N_GPU_LAYERS:-999}"
LLAMA_BATCH_SIZE="${LLAMA_BATCH_SIZE:-512}"
LLAMA_UBATCH_SIZE="${LLAMA_UBATCH_SIZE:-128}"
LLAMA_JINJA="${LLAMA_JINJA:-auto}"
BASE_MODEL_API_BASE_URL="http://127.0.0.1:${LLAMA_SERVER_PORT}/v1"

if ! command -v "${LLAMA_SERVER_BIN}" >/dev/null 2>&1; then
  echo "llama-server was not found: ${LLAMA_SERVER_BIN}" >&2
  echo "Set LLAMA_SERVER_BIN before running localModelU.sh or edit runner/localModelU.sh." >&2
  exit 1
fi

if [ ! -f "${LOCAL_MODEL_PATH}" ]; then
  echo "GGUF model was not found: ${LOCAL_MODEL_PATH}" >&2
  echo "Set LOCAL_MODEL_PATH before running localModelU.sh or edit runner/localModelU.sh." >&2
  exit 1
fi

LOG_STDOUT="${REPO_ROOT}/_state/runner/${BASE_MODEL_RUNNER_TYPE}.stdout"
LOG_STDERR="${REPO_ROOT}/_state/runner/${BASE_MODEL_RUNNER_TYPE}.stderr"

check_service() {
  if [ -n "${BASE_MODEL_API_KEY}" ]; then
    curl --noproxy '*' --fail --silent --show-error \
      --max-time 5 \
      --header "Authorization: Bearer ${BASE_MODEL_API_KEY}" \
      "${BASE_MODEL_API_BASE_URL}/models" >/dev/null
  else
    curl --noproxy '*' --fail --silent --show-error \
      --max-time 5 \
      "${BASE_MODEL_API_BASE_URL}/models" >/dev/null
  fi
}

port_in_use() {
  "${VENV_PYTHON}" - <<PY
import socket

with socket.socket() as sock:
    sock.settimeout(0.5)
    raise SystemExit(0 if sock.connect_ex(("127.0.0.1", int("${LLAMA_SERVER_PORT}"))) == 0 else 1)
PY
}

if port_in_use; then
  if check_service && [ "${LLAMA_USE_EXISTING_SERVER:-0}" = "1" ]; then
    echo "Using existing llama-server at ${BASE_MODEL_API_BASE_URL}"
    exit 0
  fi
  echo "Port ${LLAMA_SERVER_PORT} is already in use." >&2
  echo "Stop the existing process, choose another LLAMA_SERVER_PORT, or set LLAMA_USE_EXISTING_SERVER=1 if it is the intended llama-server." >&2
  exit 1
fi

if [ "${LLAMA_JINJA}" = "auto" ]; then
  if "${LLAMA_SERVER_BIN}" --help 2>&1 | grep -q -- '--jinja'; then
    LLAMA_JINJA=1
  else
    LLAMA_JINJA=0
  fi
fi

set -- "${LLAMA_SERVER_BIN}" \
  --model "${LOCAL_MODEL_PATH}" \
  --alias "${BASE_MODEL_NAME}" \
  --host "${LLAMA_SERVER_HOST}" \
  --port "${LLAMA_SERVER_PORT}" \
  --api-key "${BASE_MODEL_API_KEY}" \
  --ctx-size "${LLAMA_CTX_SIZE}" \
  --n-gpu-layers "${LLAMA_N_GPU_LAYERS}" \
  --threads "${LLAMA_THREADS}" \
  --parallel "${LLAMA_PARALLEL}" \
  --batch-size "${LLAMA_BATCH_SIZE}" \
  --ubatch-size "${LLAMA_UBATCH_SIZE}"

if [ "${LLAMA_JINJA}" = "1" ]; then
  set -- "$@" --jinja
fi

echo "Starting ${LLAMA_SERVER_BIN} with ${LOCAL_MODEL_PATH}"
echo "llama-server log: ${LOG_STDERR}"

"$@" > "${LOG_STDOUT}" 2> "${LOG_STDERR}" & pid=$!
echo "${pid}" >> "${PID_FILE}"

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
