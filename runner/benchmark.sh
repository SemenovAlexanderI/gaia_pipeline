#!/bin/sh
set -aue

pkill -f '[i]nspect eval' 2>/dev/null && sleep 2

if [ "${INSPECT_DISABLE_PROXY:-1}" = "1" ]; then
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy OPENAI_PROXY
fi

if [ "${GAIA_CHECK_DATASET_CACHE:-1}" = "1" ]; then
  "${VENV_PYTHON}" - <<'PY'
import os
import shutil
import sys
from pathlib import Path

if "gaia" not in os.environ.get("GAIA_TASK", ""):
    raise SystemExit(0)

try:
    from huggingface_hub import snapshot_download
    from inspect_evals.constants import INSPECT_EVALS_CACHE_PATH
    from inspect_evals.gaia import dataset as gaia_dataset_module
    from inspect_evals.gaia import gaia as gaia_module
except Exception as exc:
    print(f"GAIA dataset preflight skipped: {type(exc).__name__}: {exc}", file=sys.stderr)
    raise SystemExit(0)

repo_id = getattr(gaia_dataset_module, "DATASET_PATH", "gaia-benchmark/GAIA")
revision = (
    getattr(gaia_module, "DATASET_REVISION", None)
    or getattr(gaia_dataset_module, "DATASET_REVISION", None)
    or "main"
)
hf_home = os.environ.get("HF_HOME") or "~/.cache/huggingface"
repo_root = Path(os.environ.get("REPO_ROOT", ".")).resolve()
expected_dir = INSPECT_EVALS_CACHE_PATH / "gaia_dataset" / "GAIA"
local_dir_value = os.environ.get("GAIA_DATASET_DIR") or repo_root / "datasets" / "GAIA"
local_dir = Path(local_dir_value).expanduser().resolve()


def looks_like_gaia_dataset(path: Path) -> bool:
    return path.is_dir() and (path / "2023").is_dir()


if looks_like_gaia_dataset(expected_dir):
    print(f"GAIA dataset cache: {expected_dir}", file=sys.stderr)
    raise SystemExit(0)

if looks_like_gaia_dataset(local_dir):
    expected_dir.parent.mkdir(parents=True, exist_ok=True)
    if expected_dir.exists() or expected_dir.is_symlink():
        if not looks_like_gaia_dataset(expected_dir):
            if expected_dir.is_symlink() or expected_dir.is_file():
                expected_dir.unlink(missing_ok=True)
            else:
                shutil.rmtree(expected_dir, ignore_errors=True)
    if not expected_dir.exists():
        try:
            expected_dir.symlink_to(local_dir, target_is_directory=True)
            print(f"GAIA dataset cache: {expected_dir} -> {local_dir}", file=sys.stderr)
        except OSError:
            shutil.copytree(local_dir, expected_dir)
            print(f"GAIA dataset cache: copied {local_dir} to {expected_dir}", file=sys.stderr)
    raise SystemExit(0)

try:
    path = snapshot_download(
        repo_id=repo_id,
        repo_type="dataset",
        revision=revision,
        local_dir=expected_dir,
        local_files_only=True,
    )
except Exception as exc:
    print("", file=sys.stderr)
    print("GAIA dataset is not available in the local Hugging Face cache.", file=sys.stderr)
    print(f"  repo: {repo_id}", file=sys.stderr)
    print(f"  revision: {revision}", file=sys.stderr)
    print(f"  HF_HOME: {hf_home}", file=sys.stderr)
    print(f"  inspect-evals cache: {expected_dir}", file=sys.stderr)
    print(f"  local dataset dir: {local_dir}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Fix options:", file=sys.stderr)
    print("  1. Copy your downloaded GAIA folder to:", file=sys.stderr)
    print("     ./datasets/GAIA", file=sys.stderr)
    print("     or run with GAIA_DATASET_DIR=/path/to/GAIA.", file=sys.stderr)
    print("  2. Download the dataset once on a machine/network that can access Hugging Face:", file=sys.stderr)
    print(
        f"     hf download {repo_id} --repo-type dataset --revision {revision} --local-dir ./GAIA",
        file=sys.stderr,
    )
    print("     Then copy ./GAIA to this machine as ./datasets/GAIA.", file=sys.stderr)
    print("  3. If you intentionally want Inspect to attempt a network download, set:", file=sys.stderr)
    print("     GAIA_CHECK_DATASET_CACHE=0", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"Underlying local-cache error: {type(exc).__name__}: {exc}", file=sys.stderr)
    raise SystemExit(1)

print(f"GAIA dataset cache: {path}", file=sys.stderr)
PY
fi

INSPECT_TASK="${GAIA_TASK}"
GAIA_TOOL_TIMEOUT_VALUE="${GAIA_TOOL_TIMEOUT:-0}"
case "${GAIA_TOOL_TIMEOUT_VALUE}" in
  ''|*[!0-9]*) GAIA_TOOL_TIMEOUT_VALUE=0 ;;
esac
if [ "${GAIA_USE_LOCAL_GAIA_TASK:-auto}" != "0" ] && [ "${GAIA_TOOL_TIMEOUT_VALUE}" -gt 0 ]; then
  case "${GAIA_TASK}" in
    inspect_evals/gaia)
      INSPECT_TASK="${REPO_ROOT}/tasks/local_gaia.py@gaia"
      ;;
    inspect_evals/gaia_level1)
      INSPECT_TASK="${REPO_ROOT}/tasks/local_gaia.py@gaia_level1"
      ;;
    inspect_evals/gaia_level2)
      INSPECT_TASK="${REPO_ROOT}/tasks/local_gaia.py@gaia_level2"
      ;;
    inspect_evals/gaia_level3)
      INSPECT_TASK="${REPO_ROOT}/tasks/local_gaia.py@gaia_level3"
      ;;
  esac
fi

set -- eval "${INSPECT_TASK}" \
  --model "openai-api/gaia_model/${SCAFFOLD_MODEL_NAME}" \
  --sandbox "${GAIA_SANDBOX}" \
  --max-connections "${GAIA_MAX_CONNECTIONS}" \
  -T "split=${GAIA_SPLIT}" \
  -T "max_attempts=${GAIA_MAX_ATTEMPTS}"

if [ "${GAIA_TOOL_TIMEOUT_VALUE}" -gt 0 ]; then
  set -- "$@" -T "code_timeout=${GAIA_TOOL_TIMEOUT_VALUE}"
fi

if [ -n "${GAIA_SAMPLE_TIME_LIMIT:-}" ]; then
  set -- "$@" -T "time_limit=${GAIA_SAMPLE_TIME_LIMIT}"
fi

if [ -n "${GAIA_SAMPLE_START:-}" ] && [ -n "${GAIA_SAMPLE_END:-}" ]; then
  set -- "$@" --limit "${GAIA_SAMPLE_START}-${GAIA_SAMPLE_END}"
fi

if [ -n "${GAIA_MAX_SAMPLES:-}" ]; then
  set -- "$@" --max-samples "${GAIA_MAX_SAMPLES}"
fi

if [ -n "${GAIA_MESSAGE_LIMIT:-}" ]; then
  set -- "$@" --message-limit "${GAIA_MESSAGE_LIMIT}"
fi

if [ "${GAIA_NO_FAIL_ON_ERROR:-1}" = "1" ]; then
  set -- "$@" --no-fail-on-error
fi

"${INSPECT_BIN:-${REPO_ROOT}/.venv/bin/inspect}" "$@"
