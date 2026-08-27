"""serving-stack: the FastAPI service (week 2, CPU, tiny model)."""

from __future__ import annotations

import json
import os
import time
import uuid

import torch
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import StreamingResponse
from transformers import AutoModelForCausalLM, AutoTokenizer

from schemas import (
    ChatCompletionRequest,
    ChatCompletionResponse,
    HealthResponse,
    ModelCard,
    ModelList,
    Choice,
    ResponseMessage,
    Usage,
)

MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-0.5B-Instruct")

API_KEY = os.environ.get("API_KEY", "")
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "256"))

if not API_KEY:
    print("WARNING: API_KEY is not set; /v1 is open")

app = FastAPI(title="serving-stack", version="wk2")


# Load once at import time. CPU only this week.
print(f"loading {MODEL_ID} on cpu ...")

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)

model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    torch_dtype=torch.float32,
)

model.to("cpu")
model.eval()

print("model ready")


# ---------------------------------------------------------------------------
# GET /health
# ---------------------------------------------------------------------------
@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    """Liveness and readiness."""
    return HealthResponse(status="ok", model=MODEL_ID)


# ---------------------------------------------------------------------------
# GET /v1/models
# ---------------------------------------------------------------------------
@app.get("/v1/models", response_model=ModelList)
def list_models(authorization: str | None = Header(default=None)) -> ModelList:
    """List the served model id(s)."""
    if API_KEY:
        expected = f"Bearer {API_KEY}"
        if authorization != expected:
            raise HTTPException(status_code=401, detail="Unauthorized")

    return ModelList(
        data=[
            ModelCard(
                id=MODEL_ID,
                created=int(time.time()),
            )
        ]
    )


# ---------------------------------------------------------------------------
# POST /v1/chat/completions
# ---------------------------------------------------------------------------
@app.post("/v1/chat/completions", response_model=None)
def chat_completions(
    req: ChatCompletionRequest,
    authorization: str | None = Header(default=None),
):
    if API_KEY:
        expected = f"Bearer {API_KEY}"
        if authorization != expected:
            raise HTTPException(status_code=401, detail="Unauthorized")

    if req.max_tokens > MAX_TOKENS:
        req.max_tokens = MAX_TOKENS


    input_ids = tokenizer.apply_chat_template(
        [m.model_dump() for m in req.messages],
        add_generation_prompt=True,
        return_tensors="pt",
    )

    prompt_tokens = input_ids.shape[1]

    # -----------------------------------------------------------------------
    # Streaming response
    # -----------------------------------------------------------------------
    if req.stream:

        def generate_stream():
            completion_id = "chatcmpl-" + uuid.uuid4().hex
            created = int(time.time())

            # Generate the complete response first.
            # Week 2 is CPU-only; Week 3 handles real concurrency/streaming.
            with torch.no_grad():
                if req.temperature > 0:
                    out = model.generate(
                        input_ids,
                        max_new_tokens=req.max_tokens,
                        do_sample=True,
                        temperature=req.temperature,
                    )
                else:
                    out = model.generate(
                        input_ids,
                        max_new_tokens=req.max_tokens,
                        do_sample=False,
                    )

            new_tokens = out[0][prompt_tokens:]

            # Send one SSE chunk per generated token.
            for token in new_tokens:
                text = tokenizer.decode(
                    [token.item()],
                    skip_special_tokens=True,
                )

                if text:
                    chunk = {
                        "id": completion_id,
                        "object": "chat.completion.chunk",
                        "created": created,
                        "model": req.model,
                        "choices": [
                            {
                                "index": 0,
                                "delta": {
                                    "content": text,
                                },
                                "finish_reason": None,
                            }
                        ],
                    }

                    yield f"data: {json.dumps(chunk)}\n\n"

            # Final chunk
            final_chunk = {
                "id": completion_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": req.model,
                "choices": [
                    {
                        "index": 0,
                        "delta": {},
                        "finish_reason": (
                            "length"
                            if len(new_tokens) >= req.max_tokens
                            else "stop"
                        ),
                    }
                ],
            }

            yield f"data: {json.dumps(final_chunk)}\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(
            generate_stream(),
            media_type="text/event-stream",
        )

    # -----------------------------------------------------------------------
    # Non-streaming response
    # -----------------------------------------------------------------------
    with torch.no_grad():
        if req.temperature > 0:
            out = model.generate(
                input_ids,
                max_new_tokens=req.max_tokens,
                do_sample=True,
                temperature=req.temperature,
            )
        else:
            out = model.generate(
                input_ids,
                max_new_tokens=req.max_tokens,
                do_sample=False,
            )

    new_tokens = out[0][prompt_tokens:]

    completion_tokens = len(new_tokens)

    text = tokenizer.decode(
        new_tokens,
        skip_special_tokens=True,
    )

    finish_reason = (
        "length"
        if completion_tokens >= req.max_tokens
        else "stop"
    )

    return ChatCompletionResponse(
        id="chatcmpl-" + uuid.uuid4().hex,
        created=int(time.time()),
        model=req.model,
        choices=[
            Choice(
                message=ResponseMessage(
                    role="assistant",
                    content=text,
                ),
                finish_reason=finish_reason,
            )
        ],
        usage=Usage(
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=prompt_tokens + completion_tokens,
        ),
    )
