#!/usr/bin/env bash
# Installs the build toolchain via apt. Needs sudo, so run it from a real terminal.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

has nvidia-smi || die "nvidia-smi not found - install the NVIDIA driver on Windows (WSL gets it from there)"

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
