#!/bin/sh
set -aue

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/.env"

VENV_PYTHON="${REPO_ROOT}/_state/.venv/bin/python"
HF_HOME="${REPO_ROOT}/_state/huggingface"
INSPECT_LOG_DIR="${REPO_ROOT}/_state/inspect-logs"
PLAYWRIGHT_BROWSERS_PATH="${REPO_ROOT}/_state/playwright-browsers"
PATH="${REPO_ROOT}/_state/.venv/bin:${PATH}"

mkdir -p \
  "${HF_HOME}" \
  "${INSPECT_LOG_DIR}" \
  "${PLAYWRIGHT_BROWSERS_PATH}" \
  "${REPO_ROOT}/_state/runner"
rm -rf "${REPO_ROOT}/_state/runner"/*

create_venv() {
  if "${VENV_PYTHON}" -m pip --version >/dev/null 2>&1; then
    return
  fi

  if "${PYTHON_BIN:-python3}" -m venv "${REPO_ROOT}/_state/.venv"; then
    return
  fi

  rm -rf "${REPO_ROOT}/_state/.venv"
  "${PYTHON_BIN:-python3}" -m venv --system-site-packages --without-pip "${REPO_ROOT}/_state/.venv"
  "${VENV_PYTHON}" -m pip install --upgrade pip wheel setuptools
}

install_environment() {
  create_venv
  "${VENV_PYTHON}" -m pip install \
    pip wheel setuptools "inspect-evals[gaia]" inspect-tool-support openai playwright \
    -r "${REPO_ROOT}/svc_scaffold/requirement.txt"
  "${REPO_ROOT}/_state/.venv/bin/inspect-tool-support" post-install
  "${VENV_PYTHON}" -m playwright install chromium
  "${VENV_PYTHON}" "${REPO_ROOT}/runner/check_environment.py"
}

run_background() {
  RUN_TASK_NAME="$1"
  . "${REPO_ROOT}/runner/${RUN_TASK_NAME}.env"
  (
    set +e
    sh "${REPO_ROOT}/runner/${RUN_TASK_NAME}.sh" > "${REPO_ROOT}/_state/runner/${RUN_TASK_NAME}.log" 2>&1
    echo "$?" > "${REPO_ROOT}/_state/runner/${RUN_TASK_NAME}.status"
  ) &
  RUN_PIDS="${RUN_PIDS:-} $!"

  while [ ! -f "${REPO_ROOT}/_state/runner/${RUN_TASK_NAME}.ready" ]; do
    sleep 5
  done

  sleep 1
  for f in "${REPO_ROOT}"/_state/runner/*.status; do
    [ ! -f "$f" ] || exit "$(cat "$f")"
  done
}

cleanup() { kill ${RUN_PIDS:-} 2>/dev/null || :; }
trap cleanup EXIT INT TERM

if ! "${VENV_PYTHON}" "${REPO_ROOT}/runner/check_environment.py" >/dev/null 2>&1; then
  install_environment
fi

run_background "2_run_base_model_${BASE_MODEL_RUNNER_TYPE}"
run_background "3_run_scaffold"
run_background "4_run_benchmark"
