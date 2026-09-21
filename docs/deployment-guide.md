# GLM-5.2 C6 P/D deployment on Huawei Cloud ModelArts Standard

## 1. Scope

This public-cloud template deploys `GLM-5.2-w4a8c8` using the validated C6
64-NPU prefill/decode-disaggregated profile on ModelArts Standard.

| Side | Nodes | Local NPUs | Parallelism | MTP | Batched tokens |
|---|---:|---:|---|---:|---:|
| Prefill | 4 | 8 | DP4 × TP8 × EP | 1 | 8192 |
| Decode | 4 | 8 | DP8 × TP4 × EP; two ranks/node | 3 | 256 |

Both sides configure a 256,000-token context, prefix caching,
Mooncake/Ascend Store KV transfer, and GLM reasoning/tool parsers. C6 enables
MLAPO and shared-expert multistream on Decode, while keeping Decode Fused MC2
and Dynamic EPLB disabled. It must still be revalidated against the selected
public-cloud flavor, driver, firmware, and image digest.

## 2. Project-specific values

Fill these values with resources from the deployment project:

```text
REGION_ID=<REGION_ID>
PROJECT_ID=<PROJECT_ID>
MODELARTS_RESOURCE_POOL_ID=<DEDICATED_POOL_ID>
VPC_ID=<VPC_ID>
SUBNET_ID=<SUBNET_ID>
SECURITY_GROUP_ID=<SECURITY_GROUP_ID>
SWR_IMAGE_URI=<PRIVATE_SWR_IMAGE_URI>
IMAGE_DIGEST=<IMMUTABLE_IMAGE_DIGEST>
SFS_MODEL_DIRECTORY=<MODEL_DIRECTORY>
SFS_SCRIPT_DIRECTORY=<SCRIPT_DIRECTORY>
SFS_CONFIG_DIRECTORY=<CONFIG_DIRECTORY>
SFS_LOG_DIRECTORY=<LOG_AND_RENDEZVOUS_DIRECTORY>
MOONCAKE_METADATA_HOST=<INTERNAL_METADATA_SERVICE_DNS_OR_IP>
MODELARTS_COHORT_ID=<UNIQUE_ROLLOUT_ID>
```

Never copy an address, ID, or secret from another project.

## 3. Permissions and consoles

- IAM: <https://console.huaweicloud.com/iam/>
- ModelArts: <https://console.huaweicloud.com/modelarts/>
- SWR: <https://console.huaweicloud.com/swr/>
- SFS: <https://console.huaweicloud.com/sfs/>
- LTS: <https://console.huaweicloud.com/lts/>
- CES: <https://console.huaweicloud.com/ces/>

Recommended policies are `ModelArtsXInferAllPolicy`, `ModelArts
CommonOperations`, `SWR OperateAccess`, the required OBS/SFS policy, and
optional LTS/CES policies. Prefer folder-scoped custom SFS permissions and a
ModelArts IAM agency over user AK/SK inside containers.

References:

- <https://support.huaweicloud.com/intl/en-us/permission-modelarts/inference2.0-modelarts-0036.html>
- <https://support.huaweicloud.com/intl/en-us/api-modelarts/modelarts_03_0174.html>
- <https://support.huaweicloud.com/intl/en-us/usermanual-standard-modelarts/modelarts_23_0084.html>

## 4. Prepare the resource pool

1. Reserve eight homogeneous nodes with eight 64 GB Ascend A2 NPUs each.
2. Use a low-latency VPC and allow all required HCCL and KV-transfer traffic
   between the eight nodes. Each Decode node must host two TP4 ranks.
3. Confirm access to SWR, SFS, OBS, LTS, CES, and the internal Mooncake metadata
   service.
4. Run the official vLLM Ascend multi-node communication verification.
5. Do not overlap another deployment requiring these 64 NPUs.

## 5. Mirror the official image

Use the official A2 image:

```text
quay.io/ascend/vllm-ascend:v0.23.0
```

