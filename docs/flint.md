# Flint Preview

**Supported, the ramp's quality pick for agent work at 32 GB** ([README](../README.md#which-model)):
tuned by `bench-optimize` to stage 2 and benched in tier 2 ([bench.md](bench.md#flint-in-tier-2)).
Offered beside Qwen3.6, never recommended: every agent task passed, but a third of the chat tasks
failed, more of them in German, so it is no multilingual chat assistant.

Recursive's MoE for coding agents: architecture `flint`, 49 layers of which 0-1 dense, 256 experts
with 6 active and 2 shared (~2.5B parameters per token), a 262k native window, text only. 35 of its
layers attend over a 513-token sliding window with RoPE; the other 14, without position encoding,
hold the full-window cache. It always thinks, and calls tools in GLM-style XML
(`<tool_call>name<arg_key>…</arg_key><arg_value>…</arg_value></tool_call>`)
([model card](https://huggingface.co/RecursiveSI/flint)). A new architecture, on the path in
[dev.md#new-architectures](dev.md#new-architectures).

## The tree

Mainline at release b12128 (`a01dff9`), in a dir of its own (`$LAS_HOME/llama.cpp-flint`):
`flint` arrived in ggml-org/llama.cpp#30928 (2026-10-21), after the mainline pin Qwen3.6's Vulkan
build shares, and is not in Unsloth's pinned tree, so neither of those pins moves. The release
number goes in by hand (`LLAMA_BUILD_NUMBER`), since the build fetches the web UI by it.
`las check flint` passes with the GGUF's own template, no file in `templates/`. CUDA only.

Not taken: CUDA's `pool1d_nchw_kernel`, the max-pool of the MoE amax rescaling before each expert
down-projection, scans a 512-wide row per thread. On an RTX 3090 it took 14 % of decode, and a
warp-per-row patch gave +15.5 % with unchanged output
([RecursiveSI/flint#25](https://huggingface.co/RecursiveSI/flint/discussions/25), 2026-10-28);
unmeasured here, a `bench-optimize` stage-5 ticket.

## Settings

- **GGUF:** `unsloth/flint-GGUF` UD-Q4_K_XL at `20468ed`, 25.1 GB, its sha256 the LFS pin. Experts
  468 MiB per MoE layer (21.5 GiB in all), everything else 1.9 GiB.
- **Sampling:** the card's: temperature 1.0, top-p 0.95, top-k 20. The template has no
  `reasoning_effort`, so `EFFORT` is empty.
- **KV:** f16/f16. Only 14 layers hold the full window (3.6 GiB at 131k), and q8_0 decoded 9-16 %
  slower from 65k on, for four expert layers more on the card ([bench.md](bench.md#flint-optimized)).
- **Reasoning history:** the card asks to keep `reasoning_content` in the conversation; the server
  runs `--no-reasoning-preserve` like every model here. Not measured either way.

## Window

`configs/flint.env`: 131k, the experts of 45 of 47 MoE layers in RAM (`CPU_MOE=47`), ubatch 2048,
Qwen3.6's budget. Fit: 98 304 tokens in 134 s, 439 MiB free. 196k fits at q8_0 for ~9 % less
decode at 65k; 262k does not load at ubatch 2048, its compute buffer grows to 1755 MiB, and
ubatch 1024 there is untried. The sweep: [bench.md](bench.md#flint-optimized). Logs:
`runs/T-082-flint-opt/`.

## RAM

VmRSS 24.4 GB while serving, nearly all of it the mapped GGUF (`runs/T-082-flint-opt/ram.sh`):
`MODEL_RAM_MB` 24 500, so a 32 GB machine passes preflight.
