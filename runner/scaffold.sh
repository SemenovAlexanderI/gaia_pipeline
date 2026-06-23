#!/bin/sh
set -aue

pkill -f '[u]vicorn svc_scaffold.main:app' 2>/dev/null && sleep 2

"${VENV_PYTHON}" -m uvicorn svc_scaffold.main:app --host "0.0.0.0" --port "${SCAFFOLD_PORT}" \
  > "${REPO_ROOT}/_state/runner/scaffold.stdout" \
  2> "${REPO_ROOT}/_state/runner/scaffold.stderr" & pid=$!
echo "${pid}" >> "${PID_FILE}"
LOG_STDERR="${REPO_ROOT}/_state/runner/scaffold.stderr"

check_service() {
  "${VENV_PYTHON}" - <<'PY'
import os
from urllib.request import urlopen

try:
    urlopen(f"http://127.0.0.1:{os.environ['SCAFFOLD_PORT']}/health", timeout=5).close()
except Exception:
    raise SystemExit(1)
PY
}

while ! check_service; do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "scaffold exited before becoming healthy. Last log lines:" >&2
    tail -n 80 "${LOG_STDERR}" >&2 || :
    wait "$pid" || exit $?
    exit 1
  fi
  sleep 5
done
