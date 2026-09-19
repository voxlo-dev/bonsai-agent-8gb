# T-007 — Verify the build on an RTX 50xx

- **Summary:** Build and run on Blackwell (sm_120) with CUDA >= 12.8 from NVIDIA's repository
- **Category:** chore
- **Importance:** low
- **Effort:** S
- **Depends on:** none

## Why

apt's CUDA 12.4 cannot target `sm_120`; `build.sh` now stops early with that message. Whether
the fork's `PTQ1_0` kernels then build and run correctly with CUDA 12.8+ and gcc 14/15 is
unknown, and the gcc-13 preference in `build.sh` may not be needed there.

## What

On an RTX 50xx: install CUDA >= 12.8 from NVIDIA, run `./install.sh build model`, start the
server, and record generation speed. Document the install route in `docs/dev.md#toolchain`.
