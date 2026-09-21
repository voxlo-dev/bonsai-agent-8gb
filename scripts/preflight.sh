#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Checks everything that would make a later step fail, before any of them spends half an hour:
# disk, RAM, the GPU driver for BACKEND, VRAM, the distro and Node. Reports every item, then
# exits once. install.sh runs it first; SKIP_PREFLIGHT=1 turns it off. Takes the step list as
# arguments so it only checks what is about to run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

steps=("$@")
((${#steps[@]})) || steps=(deps build model pi link)
runs() { local s; for s in "${steps[@]}"; do [[ "$s" == "$1" ]] && return 0; done; return 1; }

fails=0 warns=0
pass() { printf '   \033[1;32mok\033[0m    %s\n' "$*"; }
soft() { printf '   \033[1;33mwarn\033[0m  %s\n' "$*"; warns=$((warns + 1)); }
hard() { printf '   \033[1;31mfail\033[0m  %s\n' "$*"; fails=$((fails + 1)); }

# df needs a path that exists; walk up to the nearest one that does.
nearest() { local d="$1"; while [[ ! -d "$d" && "$d" != / ]]; do d="$(dirname "$d")"; done; printf '%s' "$d"; }
free_mb() { df -P -BM "$(nearest "$1")" 2>/dev/null | awk 'NR == 2 { sub(/M$/, "", $4); print $4 }'; }

log "preflight ($BACKEND, steps: ${steps[*]})"

# --- system -----------------------------------------------------------------
if [[ "$(uname -s)" != Linux ]]; then
  hard "this is $(uname -s), not Linux - under Windows use WSL2"
else
  distro="$( . /etc/os-release 2>/dev/null && printf '%s %s' "${NAME:-?}" "${VERSION_ID:-}" )"
  wsl=""; grep -qi microsoft /proc/version 2>/dev/null && wsl=" (WSL2)"
  case "${distro,,}" in
    ubuntu*26.04*|debian*13*) pass "system: ${distro:-unknown}$wsl" ;;
    ubuntu*|debian*)          soft "system: ${distro:-unknown}$wsl - measured on Ubuntu 26.04 (cuda) and Debian 13 (vulkan); deps may install a different toolchain version" ;;
    *)                        soft "system: ${distro:-unknown}$wsl - not Debian or Ubuntu, so 'deps' cannot install the toolchain; see the Requirements section of README.md" ;;
  esac
fi

# --- disk -------------------------------------------------------------------
need_home=0
runs build && need_home=$((need_home + 2000))
runs model && need_home=$((need_home + 5800))
runs pi    && need_home=$((need_home + 500))
if ((need_home > 0)); then
  have="$(free_mb "$BONSAI_HOME")"
  if [[ -z "$have" ]]; then
    soft "disk: cannot read free space for $BONSAI_HOME"
  elif ((have < need_home)); then
    hard "disk: $((have / 1024)) GB free at $BONSAI_HOME, needs ~$((need_home / 1024)) GB"
  else
    pass "disk: $((have / 1024)) GB free at $BONSAI_HOME, needs ~$((need_home / 1024)) GB"
  fi
fi
if runs deps && [[ "$BACKEND" == cuda ]] && ! has nvcc; then
  have_root="$(free_mb /usr)"
  if [[ -n "$have_root" ]] && ((have_root < 5400)); then
    hard "disk: $((have_root / 1024)) GB free on /usr, the CUDA toolkit from apt needs ~5.4 GB"
  else
    pass "disk: $((have_root / 1024)) GB free on /usr for the CUDA toolkit"
  fi
fi

# --- memory -----------------------------------------------------------------
avail_mb="$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null)"
if [[ -z "$avail_mb" ]]; then
  soft "RAM: cannot read /proc/meminfo"
elif ((avail_mb < 3000)); then
  hard "RAM: ${avail_mb} MB available - serving needs ~8 GB of headroom, see docs/dev.md#ram-and-build-memory"
elif ((avail_mb < 7500)); then
  soft "RAM: ${avail_mb} MB available - the model loads through mmap and peaks at 5.8 GB; the build falls back to fewer jobs"
else
  pass "RAM: ${avail_mb} MB available"
fi

# --- GPU --------------------------------------------------------------------
# Only 'deps' and 'build' need the driver here; 'model', 'pi' and 'link' work on a machine with
# no GPU at all, which is how a server on another host gets set up.
vram_total=0 vram_used=0
if ! runs deps && ! runs build; then
  log "skipping the GPU checks: no step in this run needs one"
