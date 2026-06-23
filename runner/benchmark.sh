#!/bin/sh
set -aue

pkill -f '[i]nspect eval' 2>/dev/null && sleep 2

if [ "${INSPECT_DISABLE_PROXY:-1}" = "1" ]; then
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy OPENAI_PROXY
fi

if [ "${GAIA_CHECK_DATASET_CACHE:-1}" = "1" ]; then
  "${VENV_PYTHON}" - <<'PY'
import os
import sys

if "gaia" not in os.environ.get("GAIA_TASK", ""):
    raise SystemExit(0)

try:
    from huggingface_hub import snapshot_download
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

try:
    path = snapshot_download(
        repo_id=repo_id,
        repo_type="dataset",
        revision=revision,
        local_files_only=True,
    )
except Exception as exc:
    print("", file=sys.stderr)
    print("GAIA dataset is not available in the local Hugging Face cache.", file=sys.stderr)
    print(f"  repo: {repo_id}", file=sys.stderr)
    print(f"  revision: {revision}", file=sys.stderr)
    print(f"  HF_HOME: {hf_home}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Fix options:", file=sys.stderr)
    print("  1. Use a cache that already contains the dataset:", file=sys.stderr)
    print("     HF_HOME=/path/to/huggingface-cache sh runner/localModelU.sh", file=sys.stderr)
    print("  2. Download the dataset once on a machine/network that can access Hugging Face:", file=sys.stderr)
    print(
        f"     huggingface-cli download {repo_id} --repo-type dataset --revision {revision}",
        file=sys.stderr,
    )
    print("     Then copy that Hugging Face cache to this machine and point HF_HOME at it.", file=sys.stderr)
    print("  3. If you intentionally want Inspect to attempt a network download, set:", file=sys.stderr)
    print("     GAIA_CHECK_DATASET_CACHE=0", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"Underlying local-cache error: {type(exc).__name__}: {exc}", file=sys.stderr)
    raise SystemExit(1)

print(f"GAIA dataset cache: {path}", file=sys.stderr)
PY
fi

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

"${INSPECT_BIN:-${REPO_ROOT}/.venv/bin/inspect}" "$@"
