# T-005 — Settle which Linux systems `deps` supports

- **Summary:** Test `./install.sh` on Ubuntu 24.04, 22.04 and Debian 13, then support them or reject them early
- **Category:** decision
- **Importance:** medium
- **Effort:** M
- **Depends on:** T-004

## Why

`docs/dev.md#toolchain` states from package metadata, not from a run, that 24.04 (CUDA 12.0,
gcc <= 12) and 22.04 (CUDA 11.5, no `sm_89`, no `gcc-13`) fail. `deps.sh` does not check the
release, so the failure would surface deep in apt or nvcc.

Debian 13 is a third case and it fails earlier and differently. Measured on a Debian 13 host:
`apt-get` exists, so `deps.sh` passes its only system check, but `apt-cache policy
nvidia-cuda-toolkit` reports `Candidate: (none)` — the image enables the `main` component
alone, and the package is not in it. `deps.sh` would therefore fail inside `apt-get install`
with an apt error rather than at a check. On the same release the distro Node is 20.19.2,
below pi's floor of 22.19, so `pi` needs a source outside apt there as well.

That makes the ticket's real question broader than Ubuntu point releases: `has apt-get` is not
a sufficient test for "this system's apt can deliver the toolchain".

## What

Run the install on Ubuntu 24.04 and 22.04, and settle Debian 13 (enabling `contrib` may be all
it needs — untested, since without a GPU `deps` stops before it reaches apt). Then either
make them work (gcc-12 as host compiler, or CUDA from NVIDIA's apt repository) or have
`deps.sh` stop early with a clear message: check the release, and check that
`nvidia-cuda-toolkit` has a candidate before trying to install it. Update the requirements in
`README.md` either way.
