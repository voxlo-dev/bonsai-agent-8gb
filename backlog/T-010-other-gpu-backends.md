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

## What

Build with `-DGGML_VULKAN=ON` on a non-NVIDIA 8 GB+ GPU, start with the same flags, and record
load success, layers offloaded, KV types accepted and tok/s. Only if it is usable: make the
backend a `config.env` setting and document it.
