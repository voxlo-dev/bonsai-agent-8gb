# Second model: Qwen3.6-35B-A3B

`MODEL=qwen36-35b` serves Qwen3.6-35B-A3B instead of Bonsai. It is a mixture-of-experts model with
35B parameters, 3B of them active per token. The experts live in system RAM; the card holds
attention, the shared expert, the KV cache and the MTP head. **Experimental**: measured for speed
and KV quality, not yet in an agent session. Bonsai stays the default.

It is also the slot for Qwen 4. If a Qwen 4 35B-A3B ships, it becomes a model file of its own plus
one re-run of the measurement below. The code does not change.

## Why a MoE, and why this one

The study behind this repo ([model-comparison.md](model-comparison.md)) found Qwen3.6-35B-A3B the
best agent *by process* on an 8 GB card, but its result was broken. Bonsai answers that with a
dense 27B squeezed into VRAM. A MoE answers it the other way: with 3B active parameters the experts
are cheap to run from RAM, which frees the card for what Bonsai is short of, the window. Its KV
cache is also small. 40 layers, every 4th full attention, 2 KV heads of 256 dims: 10.6 MiB per 1k
tokens at `q8_0`/`q8_0`, against Bonsai's 34.

| Pin | Value |
| --- | --- |
| Model | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` rev `5bc3e238d916f48a861bac2f8a1990a0e9b7e98d`, `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`, 22 663 387 424 bytes |
| sha256 | `0b21525e972670ed59e1812e170b27c26355381f0656ecc4e25617ece7dac58b` |
| llama.cpp | mainline, ggml-org `8212c7802455255460ab8e18fc34754560031b34` (2026-09-24), in its own `$BONSAI_HOME/llama.cpp-mainline` |

The `-MTP-` repo carries the same weights as `unsloth/Qwen3.6-35B-A3B-GGUF` plus one MTP layer
(`blk.40.nextn.*`), which the fork ignores and mainline drafts with. Not
`empero-ai/Qwen3.8-35B-A3B-Distill`: despite its name it is a community fine-tune of this same
model.

## What was measured

T-034, 2026-09-24 to 26. Same machine, corpus and prompts as Bonsai's measurement in
[context-window.md](context-window.md). `CPU_MOE` is the number of layers whose experts stay in
RAM (`--n-cpu-moe`, 40 = all); `ub` is `-b`/`-ub`. K is `q8_0` throughout. tg and pp in tok/s,
`@43k` a 42 803-token prompt, `@112k` 112 032. Repeated configs varied < 2 %.

Fork `1a07bfa`:

| ctx | `CPU_MOE` | V | ub | VRAM | tg @1k | tg @43k | pp @43k | tg @112k | pp @112k |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 262 144 | 40 | q4_0 | 4096 | 7 312 | 29.9 | 26.1 | 1 012 | 21.9 | 903 |
| 262 144 | 40 | q8_0 | 2048 | 6 728 | 29.6 | 26.6 | 687 | 22.1 | 623 |
| 262 144 | 36 | q8_0 | 512 | 7 780 | 31.2 | 27.7 | 261 | 23.4 | 246 |
| 131 072 | 35 | q8_0 | 4096 | 7 812 | 32.0 | 28.5 | 1 090 | 23.7 | 962 |
| 131 072 | 33 | q8_0 | 512 | 7 464 | 32.9 | 29.5 | 282 | 24.2 | 265 |
| 65 536 | 33 | q8_0 | 4096 | 7 518 | 33.7 | 29.3 | 1 124 | – | – |
| 65 536 | 31 | q8_0 | 512 | 7 558 | 34.4 | 30.0 | 296 | – | – |

Mainline `8212c78`; `+mtp` is `--spec-type draft-mtp` at the default draft length 3:

| ctx | `CPU_MOE` | V | ub | VRAM | tg @1k | tg @43k | pp @43k | tg @112k | pp @112k |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 131 072 | 36 | q8_0 | 4096 | 7 540 | 29.7 | 27.7 | 1 090 | 23.5 | 947 |
| 262 144 | 40 | q4_0 | 4096 | 7 568 | 29.1 | 25.9 | 1 017 | 22.0 | 899 |
| 262 144 +mtp | 40 | q4_0 | 1024 | 7 396 | 40.9 | 33.0 | 409 | 30.0 | 370 |
| **131 072 +mtp** | **38** | **q8_0** | **2048** | **7 374** | **42.8** | **33.6** | **700** | **29.5** | **611** |
| 65 536 +mtp | 35 | q8_0 | 2048 | 7 380 | 40.7 | 32.2 | 734 | – | – |

The corpus prompts continue C++ code, so what MTP drafts there is not typical output. The fair
number is **natural output**: three chat prompts with thinking, 1 024 tokens each, at the shipped
config with the model card's sampling. That gives **29.0 tok/s without MTP and 38.7-44.7 with it**, with 63-80 % of drafts accepted.

## What it decides

**Mainline with MTP, not the fork.** Without MTP the two builds are equal: at 131k, tg 27.7 against
28.5, with one expert layer fewer on the card for mainline, which needs ~120 MiB more VRAM; pp is
the same. MTP adds 33-54 % on natural output and still 25 % at 112k of context. It costs ~1.66 GB of
VRAM, paid in expert layers and ubatch, which puts pp at ~700 instead of ~1 050. The fork cannot
draft at all. This is also the path a Qwen 4 will need: mainline knows `qwen4exp` (the architecture
of `Qwen/Qwen3.8-Flash-Next`), the fork does not.

**131 072 tokens, `q8_0`/`q8_0`.** With MTP, tg at 43k is 32.2-33.6 across every window from 65k to
262k, so speed does not pick the window. The KV cache does. 262k needs V at `q4_0` to fit, and
Qwen's cache takes that badly at depth ([context-window.md](context-window.md#kv-cache-quality)).
262k also needs ub 1024, and its pp of ~400 turns a compaction that re-reads 100k of kept context
from ~3 minutes into ~4.5.

**`UB` 2048.** The default ubatch of 512 reads prompts at ~250 tok/s with the experts in RAM; 4096
reads them at ~1 050 for 1.3 GB more VRAM and no tg cost. With MTP on the card, 2048 is what fits,
at ~700.

**`CPU_MOE` 38.** One expert layer on the card costs ~470 MiB and buys ~0.8 tok/s. 38 leaves the
shipped config at 7 374 MiB, ~480 below the edge ([context-window.md](context-window.md#the-edge-you-cannot-see)).
37 would sit at ~7 840, too close.

**Thinking in the prompt** behaves as with Bonsai: `--reasoning-preserve` renders every earlier
thinking block, `--no-reasoning-preserve` only those after the last user message. Mainline has the
same switch, so `PRESERVE_THINKING` works unchanged. The template reads `enable_thinking` and
`preserve_thinking`, not `reasoning_effort`, so `EFFORT` is empty for this model.

**Sampling** is Bonsai's: temperature 1.0, top-p 0.95, top-k 20, min-p 0. That is what Qwen used for
its own agent benchmarks (SWE-bench, Terminal-Bench, per the model card), and it keeps sampling out
of the comparison between the two models. The card's 0.6 "for precise coding" is untested here.

**RAM: ~24 GB resident, ~28 GB total.** RSS was 20-23.5 GB across the configs (the model is
mmapped), and available memory fell by another 2-3 GB of page cache during a run. 30.9 GB in WSL2
was enough, with ~25 GB still available. WSL2 sees half the Windows RAM by default, so a 32 GB PC
has to raise `memory=` in `%UserProfile%\.wslconfig`; `preflight` checks for it.

## The profiles

| | `dedicated` | `display` |
| --- | --- | --- |
| ctx | 131 072 | 131 072 |
| `CPU_MOE` / `UB` | 38 / 2048 | 40 / 2048 |
| VRAM | 7 374 MiB, measured | ~6 430 MiB, **by arithmetic**, which leaves ~1 GB for a desktop. Verify once |
| `BUDGET` / `MAX_TOKENS` / `RESERVE_TOKENS` / `KEEP_RECENT_TOKENS` | 16384 / 32000 / 32000 / 24000 | the same |

The budget is a starting point, not a measurement. It follows the rules in
[dev.md](dev.md#context-budget): `RESERVE_TOKENS` >= `BUDGET` + a ~4k tool call + pi's 4096 clamp,
and `KEEP_RECENT_TOKENS` at a real cost of 1.4-2x (~48k) is far below the 99k trigger. `BUDGET` is
twice Bonsai's because the study measured this model at 91 % reasoning share. The agent session in
T-034 phase 3 is what confirms or moves it.

Not tried: draft lengths other than 3, `UB` 1536 or 3072, `f16` for the cache (at 131k it costs
~1.3 GB more, three expert layers or the ubatch).

## When Qwen 4 lands

`models/qwen4-35b.env` with its pin and a mainline commit that knows its architecture,
`profiles/qwen4-35b/` copied from this one, then the grid above re-run with `M=` and `SERVER=`
changed, the KV quality test, and one agent session. If its KV geometry differs, the window moves.
