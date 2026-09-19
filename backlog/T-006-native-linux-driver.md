# T-006 — Verify apt's CUDA toolkit next to a native NVIDIA driver

- **Summary:** Check whether `nvidia-cuda-toolkit` breaks an installed native driver of another version
- **Category:** chore
- **Importance:** medium
- **Effort:** S
- **Depends on:** none

## Why

`nvidia-cuda-toolkit` pulls in `libnvidia-compute-*` at its own version. Under WSL2 the
loader prefers `/usr/lib/wsl/lib`, so it is harmless there. On native Linux with, say, driver
570 or 580 it may replace or shadow the userspace driver and cause "Driver/library version
mismatch". Native Linux is now listed as supported in `README.md` without having been run.

## What

On a native Ubuntu with a distro NVIDIA driver of a different version, run `./install.sh deps`
and observe what apt wants to change, then `nvidia-smi` and a server start. If it conflicts,
make `deps.sh` detect a native driver and install only the toolkit parts it needs, or
document installing CUDA from NVIDIA's repository instead.
