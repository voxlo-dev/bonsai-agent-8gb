# T-005 — Settle which Linux systems `deps` supports

- **Summary:** Test `./install.sh` on Ubuntu 24.04 and 22.04, then support them or reject them early
- **Category:** decision
- **Importance:** medium
- **Effort:** M
- **Depends on:** T-004

## Why

`docs/dev.md#toolchain` states from package metadata, not from a run, that 24.04 (CUDA 12.0,
gcc <= 12) and 22.04 (CUDA 11.5, no `sm_89`, no `gcc-13`) fail. `deps.sh` does not check the
release, so the failure would surface deep in apt or nvcc.

## What

Run the install on both releases. Then either make them work (gcc-12 as host compiler, or
CUDA from NVIDIA's apt repository) or have `deps.sh` stop early with a clear message on
releases below the tested one. Update the requirements in `README.md` either way.
