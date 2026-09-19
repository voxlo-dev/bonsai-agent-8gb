#!/usr/bin/env bash
# Puts the pinned GGUF at MODEL_PATH: links it from the Hugging Face cache when present, downloads it otherwise.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ -f "$MODEL_PATH" ]]; then
  log "model present: $MODEL_PATH"
  exit 0
fi
mkdir -p "$(dirname "$MODEL_PATH")"

cached="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${MODEL_REPO//\//--}/snapshots/$MODEL_REV/$MODEL_FILE"
if [[ -f "$cached" ]]; then
  log "linking from Hugging Face cache"
  ln -s "$(readlink -f "$cached")" "$MODEL_PATH"
  exit 0
fi

url="https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REV/$MODEL_FILE"
log "downloading $MODEL_FILE (~6 GB)"
curl -fL --retry 3 -C - -o "$MODEL_PATH.part" "$url"

log "verifying checksum"
echo "$MODEL_SHA256  $MODEL_PATH.part" | sha256sum -c --quiet - || die "checksum mismatch - delete $MODEL_PATH.part and retry"
mv "$MODEL_PATH.part" "$MODEL_PATH"