else
case "$BACKEND" in
  cuda)
    if ! has nvidia-smi; then
      hard "driver: nvidia-smi not found - install the NVIDIA driver (under WSL2 on the Windows side)"
    elif ! out="$(nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits 2>&1)"; then
      hard "driver: nvidia-smi fails - ${out%%$'\n'*}"
    else
      IFS=',' read -r gname vram_total vram_used <<<"${out%%$'\n'*}"
      vram_total="${vram_total// /}" vram_used="${vram_used// /}"
      pass "GPU:${gname} (${vram_total} MiB)"
    fi
    if runs build && ! has nvcc && ! runs deps; then
      hard "toolchain: nvcc not found and 'deps' is not in this run - install CUDA >= 12.4 or run ./install.sh deps"
    fi
    ;;
  vulkan)
    if ! ls /dev/dri/renderD* >/dev/null 2>&1; then
      hard "driver: no /dev/dri/renderD* - the kernel driver (amdgpu) is not loaded"
    elif ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx render && [[ ! -r "$(ls /dev/dri/renderD* 2>/dev/null | head -1)" ]]; then
      hard "driver: no access to the render node - usermod -aG render $USER, then log in again"
    else
      pass "driver: render node present"
    fi
    for f in /sys/class/drm/card*/device/mem_info_vram_total; do
      [[ -r "$f" ]] || continue
      vram_total=$(( $(cat "$f") / 1024 / 1024 ))
      u="${f%_total}_used"; [[ -r "$u" ]] && vram_used=$(( $(cat "$u") / 1024 / 1024 ))
      break
    done
    if has vulkaninfo; then
      summary="$(vulkaninfo --summary 2>/dev/null || true)"
      device="$(sed -n 's/^[[:space:]]*deviceName *= *//p' <<<"$summary" | head -1 || true)"
      [[ -n "$device" ]] && pass "GPU: $device" || soft "GPU: vulkaninfo lists no device"
    fi
    if runs build && ! has glslc && ! runs deps; then
      hard "toolchain: glslc not found and 'deps' is not in this run - install the Vulkan SDK or run ./install.sh deps"
    fi
    ;;
esac

if ((vram_total > 0)); then
  if ((vram_total < 7600)); then
    hard "VRAM: ${vram_total} MiB - this setup needs 8 GB and does not run partially offloaded at usable speed"
  else
    pass "VRAM: ${vram_total} MiB total"
  fi
  # A desktop on this GPU takes 0.5-1.2 GB, which is exactly the headroom the 64k profile does
  # not have. See docs/dev.md#vram-budget.
  if ((vram_used > 400)) && [[ "$PROFILE" == dedicated ]]; then
    soft "VRAM: ${vram_used} MiB already in use - something (a desktop?) is on this GPU; the 'dedicated' profile leaves ~440 MiB spare. Use PROFILE=display, or move the display to an iGPU"
  fi
elif [[ "$BACKEND" == vulkan ]]; then
  soft "VRAM: cannot read it from sysfs - check by hand that the card has 8 GB"
fi
fi

# --- Node -------------------------------------------------------------------
if runs pi; then
  if ! has node; then
    hard "node: not found - pi needs Node.js >= 22.19"
  else
    nver="$(node --version 2>/dev/null | tr -d v)"
    if [[ -n "$nver" ]] && [[ "$(printf '%s\n' 22.19 "$nver" | sort -V | head -1)" != 22.19 ]]; then
      hard "node: v$nver is older than the required 22.19"
    else
      pass "node: v${nver:-?}"
    fi
  fi
fi

# --- port -------------------------------------------------------------------
if [[ "$SERVER_HOST" == 127.0.0.1 || "$SERVER_HOST" == localhost ]]; then
  if curl -sf --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    soft "port $PORT: something already answers there - if it is not bonsai-server, set PORT and re-run ./install.sh pi"
  fi
fi

# --- verdict ----------------------------------------------------------------
echo
if ((fails > 0)); then
  die "preflight: $fails problem(s) above must be fixed first - troubleshooting is in docs/dev.md#troubleshooting (SKIP_PREFLIGHT=1 goes ahead anyway)"
fi
((warns > 0)) && warn "preflight: $warns warning(s), continuing"
log "preflight passed"
