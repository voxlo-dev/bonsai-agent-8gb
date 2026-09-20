# T-010 — Try the fork's non-CUDA backends

- **Summary:** Test whether Vulkan (AMD/Intel) or ROCm runs the model at usable speed
- **Category:** spike
- **Importance:** low
- **Effort:** M
- **Depends on:** none

## Why

The fork carries `PTQ1_0` kernels for Vulkan, ROCm/HIP (RDNA configs), Metal and the CPU, so
NVIDIA is a constraint of this setup, not of the model. Unknown: whether flash attention with
the mixed `q8_0`/`q4_0` KV cache works there, and at what speed.

The check below was done against an AMD RX 570 (Polaris10/gfx803, 8 GiB VRAM, RADV). ROCm does
not support gfx803, so on that class of card the backend under test is Vulkan; a Vulkan build
needs `glslc`, the Vulkan headers and `libshaderc` next to the usual toolchain, but no CUDA and
no root.

## Feasibility, checked against the sources

Read at the pinned commit `1a07bfa`, before building anything:

- **PTQ1_0 has the full Vulkan pipeline set**, not just a dequantiser: `mul_mat_vec_ptq1_0_f32_f32`
  and `_f16_f32` (generation), the scalar `matmul_ptq1_0_f32` via `CREATE_MM` (the path a device
  without cooperative matrix takes, so prompt processing is covered), `dequant_ptq1_0`,
  `get_rows_ptq1_0`. Shaders in `ggml/src/ggml-vulkan/vulkan-shaders/ptq1_0.glsl` and
  `dequant_ptq1_0.comp`.
- **coopmat2 is missing for PTQ1_0 on purpose** — `dequant_funcs_cm2.glsl` carries no decoder and
  `vulkan-shaders-gen.cpp` skips cm2 generation for it. coopmat2 is NVIDIA-only, so this costs a
  non-NVIDIA device nothing.
- **Flash attention takes `q8_0` for K with `q4_0` for V.** `fa_kv_ok` in `supports_op` lists both
  and only requires BF16 to match on both sides, so `CTX`, `KV_K` and `KV_V` need no change. Its
  one hardware condition on the non-coopmat2 path is `subgroup_shuffle && subgroup_vote`.

What the RX 570 reports through `vulkaninfo`:

| | |
| --- | --- |
| subgroup | size 64, fixed; SHUFFLE and VOTE present — the flash-attention condition holds |
| 8-bit / 16-bit storage | both present, so `block_ptq1_0` is addressable |
| `shaderFloat16` | **false** |
| cooperative matrix | none, as expected for Polaris |
| max compute shared memory | 65 536 B |
| heaps | 7.75 GiB VRAM, 11.74 GiB GTT |

RADV reporting no fp16 arithmetic is not a blocker: the only place in the backend that reads
`device->fp16` is the `f32acc` choice for flash attention, which then accumulates in fp32. No
`supports_op` rejection depends on it.

## What

Build with `-DGGML_VULKAN=ON` on that box, start with the same flags, and record load success,
layers offloaded, KV types accepted and tok/s. Only if it is usable: make the backend a
`config.env` setting and document it.

Two things the sources cannot answer:

- **Speed.** gfx803 gets neither cooperative matrix nor fp16 accumulation. The 36 tok/s of the
  4060 Ti say nothing about it, and "usable" is exactly what this spike has to decide.
- **Whether it stays in VRAM.** 64k costs 7.75 GiB on CUDA, the VRAM heap here is 7.75 GiB, and
  fp32 flash-attention accumulation comes on top. RADV falls back to the 11.7 GiB GTT silently
  rather than failing, which runs weights over PCIe. Start at `PROFILE=display` (48k) and judge
  by tok/s, not by a VRAM reading.
