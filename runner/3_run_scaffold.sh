#!/bin/sh
set -aue

"${VENV_PYTHON}" -m uvicorn svc_scaffold.main:app --host "0.0.0.0" --port "19080" & pid=$!
cleanup() { kill "$pid" 2>/dev/null || :; }
trap cleanup EXIT INT TERM

while :; do
  if "${VENV_PYTHON}" - <<'PY'
from urllib.request import urlopen

try:
    with urlopen("http://127.0.0.1:19080/health", timeout=5):
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
