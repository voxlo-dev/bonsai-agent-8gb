#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
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
[[ -f "$MODEL_PATH.part" ]] && log "resuming an interrupted download" \
  || log "downloading $MODEL_FILE (~$((MODEL_DISK_MB / 1024)).$((MODEL_DISK_MB % 1024 * 10 / 1024)) GB) - interrupting is safe, the next run resumes"
# -# is the progress bar; -C - resumes a .part left by an interrupted run.
curl -fL --retry 3 -C - -# -o "$MODEL_PATH.part" "$url" \
  || die "download failed - run ./install.sh model again to resume from $MODEL_PATH.part"

log "verifying checksum (~30 s per 5 GB)"
echo "$MODEL_SHA256  $MODEL_PATH.part" | sha256sum -c --quiet - \
  || die "checksum mismatch: the file at $MODEL_PATH.part is not MODEL_SHA256 from config.env. Delete it and run ./install.sh model again; if it happens twice the pin and the remote file disagree"
mv "$MODEL_PATH.part" "$MODEL_PATH"
log "model ready at $MODEL_PATH"
