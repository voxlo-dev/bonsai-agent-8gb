#!/usr/bin/env bash
# Installs the build toolchain via apt. Needs sudo, so run it from a real terminal.
# Tested on Ubuntu 26.04 only; other systems bring the toolchain themselves, see docs/dev.md#toolchain.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

has nvidia-smi || die "nvidia-smi not found - install the NVIDIA driver (under WSL2: on the Windows side)"
has apt-get || die "no apt-get - install CUDA >= 12.4, a matching gcc, cmake, git, python3 yourself, then: ./install.sh build model pi link"

# gcc-13 is the CUDA host compiler: nvcc 12.x rejects the newer distro default gcc
pkgs=(build-essential cmake ccache git curl python3 gcc-13 g++-13 nvidia-cuda-toolkit)
missing=()
for p in "${pkgs[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done

if ((${#missing[@]} == 0)); then
  log "toolchain complete"
else
  log "installing: ${missing[*]}"
  sudo apt-get update
  sudo apt-get install -y "${missing[@]}"
fi
nvcc --version | tail -1
