#!/usr/bin/env bash
set -Eeuo pipefail

# Positional arguments are supplied by vLLM Ascend launch_online_dp.py:
# devices, port, global DP, DP rank, DP address, DP RPC port, TP.
export GLOO_SOCKET_IFNAME="$ENTRY_NET_INTERFACE"
export TP_SOCKET_IFNAME="$ENTRY_NET_INTERFACE"
export HCCL_IF_IP="$POD_IP"
export HCCL_SOCKET_IFNAME="$ENTRY_NET_INTERFACE"
export HCCL_RDMA_TIMEOUT=20
export HCCL_CONNECT_TIMEOUT=1800
export HCCL_EXEC_TIMEOUT=3000
export HCCL_BUFFSIZE=256
export HCCL_OP_EXPANSION_MODE=AIV
export HCCL_INTRA_ROCE_ENABLE=1
export HCCL_IF_BASE_PORT=64000
export VLLM_ENGINE_READY_TIMEOUT_S=3600
export VLLM_MOONCAKE_ABORT_REQUEST_TIMEOUT=480
export VLLM_HTTP_TIMEOUT_KEEP_ALIVE=3605
export VLLM_RPC_TIMEOUT=3600000
export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=30000
export VLLM_ASCEND_ENABLE_FLASHCOMM1=1
export VLLM_ASCEND_ENABLE_FUSED_MC2=1
export VLLM_ASCEND_ENABLE_MLAPO=1
export VLLM_NIXL_ABORT_REQUEST_TIMEOUT=300000
export ASCEND_CONNECT_TIMEOUT=60000
export ASCEND_TRANSFER_TIMEOUT=10000
export ASCEND_AGGREGATE_ENABLE=1
export ACL_OP_INIT_MODE=1
export ASCEND_RT_VISIBLE_DEVICES=$1
export ASCEND_AUTO_CONNECT=1
export PYTHONHASHSEED=1234
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=10
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export TASK_QUEUE_ENABLE=1
export MOONCAKE_CONFIG_PATH=${MOONCAKE_CONFIG_PATH:-/cache/config/mooncake.json}

node_log="${LOG_PATH:-/logs}/${MODELARTS_COHORT_ID}-${GLM52_ROLE}-${POD_IP}"
mkdir -p "$node_log"
export ASCEND_PROCESS_LOG_PATH="$node_log/ascend"

vllm serve "$MODEL_PATH" \
  --host 0.0.0.0 \
  --port "$2" \
  --data-parallel-size "$3" \
  --data-parallel-rank "$4" \
  --data-parallel-address "$5" \
  --data-parallel-rpc-port "$6" \
  --tensor-parallel-size "$7" \
  --enable-expert-parallel \
  --enable-prefix-caching \
  --seed 1024 \
  --enable-chunked-prefill \
  --served-model-name "${SERVED_MODEL_NAME:-glm-5.2}" \
  --async-scheduling \
  --max-model-len "${MAX_MODEL_LEN:-256000}" \
  --max-num-batched-tokens "${PREFILL_MAX_BATCHED_TOKENS:-8192}" \
  --trust-remote-code \
  --max-num-seqs "${PREFILL_MAX_NUM_SEQS:-256}" \
  --gpu-memory-utilization "${PREFILL_GPU_MEMORY_UTILIZATION:-0.95}" \
  --safetensors-load-strategy prefetch \
  --quantization ascend \
  --enforce-eager \
  --enable-auto-tool-choice \
  --tool-call-parser glm47 \
  --reasoning-parser glm45 \
  --kv-transfer-config '{"kv_connector":"MultiConnector","kv_role":"kv_producer","kv_load_failure_policy":"recompute","kv_connector_extra_config":{"connectors":[{"kv_connector":"MooncakeConnectorV1","kv_role":"kv_producer","kv_port":"30000","kv_connector_extra_config":{"prefill":{"dp_size":4,"tp_size":8},"decode":{"dp_size":8,"tp_size":4}}},{"kv_connector":"AscendStoreConnector","kv_role":"kv_producer","kv_connector_extra_config":{"lookup_rpc_port":"0","backend":"mooncake"}}]}}' \
  --additional-config '{"enable_flashcomm1":true,"enable_dsa_cp":true,"ascend_compilation_config":{"enable_npugraph_ex":true},"fuse_muls_add":true,"multistream_overlap_shared_expert":true,"enable_sparse_sfa_c8":true,"enable_sparse_li_c8":true,"int8_per_token_head":true,"enable_cpu_binding":true}' \
  --speculative-config "{\"num_speculative_tokens\":${PREFILL_MTP_TOKENS:-1},\"method\":\"deepseek_mtp\",\"enforce_eager\":true}" \
  >>"$node_log/vllm.log" 2>&1
