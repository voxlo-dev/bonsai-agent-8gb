# T-017 — Upstream the PTQ1_0 Vulkan decode to the fork

- **Summary:** Open the PR against PrismML-Eng/llama.cpp issue #185 with the T-016 patch, follow it through review, and drop `patches/vulkan/` once a pinned commit carries it
- **Category:** chore
- **Importance:** medium
- **Effort:** S
- **Depends on:** none (T-016 closed; patch in `patches/vulkan/0001-ptq1_0-table-decode.patch`)

## Why

T-016 rewrote the fork's PTQ1_0 Vulkan decode: 633 → 143 ms/token generation and 3.8 → 54 tok/s
prompt on an RX 570, bit-exact against the CPU backend. The fork's own issue
[#185](https://github.com/PrismML-Eng/llama.cpp/issues/185) has this kernel as committed-untested
and slow, open, no patch - so the result has a home there, and every Vulkan user of the fork gets
it. Until then this repo carries it in `patches/vulkan/`, applied by `build`, which is a second
thing to keep in step with `LLAMA_COMMIT`.

## What

1. Fork PrismML-Eng/llama.cpp on GitHub, `git am` the patch onto a branch off `1a07bfa` (the
   pinned commit), push. This is a manual step: the machine that built the patch and the machine
   with a GitHub login are not the same one here.
2. Open the PR with the text in `runs/T-016-ptq1_0-vulkan-decode/upstream-pr.md`: what was
   wrong, what changed, the `test-backend-ops` verification, the before/after table, what is
   left (a dedicated mat-vec kernel that keeps all five trits of a loaded word).
3. Answer review. Likely asks: numbers on a second card (the reporter of #185 has a 9070 XT
   and a 860M), whether the const table should be shared memory on NVIDIA too (it follows
   the IQ grids, so yes by precedent).
4. When merged: move `LLAMA_COMMIT` to a commit that carries it, re-run the CUDA build and
   the RX 570 measurement (`runs/T-016-ptq1_0-vulkan-decode/measure.sh`), delete
   `patches/vulkan/`, and drop the patch mentions from `README.md`, `AGENTS.md` and
   `docs/dev.md#other-gpu-backends`.

Not in scope: the dedicated PTQ1_0 mat-vec kernel (ceiling ~22 tok/s on the RX 570). Own
ticket if the batch use case wants more than 7 tok/s.
