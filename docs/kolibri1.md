# Kolibri-1, 78B

`MODEL=kolibri1`, or the `kolibri-server`, `kolibri-pi` and `kolibri-studio` commands, serve
[Kolibri-1](https://huggingface.co/Aleph-Alpha/Kolibri-1), Aleph Alpha's reasoning MoE for German
and English (Apache-2.0): 78B, 384 experts of which 6 are active plus one shared expert, 3.5B
parameters per token, 50 layers. Every routed expert stays in RAM, so like Qwen3.8-Flash it needs a
64 GB machine; it decodes at Qwen3.6's speed. Measured for load and speed only (2026-10-05): its
window is not filled, and its one agent session copied another model's work (T-051).

**What it needs.** [Hob-forge/Kolibri-1-GGUF](https://huggingface.co/Hob-forge/Kolibri-1-GGUF),
`Q4_K_M`, one file of 47.5 GB: routed experts 42.6 GiB, the rest 1.6 GiB. An independent conversion
from Aleph Alpha's FP8 checkpoint without an importance matrix; its author reports 63 of 67 top-1
tokens and a mean KL of 0.013 against a float64 reference. The experts sit in the page cache
(~46 GB); `preflight` asks for 49 GB of RAM. Text only: there is no vision projector, and
`VISION=1` is refused.

## The tree

No llama.cpp release knows the `kolibri1` architecture (feature request ggml-org/llama.cpp#29922).
Unpatched, the trees here stop at `unknown model architecture: 'kolibri1'`, Unsloth Studio's own
included. The GGUF's repository ships `kolibri1-llama.cpp.patch`, four commits against mainline
`836d571` (release b11381), kept as `patches/kolibri1/0001-kolibri1.patch` and applied by `build`
on either backend:

- **Router:** experts are selected on `logits + expert_bias` and weighted by the unbiased
  `sigmoid(logits)`. llama.cpp's DeepSeek-V3 router selects on `sigmoid(logits) + bias`, which
  picks other experts (top-1 10 of 67 in the author's test), so the patch adds a gating mode.
- **Attention:** GQA, 48 query and 4 KV heads with per-head q/k RMSNorm; four sliding-window layers
  (513 tokens, RoPE) to one full-attention layer without positional encoding.
- **Norms:** sandwich norms around attention and MoE.

The patch touches model code only (graph, arch tables, the converter, a test), and applies to the
pinned commit with `git apply`. On CUDA the new router has no fused kernel and runs the unfused
MoE path.

**The build number is set by hand** (`LLAMA_CMAKE_ARGS=-DLLAMA_BUILD_NUMBER=11381`). `build`
fetches one commit, so llama.cpp counts a build number of 1 and fetches its web UI from the
Hugging Face bucket under that number, which does not exist: the server then answers every path
but the API with 404. b11381 is the UI released with this commit.

## Settings

| Setting | Why |
| --- | --- |
| `CPU_MOE` 50 | every routed expert in RAM; the card holds 1.6 GiB of weights plus the cache |
| `KV_K`/`KV_V` `q8_0` | as for both Qwen models; KV quality is not measured for this model |
| `EFFORT` medium | the template reads `reasoning_effort` (`none`, `low`, `medium`, `high`, its default); medium as for Bonsai and Qwen3.8-Flash |
| sampling 1.0 / 0.97 / 128 | temperature, top-p and top-k from the model card, which the patch was tested with. `kolibri-studio` passes top-k 100, the most Unsloth Studio accepts; at top-p 0.97 ranks past 100 carry almost no mass |
| no speculative decoding | no MTP head, and no small model shares its 128k tokenizer |

## Window and profiles

Only 10 of the 50 layers keep the whole window; the other 40 keep 513 tokens. At `q8_0` the cache
is ~10.6 KB per token, ~1.4 GB at 131k and ~2.8 GB at the trained 262k. Both profiles are 131k,
every expert in RAM, ubatch 2048, by arithmetic from one measurement: 3 362 MiB at 32k, `f16`
cache, ubatch 512. That leaves ~2.5 GB on a dedicated card, which a filled window
([AGENTS.md](../AGENTS.md#working-on-it)) has to confirm before expert layers move onto it or the
window grows. The budget is Qwen3.6's: the same speed, by the rules in
[agent.md](agent.md#context-budget).

## Speed

| Run (7800X3D, 64 GB, RTX 4060 Ti, native Linux) | Prompt | Generation |
| --- | --- | --- |
| CPU only, 8 threads, 8k window, 57-token prompt | 25 tok/s | 20.1 tok/s |
| CUDA, every expert in RAM, 32k, `f16` cache | | 44 tok/s |

Decode reads 6 experts x 50 layers x ~2.4 MB = ~0.71 GB per token from RAM and ~1.7 GB from the
card. At ~60 GB/s for dual-channel DDR5 (not measured on this machine) and the card's 280 GB/s
([performance.md](performance.md#the-roofline)) that is ~18 ms, a ceiling of ~55 tok/s: 44 is
~80 % of it. An expert layer on the card saves ~2 % of the RAM traffic for ~0.85 GiB of VRAM, so the
~2.5 GB the profile leaves buy a few percent at most.

## Open

The first agent session was invalid: it copied another model's result and handed it in as its
own ([agent-sessions.md](agent-sessions.md#k-kolibri-1-copied-b2)). T-051: fill the window with `nvidia-smi` alongside, the expert layers that fit next to it, prompt
speed at depth, and whether llama.cpp's default 8 GB prompt cache in RAM (`--cache-ram`) pushes
experts out of the page cache, as it does for Qwen3.8-Flash. Then an agent session.
