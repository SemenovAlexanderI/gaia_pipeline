# GAIA Inspect Pipeline

This repository runs the GAIA benchmark through Inspect AI against an OpenAI-compatible model endpoint.

## Configuration

Create `.env` from the example file and fill in the required credentials:

```bash
cp .env.example .env
```

At minimum, set:

```env
BASE_MODEL_RUNNER_TYPE=llama16GB
HF_TOKEN=hf_...
```

`HF_TOKEN` must have access to the gated `gaia-benchmark/GAIA` dataset on Hugging Face.

Runner choices:

- `llama16GB`: Colab/T4-oriented runner. Downloads a prebuilt CUDA `llama-server` from `ai-dock/llama.cpp-cuda` and serves `unsloth/Qwen3.5-9B-GGUF:Q4_K_M`.
- `vllm16GB`: vLLM AWQ runner for `QuantTrio/Qwen3.5-9B-AWQ`.
- `cpu2B`: CPU fallback using `llama-cpp-python`.

## Run With Docker Compose

Use this mode on a desktop or workstation where Docker is allowed.

```bash
docker compose up
```

Docker Compose starts one Ubuntu 24.04 based Python development container. It bind-mounts this project into `/workspace`, uses that as the working directory, then runs `sh runner/start.sh`:

- `gaia`: runs `sh runner/start.sh`.
- `runner/start.sh`: installs dependencies, sources `runner/base_model/${BASE_MODEL_RUNNER_TYPE}.env`, starts the selected base model runner, starts `svc_scaffold`, then starts the benchmark job. If any background service exits, the whole run exits.

Runtime state is stored in the local ignored folder:

- `_state/`: Python virtualenvs, Hugging Face cache, downloaded GGUF files, Playwright browsers, runner logs, and Inspect eval logs.

## Run Without Docker

Use this mode on a desktop or environment where Docker is not allowed.

Install Python 3 and the required system tools in the host environment, then run:

```bash
sh runner/start.sh
```

## Local Offline Ubuntu Run

For an already downloaded GGUF model and GAIA dataset, configure these absolute
paths in `.env`:

```env
LOCAL_LLAMA_SERVER=/path/to/llama-server
LOCAL_MODEL_PATH=/path/to/model.gguf
GAIA_DATASET_DIR=/path/to/GAIA
```

Activate the conda environment containing Inspect AI, then run:

```bash
sh runner/localModelU.sh
```

The local Ubuntu runner reuses the same pipeline as the Colab runner, but
selects `runner/base_model/llamaLocal.sh` so it uses your already installed
`llama-server` and already downloaded GGUF model. It bypasses proxy settings for
local services and links the downloaded GAIA directory into the Inspect Evals
cache before the benchmark starts.

If Chromium is missing, install it into the repo-local Playwright cache used by
the runner:

```bash
PLAYWRIGHT_BROWSERS_PATH="$PWD/playwright-browsers" python -m playwright install chromium
```

If your network requires a proxy for that one-time browser download, export
`HTTP_PROXY`/`HTTPS_PROXY` before running the install command.

The default Colab runner prepares browser tooling with roughly:

```bash
inspect-tool-support post-install
python -m playwright install chromium
```

For local/proxy runs we split that into safer manual steps. If tool-support
post-install is needed, avoid the browser download side effect:

```bash
inspect-tool-support post-install --no-web-browser
```
