#!/bin/sh
set -aue

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUESTED_BASE_MODEL_RUNNER_TYPE="${1:-${BASE_MODEL_RUNNER_TYPE:-}}"

load_env() {
  if [ ! -f "$1" ]; then
    echo "Missing environment file: $1" >&2
    echo "Create it with: cp .env.example .env" >&2
    exit 1
  fi
  ENV_FILE="${TMPDIR:-/tmp}/gaia-pipeline-env.$$"
  tr -d '\r' < "$1" > "${ENV_FILE}"
  . "${ENV_FILE}"
}

if [ "${START_ENV_LOADED:-0}" != "1" ]; then
  load_env "${REPO_ROOT}/.env"
fi
if [ -n "${REQUESTED_BASE_MODEL_RUNNER_TYPE}" ]; then
  BASE_MODEL_RUNNER_TYPE="${REQUESTED_BASE_MODEL_RUNNER_TYPE}"
fi
if [ -z "${BASE_MODEL_RUNNER_TYPE:-}" ]; then
  echo "BASE_MODEL_RUNNER_TYPE is not set." >&2
  echo "Use a model entrypoint such as: sh runner/localModelU.sh" >&2
  exit 1
fi

mkdir -p "${REPO_ROOT}/_state/runner"
if [ "${START_LOGGING:-}" != "1" ]; then
  rm -rf "${REPO_ROOT}/_state/runner"/*
  START_STDOUT_PIPE="${TMPDIR:-/tmp}/gaia-pipeline.stdout.pipe.$$"
  START_STDERR_PIPE="${TMPDIR:-/tmp}/gaia-pipeline.stderr.pipe.$$"
  mkfifo "${START_STDOUT_PIPE}" "${START_STDERR_PIPE}"
  START_LOGGING=1
  tee "${REPO_ROOT}/_state/runner/start.stdout" < "${START_STDOUT_PIPE}" &
  tee "${REPO_ROOT}/_state/runner/start.stderr" >&2 < "${START_STDERR_PIPE}" &
  exec sh "$0" "$@" > "${START_STDOUT_PIPE}" 2> "${START_STDERR_PIPE}"
fi

HF_HOME="${HF_HOME:-${REPO_ROOT}/_state/huggingface}"
INSPECT_LOG_DIR="${INSPECT_LOG_DIR:-${REPO_ROOT}/_state/inspect-logs}"
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-${REPO_ROOT}/playwright-browsers}"
PID_FILE="${REPO_ROOT}/_state/runner/pids"

prepend_no_proxy() {
  value="$1"
  current="${NO_PROXY:-${no_proxy:-}}"
  case ",${current}," in
    *,"${value}",*) printf '%s\n' "${current}" ;;
    ,) printf '%s\n' "${value}" ;;
    *) printf '%s,%s\n' "${value}" "${current}" ;;
  esac
}

NO_PROXY="$(prepend_no_proxy localhost)"
NO_PROXY="$(prepend_no_proxy 127.0.0.1)"
NO_PROXY="$(prepend_no_proxy 0.0.0.0)"
NO_PROXY="$(prepend_no_proxy ::1)"
no_proxy="${NO_PROXY}"
export NO_PROXY no_proxy

resolve_command() {
  case "$1" in
    */*) printf '%s\n' "$1" ;;
    *) command -v "$1" ;;
  esac
}

select_python() {
  RUNNER_MANAGED_VENV="${RUNNER_MANAGED_VENV:-auto}"

  if [ -n "${PYTHON_BIN:-}" ]; then
    VENV_PYTHON="$(resolve_command "${PYTHON_BIN}")"
    RUNNER_MANAGED_VENV=0
  elif [ "${RUNNER_MANAGED_VENV}" = "0" ] || [ "${RUNNER_MANAGED_VENV}" = "false" ]; then
    if [ -n "${CONDA_PREFIX:-}" ] && [ -x "${CONDA_PREFIX}/bin/python" ]; then
      VENV_PYTHON="${CONDA_PREFIX}/bin/python"
    else
      VENV_PYTHON="$(resolve_command python3)"
    fi
  elif [ "${RUNNER_MANAGED_VENV}" = "auto" ] \
    && [ -n "${CONDA_PREFIX:-}" ] \
    && [ -x "${CONDA_PREFIX}/bin/python" ]; then
    VENV_PYTHON="${CONDA_PREFIX}/bin/python"
    RUNNER_MANAGED_VENV=0
  else
    VENV_PYTHON="${REPO_ROOT}/.venv/bin/python"
    RUNNER_MANAGED_VENV=1
  fi

  PYTHON_BIN_DIR="$(dirname "${VENV_PYTHON}")"
  PATH="${PYTHON_BIN_DIR}:${PATH}"
  INSPECT_BIN="${INSPECT_BIN:-${PYTHON_BIN_DIR}/inspect}"
  INSPECT_TOOL_SUPPORT_BIN="${INSPECT_TOOL_SUPPORT_BIN:-${PYTHON_BIN_DIR}/inspect-tool-support}"
}

