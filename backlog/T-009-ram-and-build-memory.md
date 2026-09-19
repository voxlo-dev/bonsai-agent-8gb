# T-009 — Measure system RAM needs

- **Summary:** Find the minimum RAM for building (nvcc at -j nproc) and for serving
- **Category:** chore
- **Importance:** low
- **Effort:** S
- **Depends on:** none

## Why

`README.md` states no RAM requirement. The build runs nvcc with `-j $(nproc)`, which can run
out of memory on small machines or a default WSL2 memory limit (half of host RAM), and the
server mmaps the 5.6 GB model.

## What

Record peak RSS of the build and of `llama-server` after load (`/usr/bin/time -v`). Add the
requirement to `README.md`; if the build OOMs, cap `-j` by available memory in `build.sh`.
