# Ornith-1.5-35B-A3B

**Supported, offered at 32 GB beside Qwen3.6** ([README](../README.md#which-model)): tuned by
`bench-optimize` to stage 2 and benched in tier 2 (`bench.md#ornith-15-35b-in-tier-2`).
Never recommended over Qwen3.6, which stays the 32 GB default: Ornith is the better agent with less
thinking and the only model here to pass the hallucination tasks, Qwen3.6 the better chat
assistant, in German especially. Which one is a matter of taste.

Deep Reinforce's self-improved coding agent
([model card](https://huggingface.co/ornith-ai/Ornith-1.5-35B-A3B)), a fine-tune with Qwen3.6-35B-A3B's
architecture: `qwen35moe`, 40 layers of which every fourth attends and the rest are gated delta-net,
256 experts with 8 active (~3B parameters per token), one MTP layer, a 262k native window, a
vision projector of its own.

## The tree

Qwen3.6's: Unsloth's tree on CUDA (`models/trees/unsloth.env`), built and measured with this
architecture and its MTP drafting ([qwen36.md](qwen36.md#one-tree-for-both-qwen-models)). Nothing of
it is Ornith's own, so a move of that pin re-tests Ornith with the Qwen models. CUDA only.

## Settings

- **GGUF:** `ornith-ai/Ornith-1.5-35B-A3B-GGUF` Q4_K_M at `1239361`, 21.7 GB, its sha256 the LFS
  pin; the only quant below Q5_K_M the repo publishes. Experts 466 MiB per layer (18.7 GiB in all),
  everything else 1.6 GiB, a gigabyte less than Qwen3.6's UD-Q4_K_XL.
- **Template:** the GGUF's own, which renders every reasoning block it is given; the server's
  `--no-reasoning-preserve` still drops those before the last user message, as for Qwen3.6.
  `las check ornith-35b` passes with it.
- **Sampling:** the card's for its agent benchmarks: temperature 1.0, top-p 0.95, with the GGUF's
  top-k 20. The card advises 0.6 for general tasks; unmeasured here.
- **KV:** q8_0/q8_0 as Qwen3.6, whose cache this is ([context-window.md](context-window.md#kv-cache-quality));
  not measured against f16 for these weights. f16 is untried.
- **MTP:** on (`draft-mtp`), as for Qwen3.6.
- **Vision:** its projector is pinned (`mmproj-Ornith-1.5-35B-BF16.gguf`, 0.9 GB) and loads with
  `VISION=1`; not measured.

## Window

`configs/ornith-35b.env`: 131k with Qwen3.6's budget, the experts of 37 of 40 layers in RAM, ubatch
2048. Fit: 98 304 tokens in 113 s, 556 MiB free. 36 layers leaves 58 MiB, and nothing below starts
at ubatch 2048 (the MTP context's compute buffer finds no room). Ubatch 1024 fits one layer more for
prompts read ~1.5x slower, and no decode gain beyond one repeat's noise. Larger windows are
untried: Qwen3.6's 262k needed V at q4_0. The sweep: `bench.md#ornith-15-35b-optimized`.
Logs: `runs/T-082-ornith-opt/`.

## RAM

VmRSS 20.3 GB while serving, 18.4 GB of it file-backed, nearly all the mapped GGUF
(`runs/T-082-ornith-opt/ram.sh`): `MODEL_RAM_MB` 21 000, so a 32 GB machine passes preflight.
