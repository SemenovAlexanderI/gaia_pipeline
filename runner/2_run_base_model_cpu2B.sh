#!/bin/sh
set -aue

"${VENV_PYTHON}" -m pip install "llama-cpp-python[server]" "huggingface-hub"

"${VENV_PYTHON}" -m llama_cpp.server \
  --hf_model_repo_id "unsloth/Qwen3.5-2B-GGUF" \
  --model "*Q4_K_M*.gguf" \
  --model_alias "${MODEL_NAME}" \
  --host "0.0.0.0" \
  --port "18080" \
  --n_gpu_layers 0 \
  --n_ctx "4096" \
  --n_threads "4" \
  --chat_format chatml & pid=$!
cleanup() { kill "$pid" 2>/dev/null || :; }
trap cleanup EXIT INT TERM

while :; do
  if "${VENV_PYTHON}" - <<'PY'
from urllib.request import urlopen

try:
    with urlopen("http://127.0.0.1:18080/v1/models", timeout=5):
        pass
except Exception:
    raise SystemExit(1)
PY
  then
    touch "${REPO_ROOT}/_state/runner/${RUN_TASK_NAME}.ready"
    break
  fi
  kill -0 "$pid" 2>/dev/null || wait "$pid"
  sleep 5
done

wait "$pid"
