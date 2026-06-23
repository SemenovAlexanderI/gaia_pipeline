# GAIA Inspect Pipeline

This repository runs the GAIA benchmark through Inspect AI against an OpenAI-compatible model endpoint.

## Configuration

Create `.env` from the example file and fill in the required credentials:

```bash
cp .env.example .env
```

At minimum, set:

```env
HF_TOKEN=hf_...
```

`HF_TOKEN` must have access to the gated `gaia-benchmark/GAIA` dataset on Hugging Face.

Model entrypoints:

- `sh runner/localModelU.sh`: local Ubuntu runner. Uses an existing `llama-server` binary and the GGUF at `LOCAL_MODEL_PATH`; it does not download a CUDA build or a model.
- `sh runner/start.sh llama16GB`: Colab/T4-oriented runner. Downloads a prebuilt CUDA `llama-server` from `ai-dock/llama.cpp-cuda` and serves `unsloth/Qwen3.5-9B-GGUF:Q4_K_M`.
- `sh runner/start.sh vllm16GB`: vLLM AWQ runner for `QuantTrio/Qwen3.5-9B-AWQ`.
- `sh runner/start.sh cpu2B`: CPU fallback using `llama-cpp-python`.

For a local `llama-server` installation and an already downloaded model, set:

```bash
export LOCAL_MODEL_PATH=/home/user/models/Qwen3.5-9B-Q4_K_M.gguf
export LLAMA_SERVER_BIN=llama-server
export LLAMA_CTX_SIZE=262144
export LLAMA_PARALLEL=1
sh runner/localModelU.sh
```

`INSPECT_DISABLE_PROXY=1` is enabled in `.env.example` because Inspect/httpx
will crash on invalid proxy values such as `socks://127.0.0.1:3128/`. If your
GAIA run needs a proxy for external web access, use a valid proxy URL and set
`INSPECT_DISABLE_PROXY=0`.

The GAIA dataset is gated. For offline/local runs, download it elsewhere with
`hf download gaia-benchmark/GAIA --repo-type dataset --local-dir ./GAIA`, then
copy it into this project as `datasets/GAIA`. The runner links that folder into
the cache location expected by `inspect_evals`. If the folder lives elsewhere,
set `GAIA_DATASET_DIR=/path/to/GAIA`.

When using `GAIA_SANDBOX=local`, GAIA sample attachments are placed under
`/shared_files`. Create that directory once before running:

```bash
sudo mkdir -p /shared_files
sudo chown "${USER}:${USER}" /shared_files
```

CUDA compatibility is determined by the locally
installed `llama-server`; the pipeline does not download or link another CUDA build.
The local runner starts with a 262144-token context. This matches long GAIA
prompts better than the conservative local default used earlier. Lower
`LLAMA_CTX_SIZE` only if your GPU/CPU memory cannot hold the KV cache.
If the process exits early, inspect `_state/runner/start.stderr` and
`_state/runner/llamaLocal.stderr`.

## Run With Docker Compose

Use this mode on a desktop or workstation where Docker is allowed.

```bash
docker compose up
```

Docker Compose starts one Ubuntu 24.04 based Python development container. It bind-mounts this project into `/workspace`, uses that as the working directory, then runs `sh runner/start.sh llama16GB`:

- `gaia`: runs `sh runner/start.sh llama16GB`.
- `runner/start.sh`: installs dependencies, sources `runner/base_model/${BASE_MODEL_RUNNER_TYPE}.env`, starts the selected base model runner, starts `svc_scaffold`, then starts the benchmark job. If any background service exits, the whole run exits.
- `runner/localModelU.sh`: selects the local Ubuntu `llama-server` runner and keeps local model-serving defaults out of `.env`.

Runtime state is stored in the local ignored folder:

- `_state/`: Python virtualenvs, Hugging Face cache, downloaded GGUF files, Playwright browsers, runner logs, and Inspect eval logs.

## Run Without Docker

Use this mode on a desktop or environment where Docker is not allowed.

Install Python 3 and the required system tools in the host environment, then run:

```bash
sh runner/localModelU.sh
```
