#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_PATH=${SCRIPT_PATH:-/cache/scripts}
LOG_PATH=${LOG_PATH:-/logs}
PREDICT_PORT=${PREDICT_PORT:-1025}
PROXY_PORT=${PROXY_PORT:-8000}
DP_RPC_PORT=${DP_RPC_PORT:-12345}
LAUNCH_ONLINE_DP_SCRIPT=${LAUNCH_ONLINE_DP_SCRIPT:?Set LAUNCH_ONLINE_DP_SCRIPT}
LOAD_BALANCE_PROXY_SCRIPT=${LOAD_BALANCE_PROXY_SCRIPT:?Set LOAD_BALANCE_PROXY_SCRIPT}

command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
MODEL_PATH=${MODEL_PATH:?Set MODEL_PATH to the mounted GLM-5.2-w4a8c8 directory}
MOONCAKE_CONFIG_PATH=${MOONCAKE_CONFIG_PATH:-/cache/config/mooncake.json}
export MODEL_PATH MOONCAKE_CONFIG_PATH
test -s "$MODEL_PATH/config.json"
test -f "$MODEL_PATH/.download-complete"
test -s "$MOONCAKE_CONFIG_PATH"
mkdir -p "$LOG_PATH"
read -r POD_IP_RESOLVED NIC < <(python3 "$SCRIPT_PATH/standard_network.py")
export POD_IP="$POD_IP_RESOLVED"
export ENTRY_NET_INTERFACE="$NIC"

topology=/tmp/glm52-topology.json
python3 "$SCRIPT_PATH/topology.py" --timeout 1800 --output "$topology"
side=$(jq -r .side "$topology")
role=$(jq -r .role "$topology")
position=$(jq -r .position "$topology")
p_master=$(jq -r .p_master "$topology")
d_master=$(jq -r .d_master "$topology")

runtime=/tmp/glm52-runtime
mkdir -p "$runtime"
cp "$LAUNCH_ONLINE_DP_SCRIPT" "$runtime/launch_online_dp.py"
if [[ "$side" == "P" ]]; then
  cp "$SCRIPT_PATH/templates/prefill.sh" "$runtime/run_dp_template.sh"
  dp_size=${PREFILL_DP_SIZE:-4}
  tp_size=${PREFILL_TP_SIZE:-8}
  dp_size_local=1
  dp_rank_start=$position
  dp_address=$p_master
else
  cp "$SCRIPT_PATH/templates/decode.sh" "$runtime/run_dp_template.sh"
  dp_size=${DECODE_DP_SIZE:-8}
  tp_size=${DECODE_TP_SIZE:-4}
  dp_size_local=${DECODE_DP_SIZE_LOCAL:-2}
  dp_rank_start=$((position * dp_size_local))
  dp_address=$d_master
fi
chmod 750 "$runtime/run_dp_template.sh"

backend_log="$LOG_PATH/${MODELARTS_COHORT_ID}-${role}-${POD_IP}.log"
launch=(python3 "$runtime/launch_online_dp.py"
  --dp-size "$dp_size"
  --tp-size "$tp_size"
  --dp-size-local "$dp_size_local"
  --dp-rank-start "$dp_rank_start"
  --dp-address "$dp_address"
  --dp-rpc-port "$DP_RPC_PORT"
  --vllm-start-port "$PREDICT_PORT")

if [[ "$role" != "P_ENTRY" ]]; then
  cd "$runtime"
  exec "${launch[@]}" >>"$backend_log" 2>&1
fi

(cd "$runtime" && "${launch[@]}" >>"$backend_log" 2>&1) &
backend_pid=$!

for _ in $(seq 1 3600); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${PREDICT_PORT}/health" >/dev/null; then
    break
  fi
  kill -0 "$backend_pid" || { echo "Prefill backend exited" >&2; exit 1; }
  sleep 1
done

proxy="$runtime/load_balance_proxy.py"
cp "$LOAD_BALANCE_PROXY_SCRIPT" "$proxy"
python3 "$SCRIPT_PATH/patch_proxy.py" "$proxy"
p_hosts=$(jq -r '.p_ips | join(" ")' "$topology")
d_hosts=$(jq -r '.d_ips | map([., .]) | flatten | join(" ")' "$topology")
p_ports="$PREDICT_PORT $PREDICT_PORT $PREDICT_PORT $PREDICT_PORT"
d_ports=""
for _ in $(seq 1 4); do
  d_ports+="$PREDICT_PORT $((PREDICT_PORT + 1)) "
done

exec python3 "$proxy" \
  --host 0.0.0.0 \
  --port "$PROXY_PORT" \
  --prefiller-hosts $p_hosts \
  --prefiller-ports $p_ports \
  --decoder-hosts $d_hosts \
  --decoder-ports $d_ports
