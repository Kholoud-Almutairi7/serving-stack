# Version pins (single source of truth)

Every lab and Dockerfile draws its versions from here. Labs say "install per
PINS.md"; do not scatter hard version numbers across notebooks and READMEs.
When a pin changes, it changes here once.

## Python

- Colab base: Python 3.12 (3.12.13 as of 2026-07-27; do not pin the
  interpreter, pin the packages). Colab also ships torch 2.11.0+cu128
  preinstalled, so labs must never install a second torch.
- Local service image base: `python:3.11-slim`.

## The serving service (weeks 2, tier 0 CPU path)

| Package | Pin | Note |
|---|---|---|
| fastapi | 0.115.* | routes + the OpenAI shapes |
| uvicorn[standard] | 0.32.* | ASGI server, port 8000 |
| pydantic | 2.9.* | request/response validation |
| transformers | 4.46.* | CPU generation, tier-0 |
| torch | 2.5.* (cpu wheel in the image) | CPU inference in the container |
| accelerate | 1.1.* | device placement |
| httpx | 0.27.* | test client, async bench |
| openai | 1.54.* | the client that proves the contract |

CPU model (API labs): `Qwen/Qwen2.5-0.5B-Instruct`.

## The GPU / vLLM path (week 3, Colab T4)

| Package | Pin | Note |
|---|---|---|
| vllm | 0.6.* (confirm exact on T4) | OpenAI server; `--dtype half` on sm75 |
| torch | ships with the vllm wheel | do not install a second torch |
| bitsandbytes | 0.49.2 | int8/int4 in the W2D1 and W3D1 profiling labs; `0.44.*` is broken on cu128, see Verification status |
| autoawq | 0.2.* | AWQ weights load path |
| nvidia-ml-py | 12.* | programmatic nvidia-smi if needed |

GPU model (measurement + serving): `Qwen/Qwen2.5-1.5B-Instruct`
(fp16 about 3.1 GB of weights). AWQ build: `Qwen/Qwen2.5-1.5B-Instruct-AWQ`.

vLLM launch flags on the T4 (canon, repeated in the Colab scaffold):

```
--model Qwen/Qwen2.5-1.5B-Instruct \
--dtype half \                 # sm75: no bf16, no FlashAttention (xformers backend)
--max-model-len 4096 \
--gpu-memory-utilization 0.85 \
--port 8000
```

Function-calling flags, added when the model is locked (week 3 day 4):

- Qwen2.5-Instruct, Hermes-3: `--enable-auto-tool-choice --tool-call-parser hermes`
- Llama-3.1-Instruct: `--enable-auto-tool-choice --tool-call-parser llama3_json`

Pocket known-good model if a team's candidate fails the smoke test:
`Qwen/Qwen2.5-1.5B-Instruct` with the `hermes` parser.

## CUDA base image (week 2 day 4, GPU image)

- `nvidia/cuda:12.4.1-runtime-ubuntu22.04` for the runtime image.
- Pre-seeded by the prep-week `verify-env` pull, so day 4 is not a download day.
- Confirm the tag still resolves at build time; CUDA base tags move.

## Orchestration (weeks 4-5, listed here so the file stays the one place)

The week-4 table below is the pin of record: it is what the 2026-08-07 build
ran end to end on kind, and it wins over any figure quoted elsewhere. Locust
for the laptop load generator: 2.32.*. Prometheus and Grafana are standalone
deployments, not kube-prometheus-stack.


## Week-4 toolchain (pinned to what the 2026-08-07 build actually ran)

| Tool | Pin | Note |
|---|---|---|
| kind | v0.31.0 | node image v1.35.0; the earlier 0.24 line was never exercised |
| kubectl | v1.35.0 | matches the node |
| helm | 4.2.x | get-helm-3 script installs current stable |
| cloudflared | latest release binary | quick tunnels only |
| metrics-server | v0.9.0 | vendored manifest carries --kubelet-insecure-tls for kind |
| prometheus (go-live pack) | v2.55.1 | standalone deployment, not kube-prometheus-stack; the pack ships a 2Gi PVC so history survives pod restarts, but `kind delete cluster` still erases it |
| grafana (wk5) | 11.4.0 | anonymous viewer |

## Tier-1 team pod (weeks 4-5, the GPU track)

Validated end to end on 2026-08-13 on a Hyperstack RTX A6000 (48 GB), Ubuntu
22.04.5, driver 570.195.03. Procedure: the tier-1 pod runbook.

| Tool | Pin | Note |
|---|---|---|
| k3s | v1.36.3+k3s1 | **install with `--default-runtime nvidia --write-kubeconfig-mode 644`**; both flags are load-bearing, see the runbook |
| containerd | 2.3.2-k3s2 | ships inside k3s |
| NVIDIA device plugin | v0.17.4 | upstream static manifest, applied unmodified |
| NVIDIA Container Toolkit | 1.18.1 | must be installed **before** k3s or k3s never detects the runtime |
| vllm (in-cluster) | **v0.27.1** | `vllm/vllm-openai` image. **Deliberately NOT the 0.6.6.post1 Colab pin**. Tier 1 serves from the vllm/vllm-openai image, which is newer than the Colab pin and is not interchangeable with it |

`get.k3s.io` installs the stable channel, so the k3s version above is what
stable resolved to on that date and it will drift. Nothing in the tier-1 path
depends on the patch version; the two install flags are what matter. Week 4's
tier-0 kind cluster stays on v1.35.0 and is unaffected.
