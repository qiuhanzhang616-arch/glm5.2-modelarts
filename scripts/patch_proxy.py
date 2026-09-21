#!/usr/bin/env python3
"""Add an OpenAI-compatible /v1/models route to a copied proxy script."""

from pathlib import Path
import sys


MARKER = '@app.get("/v1/models")'
ANCHOR = 'if __name__ == "__main__":'
ROUTE = r'''
@app.get("/v1/models")
async def handle_list_models():
    from fastapi.responses import JSONResponse
    import httpx
    candidates = list(proxy_state.prefillers) + list(proxy_state.decoders)
    last_error = None
    for server in candidates:
        try:
            response = await server.client.get("/models", timeout=5.0)
            response.raise_for_status()
            return response.json()
        except (httpx.RequestError, httpx.HTTPStatusError) as exc:
            last_error = type(exc).__name__
    return JSONResponse(status_code=503, content={"error": f"No backend: {last_error}"})


'''


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_proxy.py <copied-proxy-script>")
    path = Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        return
    if ANCHOR not in text:
        raise SystemExit("proxy anchor not found; image revision is incompatible")
    path.write_text(text.replace(ANCHOR, ROUTE + ANCHOR, 1), encoding="utf-8")


if __name__ == "__main__":
    main()
