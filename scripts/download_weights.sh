#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

MODEL_ID=${MODEL_ID:-Eco-Tech/GLM-5.2-w4a8c8}
MODEL_DIR=${MODEL_DIR:?Set MODEL_DIR to the final shared model directory}
final=$(readlink -m -- "$MODEL_DIR")
parent=$(dirname -- "$final")
name=$(basename -- "$final")
staging="$parent/.${name}.partial.$$"

[[ "$final" != "/" ]] || { echo "MODEL_DIR must not be /" >&2; exit 2; }
[[ ! -e "$final" ]] || { echo "Refusing to overwrite $final" >&2; exit 2; }
command -v modelscope >/dev/null || {
  echo "Install ModelScope first: python3 -m pip install modelscope" >&2
  exit 2
}
mkdir -p "$parent" "$staging"
trap 'rm -rf -- "$staging"' EXIT
modelscope download --model "$MODEL_ID" --local_dir "$staging"

test -s "$staging/config.json"
test -s "$staging/quant_model_description.json"
find "$staging" -maxdepth 1 -name '*.safetensors' -size +1M | grep -q .
touch "$staging/.download-complete"
mv -- "$staging" "$final"
trap - EXIT
printf 'Model downloaded to %s. Record the ModelScope revision and SHA-256 manifest.\n' "$final"
