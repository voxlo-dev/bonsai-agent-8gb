# T-016 — Rewrite the PTQ1_0 Vulkan decode

- **Summary:** Replace the per-element trit decode in the fork's Vulkan shaders with a byte-to-five-trits lookup and word loads, verify against the CPU reference, measure on the RX 570
- **Category:** spike
- **Importance:** low
- **Effort:** M
- **Depends on:** none (T-010 closed; its numbers are in `docs/dev.md#other-gpu-backends`)

## Why

T-010 ended at 1.65 tok/s on the RX 570 with everything configurable exhausted - Mesa 26.1.2,
`RADV_PERFTEST=nogttspill`, clocks forced. The same card runs Qwen2.5-3B Q4_K_M at 121 GB/s
effective; at that per-byte efficiency the 5.4 GB PTQ1_0 model would do ~22 tok/s. It does 1.65,
so the kernel is ~14x worse per byte than Q4_K_M's, and the reason is visible in the source:

- `dequant_funcs.glsl` (mat-vec, generation): `dequantize4` calls `ptq1_0_trit` four times.
- `mul_mm_funcs.glsl` (mat-mat, prompt): eight calls per 8-element group.
- `ptq1_0.glsl`: each call is one byte load, a three-way branch, and a loop of up to 4
  dependent multiply-mask steps (`v = (v*3) & 0xFF`).

Per 128-element block that is 128 byte loads (`buffer_load_ubyte` each on GCN), 128 branches,
~320 serial ops. Q4_0 loads one word per four elements and shifts. It also explains why `mclk`
never ramps: the loads hit cache, so the DPM governor sees no memory traffic.

The fork's own issue [#185](https://github.com/PrismML-Eng/llama.cpp/issues/185) has this
kernel as committed-untested and slow, open, no patch. A result here has a home there.

## What

1. Generate a 256-entry table byte -> five 2-bit trits from the reference recurrence in
   `ggml-quants.c`, so it is bit-exact by construction. Put it in shared memory (or a
   `const` array) in `ptq1_0.glsl`.
2. Rewrite `dequantize4` to load one 32-bit word (the four bytes are adjacent and 4-aligned
   when `iqs` is a multiple of 4, for `e < 80`; handle the `qs[16..23]` and `qh` ranges
   likewise), one range branch, four table lookups, shifts.
3. Same in `mul_mm_funcs.glsl` for the prompt path.
4. Correctness: `test-backend-ops -o MUL_MAT -b Vulkan0` (default mode compares against the
   CPU backend). Run it before touching anything to have the baseline pass, then after.
5. Measure with `runs/T-010-vulkan-rx570/measure-forced.sh` (16k, comparable to 633 ms/token
   at `auto` clocks with nogttspill) and at 48k. Prompt speed too - that is the mul_mm path.
6. If it holds: patch to the fork against #185; numbers into `docs/dev.md#other-gpu-backends`.

Expected: 3-5x on the decode, so 4-8 tok/s if decode dominates. Ceiling ~22. Not 36, so the
NVIDIA requirement stays regardless - this is about whether the box becomes usable for small
things, and about the upstream patch.

Not in scope: an integer-dot (`mul_mat_vecq`) path for PTQ1_0 - Polaris lacks the hardware
instruction anyway - and the CPU kernel, which is `_generic` on every arch.