Mirror it unchanged into the project SWR repository and pin the resulting
digest. Do not reuse private tags such as `rc`, `arm-rs`, or tenant-specific
suffixes unless their build provenance and digest are independently audited.

## 6. Download the model

Official model page:

<https://www.modelscope.cn/models/Eco-Tech/GLM-5.2-w4a8c8>

Download the complete checkpoint into `<SFS_MODEL_DIRECTORY>`. Use a staging
directory and expose it to inference only after all safetensors, tokenizer,
configuration, quantization metadata, and generation files are present.

## 7. Mooncake prerequisite

Deploy an internal Mooncake metadata service reachable from all eight pods.
Copy `configs/mooncake.json.example`, replace
`<MOONCAKE_METADATA_HOST>`, and mount the completed file at
`/cache/config/mooncake.json`.

The metadata and KV-transfer endpoints must not be Internet-accessible.

## 8. Create the ModelArts service

Follow [`configs/modelarts-units.md`](../configs/modelarts-units.md). Use the
same image, model mount, script mount, log mount, and
`MODELARTS_COHORT_ID` for all units. Set a different `GLM52_ROLE` for each
unit.

The startup script performs an SFS-based rendezvous, assigns deterministic
Prefill and Decode ranks, launches the recorded vLLM parameters, and starts the
vLLM Ascend load-balancing proxy on the entry Prefill pod.

## 9. Runtime configuration

Important Prefill settings in C6:

- DP4 × TP8 × EP; one rank per node;
- `max-model-len=256000`;
- `max-num-batched-tokens=8192`;
- `max-num-seqs=256`;
- `gpu-memory-utilization=0.95`;
- MTP1 and eager execution;
- FlashComm1 and DSA context-parallel optimization.

Important Decode settings in C6:

- DP8 × TP4 × EP; two ranks per node;
- `max-model-len=256000`;
- `max-num-batched-tokens=256`;
- `max-num-seqs=128`;
- `gpu-memory-utilization=0.95`;
- MTP3;
- `FULL_DECODE_ONLY` graph capture;
- MLAPO, shared-expert multistream, and recompute scheduling;
- Decode `HCCL_BUFFSIZE=2560`;
- no Decode Fused MC2 and no Dynamic EPLB.

Do not move A3-only variables into this A2 profile.

The archived C6 Prefill script still carried `ASCEND_A3_ENABLE=1`. This public
A2 template intentionally omits that A3-only environment variable while
preserving the validated C6 topology, batching, memory, communication, MTP,
and Decode optimization settings.

## 10. Acceptance

Do not accept the deployment from a green console label alone. Verify:

1. all eight nodes and every expected NPU worker are ready;
2. rank sets are exactly P0–P3 and D0–D3;
3. Mooncake and Ascend Store connectors initialize without transfer errors;
4. `/health` succeeds for every backend and the proxy;
5. non-streaming, streaming, reasoning, tool call, and tool-result continuation;
6. UTF-8 and usage accounting;
7. a bounded context smoke with `input + output <= 256,000`;
8. no fallback to another model;
9. no HCCL, EngineCore, NPU kernel, OOM, or repeated restart errors.

Formal capacity and performance testing is a separate workflow.

## 11. Recovery and rollback

For a distributed failure, stop test traffic, preserve all P/D logs and
ModelArts events, then restart the complete deployment rather than a single
rank. Retain the previous deployment version, image digest, scripts, model
revision, and known-good smoke evidence before every change.

If a candidate regresses correctness, stability, TTFT, or TPOT, stop it and
restore the complete known-good version before resuming traffic.

## 12. Known limitations

- ModelArts public-cloud resource names and A2 availability vary by region.
- The official image tag is mutable unless pinned by digest.
- A configured 256K context does not prove every input/output combination.
- Mooncake, Ascend Store, MTP, graph capture, and sparse operators are tightly
  coupled to the exact image and model revision.
- The recorded profile requires 64 dedicated A2 NPUs and is not a low-cost
  default.
