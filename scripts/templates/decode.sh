#!/usr/bin/env bash
set -Eeuo pipefail

export GLOO_SOCKET_IFNAME="$ENTRY_NET_INTERFACE"
export TP_SOCKET_IFNAME="$ENTRY_NET_INTERFACE"
export HCCL_IF_IP="$POD_IP"
export HCCL_SOCKET_IFNAME="$ENTRY_NET_INTERFACE"
export HCCL_RDMA_TIMEOUT=20
export HCCL_CONNECT_TIMEOUT=1800
export HCCL_EXEC_TIMEOUT=3000
export HCCL_BUFFSIZE=2560
export HCCL_OP_EXPANSION_MODE=AIV
export HCCL_INTRA_ROCE_ENABLE=1
export HCCL_IF_BASE_PORT=64000
export VLLM_ENGINE_READY_TIMEOUT_S=3600
export VLLM_MOONCAKE_ABORT_REQUEST_TIMEOUT=480
export VLLM_HTTP_TIMEOUT_KEEP_ALIVE=3605
export VLLM_RPC_TIMEOUT=3600000
export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=30000
export VLLM_NIXL_ABORT_REQUEST_TIMEOUT=300000
export VLLM_HOST_IP="$POD_IP"
export ASCEND_CONNECT_TIMEOUT=60000
export ASCEND_TRANSFER_TIMEOUT=10000
export ASCEND_AGGREGATE_ENABLE=1
export ACL_OP_INIT_MODE=1
export ASCEND_RT_VISIBLE_DEVICES=$1
export ASCEND_AUTO_CONNECT=1
export PYTHONHASHSEED=0
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
  --prefill-context-parallel-size 1 \
  --decode-context-parallel-size 8 \
  --cp-kv-cache-interleave-size 128 \
  --enable-expert-parallel \
  --enable-prefix-caching \
  --seed 1024 \
  --served-model-name "${SERVED_MODEL_NAME:-glm-5.2}" \
  --async-scheduling \
  --max-model-len "${MAX_MODEL_LEN:-1048576}" \
  --max-num-batched-tokens "${DECODE_MAX_BATCHED_TOKENS:-256}" \
  --trust-remote-code \
  --max-num-seqs "${MAX_NUM_SEQS:-8}" \
  --gpu-memory-utilization "${DECODE_GPU_MEMORY_UTILIZATION:-0.90}" \
  --safetensors-load-strategy prefetch \
  --quantization ascend \
  --enable-auto-tool-choice \
  --tool-call-parser glm47 \
  --reasoning-parser glm45 \
  --kv-transfer-config '{"kv_connector":"MultiConnector","kv_role":"kv_consumer","kv_load_failure_policy":"recompute","kv_connector_extra_config":{"connectors":[{"kv_connector":"MooncakeConnectorV1","kv_buffer_size":8000000000,"kv_role":"kv_consumer","kv_port":"30100","kv_connector_extra_config":{"prefill":{"dp_size":4,"tp_size":8},"decode":{"dp_size":4,"tp_size":8},"load_async":true,"use_layerwise":true}},{"kv_connector":"AscendStoreConnector","kv_role":"kv_consumer","kv_connector_extra_config":{"lookup_rpc_port":"0","load_async":true,"backend":"mooncake"}}]}}' \
  --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY","cudagraph_capture_sizes":[4,8,16,24,32,40,48,56,64,96,128,160,192,224,256,298,320,352,384]}' \
  --additional-config '{"ascend_compilation_config":{"enable_npugraph_ex":true,"enable_static_kernel":false},"fuse_muls_add":true,"enable_mlapo":true,"multistream_overlap_shared_expert":true,"enable_sparse_sfa_c8":true,"enable_sparse_li_c8":true,"int8_per_token_head":true,"enable_cpu_binding":true,"recompute_scheduler_enable":true}' \
  --speculative-config "{\"num_speculative_tokens\":${DECODE_MTP_TOKENS:-3},\"method\":\"deepseek_mtp\",\"enforce_eager\":true}" \
  >>"$node_log/vllm.log" 2>&1
