#!/usr/bin/env bash
set -euo pipefail

PREDICT_PORT=${PREDICT_PORT:-1025}
PROXY_PORT=${PROXY_PORT:-8000}
curl -fsS --max-time 10 "http://127.0.0.1:${PREDICT_PORT}/health" >/dev/null
if [[ "${GLM52_ROLE:-}" == "D_WORKER" ]]; then
  curl -fsS --max-time 10 "http://127.0.0.1:$((PREDICT_PORT + 1))/health" >/dev/null
fi
if [[ "${GLM52_ROLE:-}" == "P_ENTRY" ]]; then
  curl -fsS --max-time 10 "http://127.0.0.1:${PROXY_PORT}/health" >/dev/null
fi
