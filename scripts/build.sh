#!/usr/bin/env bash
# Builds llama-server from the pinned PrismML fork: static, CUDA or Vulkan (BACKEND), with the
# patches from patches/$BACKEND applied. FORCE=1 rebuilds even when the pinned binary is there.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The stamp names commit, backend and patch set, so a change to any of them triggers a rebuild.
patch_dir="$ROOT/patches/$BACKEND"
patches=()
[[ -d "$patch_dir" ]] && mapfile -t patches < <(ls "$patch_dir"/*.patch 2>/dev/null | sort)
want="$LLAMA_COMMIT $BACKEND $(cat "${patches[@]}" /dev/null | sha256sum | cut -c1-12)"
# An unpatched CUDA build keeps the old stamp format, so existing installs do not rebuild for nothing.
[[ "$BACKEND" == cuda && ${#patches[@]} -eq 0 ]] && want="$LLAMA_COMMIT"

stamp="$LLAMA_DIR/build/.bonsai-commit"
if [[ -z "${FORCE:-}" && -x "$LLAMA_SERVER" && "$(cat "$stamp" 2>/dev/null)" == "$want" ]]; then
  log "llama-server at ${LLAMA_COMMIT:0:7} ($BACKEND) already built"
  exit 0
fi

case "$BACKEND" in
  cuda)   has nvcc  || die "nvcc not found - run ./install.sh deps" ;;
  vulkan) has glslc || die "glslc not found - run ./install.sh deps" ;;
esac

log "fetching fork at ${LLAMA_COMMIT:0:7}"
mkdir -p "$LLAMA_DIR"
cd "$LLAMA_DIR"
[[ -d .git ]] || { git init -q; git remote add origin "$LLAMA_REPO"; }
git fetch -q --depth 1 origin "$LLAMA_COMMIT"
git checkout -q --force FETCH_HEAD

# The checkout above is clean, so the patches always apply to the pinned tree, never on top
# of themselves. Moving LLAMA_COMMIT means re-checking that they still apply.
for p in "${patches[@]}"; do
  log "applying patches/$BACKEND/$(basename "$p")"
  git apply --check "$p" || die "patch does not apply to ${LLAMA_COMMIT:0:7} - the pin moved without rebasing patches/$BACKEND"
  git apply "$p"
done

launchers=()
has ccache && launchers=(-DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache)

backend_flags=()
case "$BACKEND" in
  cuda)
    arch="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')" || true
    [[ "$arch" =~ ^[0-9]+$ ]] || arch=native

    # nvcc before 12.8 does not know Blackwell (sm_120, RTX 50xx) and fails mid-build
    nvcc_ver="$(nvcc --version | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p')"
    if [[ "$arch" =~ ^[0-9]+$ ]] && ((arch >= 100)) && [[ "$(printf '%s\n' 12.8 "$nvcc_ver" | sort -V | head -1)" != 12.8 ]]; then
      die "GPU arch sm_$arch needs CUDA >= 12.8, found nvcc $nvcc_ver - see docs/dev.md#toolchain"
    fi

    has ccache && launchers+=(-DCMAKE_CUDA_COMPILER_LAUNCHER=ccache)
    if has g++-13; then
      export CC=gcc-13 CXX=g++-13
      backend_flags+=(-DCMAKE_CUDA_HOST_COMPILER="$(command -v g++-13)")
    fi
    backend_flags+=(-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$arch" -DGGML_CUDA_FA_ALL_QUANTS=ON)
    log "configuring (CUDA arch $arch)"
    ;;
  vulkan)
    # The Vulkan flash attention takes mixed KV types as is; the shaders are compiled by glslc
    # at build time (vulkan-shaders-gen), which is where the patches from patches/vulkan land.
    backend_flags+=(-DGGML_VULKAN=ON)
    log "configuring (Vulkan)"
    ;;
esac

cmake -B build -S . \
  -DCMAKE_BUILD_TYPE=Release \
  "${backend_flags[@]}" \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=ON -DLLAMA_CURL=OFF \
  "${launchers[@]}" \
  >/dev/null

log "building llama-server (takes a while)"
nice -n "${NICE:-10}" cmake --build build --target llama-server -j "$(nproc)"

echo "$want" > "$stamp"
"$LLAMA_SERVER" --version 2>&1 | tail -2
