#!/usr/bin/env python3
"""Small authenticated OpenAI-compatible smoke test."""

import json
import os
import ssl
import sys
import time
import urllib.request


url = os.environ.get("MODELARTS_CHAT_URL", "")
key = os.environ.get("MODELARTS_API_KEY", "")
model = os.environ.get("SERVED_MODEL_NAME", "glm-5.2")
if not url or not key:
    raise SystemExit("MODELARTS_CHAT_URL and MODELARTS_API_KEY are required")

payload = {
    "model": model,
    "messages": [{"role": "user", "content": "Reply exactly: GLM-5.2 OK 中文正常"}],
    "temperature": 0.1,
    "max_tokens": 64,
    "stream": True,
    "stream_options": {"include_usage": True},
}
request = urllib.request.Request(
    url,
    data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
    headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "text/event-stream",
    },
    method="POST",
)
started = time.perf_counter()
content = []
reasoning = []
usage = None
returned_model = None
finish_reason = None
done = False
chunks = 0
try:
    with urllib.request.urlopen(
        request, timeout=300, context=ssl.create_default_context()
    ) as response:
        for raw_line in response:
            line = raw_line.decode("utf-8", errors="strict").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                done = True
                break
            event = json.loads(data)
            chunks += 1
            returned_model = event.get("model") or returned_model
            usage = event.get("usage") or usage
            for choice in event.get("choices") or []:
                finish_reason = choice.get("finish_reason") or finish_reason
                delta = choice.get("delta") or {}
                content.append(delta.get("content") or "")
                reasoning.append(delta.get("reasoning_content") or "")
    result = {
        "http": response.status,
        "elapsed_s": round(time.perf_counter() - started, 3),
        "model": returned_model,
        "finish_reason": finish_reason,
        "done": done,
        "chunks": chunks,
        "content_chars": len("".join(content)),
        "reasoning_chars": len("".join(reasoning)),
        "usage": usage,
    }
    print(json.dumps(result, ensure_ascii=False))
    if response.status != 200 or not done or not chunks or returned_model != model:
        raise RuntimeError("smoke acceptance failed")
except Exception as exc:
    print(json.dumps({"error_type": type(exc).__name__, "error": str(exc)}))
    sys.exit(1)
