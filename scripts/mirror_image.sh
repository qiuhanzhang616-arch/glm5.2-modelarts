#!/usr/bin/env bash
set -Eeuo pipefail

UPSTREAM_IMAGE=${UPSTREAM_IMAGE:-quay.io/ascend/vllm-ascend:v0.23.0}
SWR_REGISTRY=${SWR_REGISTRY:?Set SWR_REGISTRY}
SWR_ORGANIZATION=${SWR_ORGANIZATION:?Set SWR_ORGANIZATION}
SWR_REPOSITORY=${SWR_REPOSITORY:-glm52-vllm-ascend}
SWR_TAG=${SWR_TAG:-v0.23.0-a2}
TARGET="${SWR_REGISTRY}/${SWR_ORGANIZATION}/${SWR_REPOSITORY}:${SWR_TAG}"

docker pull "$UPSTREAM_IMAGE"
docker image inspect "$UPSTREAM_IMAGE" --format 'upstream={{index .RepoDigests 0}}'
docker tag "$UPSTREAM_IMAGE" "$TARGET"
docker push "$TARGET"
printf 'Pin the SWR digest reported after push; do not deploy a mutable tag alone.\n'
