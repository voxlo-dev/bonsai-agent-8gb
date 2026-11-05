# LFM2.5-24B-A2B

**Unsupported until benched:** a candidate, not offered by `install.sh`. Its campaign row
([`backlog/bench-campaign.md`](../backlog/bench-campaign.md)) tunes it (`bench-optimize` stage 2),
then benches it; the hope is that it replaces Bonsai.

Liquid AI's reasoning MoE: architecture `lfm2moe`, 40 layers of which 10 attention and the rest
short convolutions, layers 0-1 dense, 64 experts with 4 active (2B parameters per token), a 131k
native window, text only. It always thinks, and calls tools in Python syntax between
`<|tool_call_start|>` and `<|tool_call_end|>` ([model card](https://huggingface.co/unsloth/LFM2.5-24B-A2B-GGUF)).
The first model of an architecture no shipped one has (T-079), on the path in
[dev.md#new-architectures](dev.md#new-architectures).

## The tree

Unsloth's (`models/trees/unsloth.env`), already built for both Qwen models: it loads `lfm2moe` and
parses LFM2's tool calls, so `las check lfm25-24b` passes with the GGUF's own template and no file
in `templates/`. Its patch reaches only Qwen3.8-Flash's sparse attention. CUDA only; Vulkan is not
measured.

## Settings

- **GGUF:** `unsloth/LFM2.5-24B-A2B-GGUF` UD-Q4_K_XL at `aacc778`, 14.9 GB, its sha256 the LFS pin.
  Experts 352 MiB per MoE layer (13.1 GiB in all), everything else 807 MiB.
- **Sampling:** the card's: temperature 0.1, top-k 50, repetition penalty 1.05 (`SERVER_ARGS`), no
  top-p. The template has no `reasoning_effort`, so `EFFORT` is empty.
- **KV:** q8_0/q8_0 as for the Qwen models, not measured against f16 for this cache. With 10
  attention layers it stays small at the full window.

## Window

`configs/lfm25-24b.env`: 131k, the experts of 27 of 38 MoE layers in RAM (`CPU_MOE=29`), ubatch
2048, Qwen3.6's budget. At `CPU_MOE=26` the compute buffer (834 MiB at ubatch 2048) did not fit.
Fit at 29 (2026-11-05): 98 304 tokens in 67 s, 589 MiB free afterwards, so one more expert layer
on the card (`CPU_MOE=28`) is within the 200 MiB margin by arithmetic - stage 2's to measure, with
its speed. Logs: `runs/T-079-lfm25/`.