select_python

cd "${REPO_ROOT}"
mkdir -p \
  "${HF_HOME}" \
  "${INSPECT_LOG_DIR}" \
  "${PLAYWRIGHT_BROWSERS_PATH}" \
  "${REPO_ROOT}/_state/runner"
: > "${PID_FILE}"

cleanup() {
  status=$?
  if [ -f "${PID_FILE}" ]; then
    while IFS= read -r pid; do
      [ -n "${pid}" ] || continue
      kill "${pid}" 2>/dev/null || :
    done < "${PID_FILE}"
  fi
  rm -f "${START_STDOUT_PIPE:-}" "${START_STDERR_PIPE:-}"
  exit "${status}"
}

trap cleanup EXIT
trap 'exit 1' INT TERM

create_venv() {
  if [ "${RUNNER_MANAGED_VENV}" != "1" ]; then
    "${VENV_PYTHON}" -m pip --version >/dev/null 2>&1 || {
      echo "pip is not available in ${VENV_PYTHON}" >&2
      echo "Install pip in the selected Python environment or unset RUNNER_MANAGED_VENV." >&2
      exit 1
    }
    return
  fi

  if "${VENV_PYTHON}" -m pip --version >/dev/null 2>&1; then
    return
  fi

  if "${PYTHON_BIN:-python3}" -m venv "${REPO_ROOT}/.venv"; then
    return
  fi

  rm -rf "${REPO_ROOT}/.venv"
  "${PYTHON_BIN:-python3}" -m venv --system-site-packages --without-pip "${REPO_ROOT}/.venv"
  "${VENV_PYTHON}" -m pip install --upgrade pip wheel setuptools
}

check_environment() {
  "${VENV_PYTHON}" - <<'PY'
from importlib.metadata import version
from shutil import which

import fastapi  # noqa: F401
import httpx  # noqa: F401
import inspect_ai  # noqa: F401
import inspect_evals.gaia  # noqa: F401
import openai  # noqa: F401
import playwright  # noqa: F401
import uvicorn  # noqa: F401

print(f"inspect-ai={version('inspect-ai')}")
print(f"inspect-evals={version('inspect-evals')}")

if which("inspect-tool-support") is None:
    raise RuntimeError("inspect-tool-support executable is not available on PATH")
PY
}

install_environment() {
  create_venv
  "${VENV_PYTHON}" -m pip install \
    pip wheel setuptools "inspect-evals[gaia]" inspect-tool-support openai playwright \
    -r "${REPO_ROOT}/svc_scaffold/requirement.txt"
  "${INSPECT_TOOL_SUPPORT_BIN}" post-install
  "${VENV_PYTHON}" -m playwright install chromium
  check_environment
}

if ! check_environment >/dev/null 2>&1; then
  install_environment
fi

load_env "${REPO_ROOT}/runner/base_model/${BASE_MODEL_RUNNER_TYPE}.env"
echo "[1/3] Starting base model runner: ${BASE_MODEL_RUNNER_TYPE}"
sh "${REPO_ROOT}/runner/base_model/${BASE_MODEL_RUNNER_TYPE}.sh"
echo "[2/3] Starting scaffold at http://127.0.0.1:${SCAFFOLD_PORT}"
sh "${REPO_ROOT}/runner/scaffold.sh"
echo "[3/3] Starting Inspect task: ${GAIA_TASK} (${GAIA_SPLIT})"
echo "Inspect logs: ${INSPECT_LOG_DIR}"
sh "${REPO_ROOT}/runner/benchmark.sh"
