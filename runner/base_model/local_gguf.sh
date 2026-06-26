#!/bin/sh
set -eu

if [ -z "${LOCAL_LLAMA_SERVER:-}" ] && [ -n "${LLAMA_SERVER_BIN:-}" ]; then
  LOCAL_LLAMA_SERVER="${LLAMA_SERVER_BIN}"
fi

: "${LOCAL_LLAMA_SERVER:?Set LOCAL_LLAMA_SERVER to the llama-server executable or set LLAMA_SERVER_BIN}"
: "${LOCAL_MODEL_PATH:?Set LOCAL_MODEL_PATH to the local GGUF file}"
: "${BASE_MODEL_NAME:?BASE_MODEL_NAME is required}"
: "${BASE_MODEL_API_KEY:?BASE_MODEL_API_KEY is required}"
: "${PID_FILE:?PID_FILE is required}"
: "${STATE_DIR:?STATE_DIR is required}"

LOCAL_MODEL_HOST="${LOCAL_MODEL_HOST:-127.0.0.1}"
LOCAL_MODEL_PORT="${LOCAL_MODEL_PORT:-18082}"
LOCAL_MODEL_CONTEXT="${LOCAL_MODEL_CONTEXT:-262144}"
LOCAL_MODEL_GPU_LAYERS="${LOCAL_MODEL_GPU_LAYERS:-999}"
LOCAL_MODEL_THREADS="${LOCAL_MODEL_THREADS:-4}"
LOCAL_MODEL_PARALLEL="${LOCAL_MODEL_PARALLEL:-1}"
LOCAL_MODEL_BATCH_SIZE="${LOCAL_MODEL_BATCH_SIZE:-512}"
LOCAL_MODEL_UBATCH_SIZE="${LOCAL_MODEL_UBATCH_SIZE:-128}"
LOCAL_MODEL_START_TIMEOUT="${LOCAL_MODEL_START_TIMEOUT:-900}"

if [ ! -x "${LOCAL_LLAMA_SERVER}" ]; then
  resolved_llama_server="$(command -v "${LOCAL_LLAMA_SERVER}" 2>/dev/null || true)"
  if [ -n "${resolved_llama_server}" ] && [ -x "${resolved_llama_server}" ]; then
    LOCAL_LLAMA_SERVER="${resolved_llama_server}"
    export LOCAL_LLAMA_SERVER
  else
    echo "llama-server is not executable or not found in PATH: ${LOCAL_LLAMA_SERVER}" >&2
    echo "Set LOCAL_LLAMA_SERVER to the full path, for example: /home/user/llama.cpp/build/bin/llama-server" >&2
    exit 1
  fi
fi

if [ ! -f "${LOCAL_MODEL_PATH}" ]; then
  echo "GGUF model not found: ${LOCAL_MODEL_PATH}" >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"

if [ -n "${LOCAL_LLAMA_LIB_DIR:-}" ]; then
  LD_LIBRARY_PATH="${LOCAL_LLAMA_LIB_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  export LD_LIBRARY_PATH
fi

if [ -n "${LOCAL_GGML_BACKEND_PATH:-}" ]; then
  GGML_BACKEND_PATH="${LOCAL_GGML_BACKEND_PATH}"
  export GGML_BACKEND_PATH
fi

echo "Starting local llama-server"
echo "  executable: ${LOCAL_LLAMA_SERVER}"
echo "  model:      ${LOCAL_MODEL_PATH}"
echo "  endpoint:   http://${LOCAL_MODEL_HOST}:${LOCAL_MODEL_PORT}/v1"
echo "  context:    ${LOCAL_MODEL_CONTEXT}"

"${LOCAL_LLAMA_SERVER}" \
  --model "${LOCAL_MODEL_PATH}" \
  --alias "${BASE_MODEL_NAME}" \
  --host "${LOCAL_MODEL_HOST}" \
  --port "${LOCAL_MODEL_PORT}" \
  --api-key "${BASE_MODEL_API_KEY}" \
  --ctx-size "${LOCAL_MODEL_CONTEXT}" \
  --n-gpu-layers "${LOCAL_MODEL_GPU_LAYERS}" \
  --threads "${LOCAL_MODEL_THREADS}" \
  --parallel "${LOCAL_MODEL_PARALLEL}" \
  --batch-size "${LOCAL_MODEL_BATCH_SIZE}" \
  --ubatch-size "${LOCAL_MODEL_UBATCH_SIZE}" \
  --jinja \
  -fit off \
  > "${STATE_DIR}/local_gguf.stdout" \
  2> "${STATE_DIR}/local_gguf.stderr" &
pid=$!
echo "${pid}" >> "${PID_FILE}"

started_at="$(date +%s)"
while ! "${PYTHON_BIN}" - <<'PY'
import os
from urllib.request import Request, urlopen

request = Request(
    f"http://{os.environ['LOCAL_MODEL_HOST']}:{os.environ['LOCAL_MODEL_PORT']}/v1/models"
)
api_key = os.environ.get("BASE_MODEL_API_KEY")
if api_key:
    request.add_header("Authorization", f"Bearer {api_key}")
try:
    urlopen(request, timeout=5).close()
except Exception:
    raise SystemExit(1)
PY
do
  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "llama-server exited during startup. Last log lines:" >&2
    tail -40 "${STATE_DIR}/local_gguf.stderr" >&2 || true
    exit 1
  fi
  now="$(date +%s)"
  if [ $((now - started_at)) -ge "${LOCAL_MODEL_START_TIMEOUT}" ]; then
    echo "llama-server startup timed out after ${LOCAL_MODEL_START_TIMEOUT}s" >&2
    exit 1
  fi
  sleep 5
done

echo "Local llama-server is ready."
