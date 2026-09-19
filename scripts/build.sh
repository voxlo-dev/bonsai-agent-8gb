#!/usr/bin/env bash
# Builds llama-server from the pinned PrismML fork: static, CUDA, all flash-attention KV type pairs.
# FORCE=1 rebuilds even when the pinned binary is already there.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

stamp="$LLAMA_DIR/build/.bonsai-commit"
if [[ -z "${FORCE:-}" && -x "$LLAMA_SERVER" && "$(cat "$stamp" 2>/dev/null)" == "$LLAMA_COMMIT" ]]; then
  log "llama-server at ${LLAMA_COMMIT:0:7} already built"
  exit 0
fi

has nvcc || die "nvcc not found - run ./install.sh deps"

log "fetching fork at ${LLAMA_COMMIT:0:7}"
mkdir -p "$LLAMA_DIR"
cd "$LLAMA_DIR"
[[ -d .git ]] || { git init -q; git remote add origin "$LLAMA_REPO"; }
git fetch -q --depth 1 origin "$LLAMA_COMMIT"
git checkout -q --force FETCH_HEAD

arch="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '.')"
[[ "$arch" =~ ^[0-9]+$ ]] || arch=native

compilers=()
if has g++-13; then
  export CC=gcc-13 CXX=g++-13
  compilers=(-DCMAKE_CUDA_HOST_COMPILER="$(command -v g++-13)")
fi

log "configuring (CUDA arch $arch)"
cmake -B build -S . \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$arch" "${compilers[@]}" \
  -DGGML_CUDA_FA_ALL_QUANTS=ON \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=ON -DLLAMA_CURL=OFF \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
  >/dev/null

log "building llama-server (takes a while)"
nice -n "${NICE:-10}" cmake --build build --target llama-server -j "$(nproc)"

echo "$LLAMA_COMMIT" > "$stamp"
"$LLAMA_SERVER" --version 2>&1 | tail -2
