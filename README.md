# GLM-5.2 on ModelArts Standard

Reusable Huawei Cloud ModelArts Standard deployment assets for
**GLM-5.2-w4a8c8** on Ascend A2.

This repository is intentionally separate from
[GLM-5.3-Flash](https://github.com/qiuhanzhang616-arch/glm53-flash-modelarts).
The two models use different images, weights, topology, MTP settings, context
handling, and operational procedures.

The primary profile here reproduces a recorded 64-NPU, 1M-context,
prefill/decode-disaggregated baseline:

- 4 Prefill nodes × 8 A2 NPUs, DP4 × TP8
- 4 Decode nodes × 8 A2 NPUs, DP4 × TP8
- Mooncake + Ascend Store KV transfer
- 1,048,576 configured context tokens
- Prefill MTP1 and Decode MTP3
- Automatic prefix caching
- Decode-only graph capture on Decode ranks

Start with [the deployment guide](docs/deployment-guide.md).

## Official sources

- vLLM Ascend GLM-5.2 guide:
  <https://docs.vllm.ai/projects/ascend/en/main/tutorials/models/GLM5.2.html>
- Official A2 image: `quay.io/ascend/vllm-ascend:v0.23.0`
- ModelScope W4A8C8 weights:
  <https://www.modelscope.cn/models/Eco-Tech/GLM-5.2-w4a8c8>
- Huawei Cloud ModelArts Standard:
  <https://support.huaweicloud.com/intl/en-us/modelarts/index.html>

This is a deployment template, not a throughput or availability guarantee.
Every value enclosed in angle brackets must be supplied by the deploying
Huawei Cloud project.
