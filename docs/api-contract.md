# Cross-cohort API contract

The interface between the AIDC platform teams and the Agentic AI application
teams. This is what makes the two cohorts composable: the agentic students'
client points `base_url` at an AIDC team's endpoint and nothing else changes.

## The contract: OpenAI-compatible

Every AIDC team's service MUST expose:

- `POST /v1/chat/completions`: OpenAI Chat Completions shape, including
  **`tools` / `tool_choice`** and streaming (`stream: true`).
- `GET /v1/models`: lists the served model id(s).
- `GET /health`: liveness/readiness for K8s probes + the agentic client's retry logic.
- `GET /metrics`: Prometheus exposition (the app's stdlib `aidc_*` route at
  tier 0; vLLM's own `vllm:*` families at tier 1, colon included).

## Auth posture

- Every `/v1/*` route requires `Authorization: Bearer <key>`; a missing or
  wrong key answers **401** in the OpenAI error envelope.
- `/health` and `/metrics` stay open: probes, the uptime watch and the scraper
  carry no keys, and neither route leaks anything.
- The key is handed over in person (or to the consuming team's on-call), never
  written into a committed file; at tier 1 it lives in a Kubernetes Secret.
  The engine variable differs by tier (`API_KEY` for the FastAPI app,
  `VLLM_API_KEY` for raw vLLM) - a platform detail the consumer never sees.

vLLM implements all of `/v1/*` natively. The platform team's job is to operate
it well (uptime, latency, autoscaling), not to reimplement it.

## Why function-calling is mandatory

The agentic cohort's curriculum is ReAct / tool-calling / structured arguments.
An endpoint that can't reliably emit tool calls is useless to them. So:

- Model must support the `tools` parameter and return well-formed `tool_calls`.
- Shortlist: Qwen2.5-Instruct, Hermes-3, Llama-3.1-Instruct.
- **wk3 checkpoint smoke test:** a fixed multi-tool prompt returns valid,
  parseable `tool_calls`, which gates the model choice.

## What the agentic students receive

In week 4 the agentic team receives a short integration note: base_url, model id, an example
`tools` call, rate/quota expectations, and the endpoint's published SLOs. Kept in
the cross-cohort runbook on the course Drive.

## SLOs the platform team publishes

Each team declares and dashboards: target uptime during the window, p95 TTFT,
p95 end-to-end latency, max concurrent requests before autoscale, error budget.
These are what the integration criterion in the rubric measures.
