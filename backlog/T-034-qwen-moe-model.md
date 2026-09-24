# T-034 — A second model: Qwen3.6-35B-A3B with the experts in RAM, as the slot Qwen 4 drops into

- **Summary:** Add a `MODEL` axis next to `PROFILE`, so the repo serves either Bonsai-2-27B (the default, unchanged) or a Qwen 35B-A3B MoE with its experts in system RAM (~20 GB) and only attention, shared expert and KV cache on the 8 GB card. The KV cache of that architecture is a third of Bonsai's per token, so the window can grow toward the native 262k. Built and measured with Qwen3.6-35B-A3B now; Qwen 4 35B-A3B, if and when it ships, becomes a new model file and one re-run of the same measurement
- **Category:** feature
- **Importance:** medium
- **Effort:** L (M for the measurement, M for the config split, S for the docs)
- **Depends on:** a machine with the 4060 Ti and >= 32 GB RAM visible to WSL2 for phases 1 and 3. Touches every file T-033 touches (`KV_V`, the profiles): whichever lands second rebases

## Why

The study behind this repo already names the candidate: Qwen3.6-35B-A3B was the best agent *by
process* on this card class, 25.9 tok/s with offloading on auto, and missed on the result
([model-comparison.md](../docs/model-comparison.md)). Bonsai answers that with a dense 27B squeezed
into VRAM. A MoE answers it the other way: 3B active parameters per token make the experts cheap
to run from RAM, which frees the card for the thing Bonsai is short of, the window. The bet is
that the next Qwen MoE (4, 35B-A3B) closes the result gap; the repo should be ready to run it the
day it appears, with the budget arithmetic already measured on its predecessor.

**The KV numbers are what make it interesting** (from `Qwen/Qwen3.6-35B-A3B` `config.json`: 40
layers, every 4th full attention, so 10 layers x 2 KV heads x 256 dims):

| Cache | Qwen3.6-35B-A3B, MiB per 1k | Bonsai (16 x 4 x 256), MiB per 1k | Qwen at 262 144 |
| --- | --- | --- | --- |
| `q8_0`/`q4_0` | 8.1 | 26 | 2.1 GiB |
| `q8_0`/`q8_0` | 10.6 | 34 | 2.7 GiB |
| `f16`/`f16` | 20 | 64 | 5.1 GiB |

The native 262k window at `q8_0`/`q8_0` costs less VRAM than Bonsai's 64k does today. What it
competes with is not the weights but **the experts that could stay on the card**: every GiB of
KV is a GiB of experts that runs from RAM instead. So the window is a trade against generation
speed, and that trade is the measurement.

**Why Qwen 4 needs the plumbing, not just a file.** The pinned PrismML fork (`1a07bfa`,
2026-09-18) knows `qwen35moe`, so Qwen3.6 runs on the binary the repo already builds. It does not
know `qwen4exp`, which mainline added for `Qwen/Qwen3.8-Flash-Next`
(`Qwen4ExpForConditionalGeneration`) — the closest hint of what a Qwen 4 architecture looks like.
A Qwen 4 model will almost certainly need mainline llama.cpp at its own pin, which the fork's
`patches/vulkan/` does not apply to. So the model file has to carry its llama.cpp tree, not only
its GGUF, and phase 1 measures Qwen3.6 on mainline too, so that path has run once before it is
needed.

**The test model.** `Qwen/Qwen3.6-35B-A3B`, Apache-2.0, official. GGUF from
`unsloth/Qwen3.6-35B-A3B-GGUF`, `UD-Q4_K_XL`, the quant the study used, so its 25.9 tok/s is a
reference point. Not `empero-ai/Qwen3.8-35B-A3B-Distill`: despite the name it is a community SFT
of this same model, eight days old at the time of writing.

| Pin | Value |
| --- | --- |
| `MODEL_REPO` | `unsloth/Qwen3.6-35B-A3B-GGUF` |
| `MODEL_REV` | `a483e9e6cbd595906af30beda3187c2663a1118c` |
| `MODEL_FILE` | `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf`, 22 360 456 160 bytes |
| `MODEL_SHA256` | `707a55a8a4397ecde44de0c499d3e68c1ad1d240d1da65826b4949d1043f4450` |
| fallback for 32 GB hosts | `UD-IQ4_XS`, 17 730 509 792 bytes, `649d7508507b84638732c4f52c24c8b15843c6dca2f3ff793ae07c14a67ebbb3` |

## Design

Two independent axes. `PROFILE` stays what it is, the GPU situation (`dedicated`, `display`).
`MODEL` is new: `bonsai` (default) and `qwen36-35b`.

```text
config.env                      MODEL, PROFILE, everything shared; sources the two files below
models/bonsai.env               model pin, llama.cpp tree, server flags, sampling, RAM/disk needs
models/qwen36-35b.env           the same keys for Qwen
profiles/bonsai/{dedicated,display}.env      CTX + the four budget values (today's files, moved)
profiles/qwen36-35b/{dedicated,display}.env  the same, measured in phase 1
```

Per model file, beyond today's `MODEL_*` pins and `MODEL_ALIAS`:

| Key | Bonsai | Qwen3.6 | Why per model |
| --- | --- | --- | --- |
| `LLAMA_REPO`, `LLAMA_COMMIT`, `LLAMA_DIR` | fork, `1a07bfa`, `$BONSAI_HOME/llama.cpp` | fork or mainline, phase 1 decides; own `LLAMA_DIR` if mainline | Qwen 4 needs mainline |
| `PATCH_SET` | `prism` → `patches/prism/$BACKEND/` | none | the PTQ1_0 patch only applies to the fork |
| `OFFLOAD` | `-ngl 99 --fit off` | `-ngl 99 --fit off --n-cpu-moe $CPU_MOE` | experts in RAM |
| `CPU_MOE` (in the profile) | — | from phase 1 | trades against `CTX`, so it lives with it |
| `KV_K`, `KV_V` | `q8_0`/`q4_0` | `q8_0`/`q8_0` unless phase 1 says otherwise | 2.4 MiB/1k difference, not worth a quality question |
| `TEMP`, `TOP_P`, `TOP_K`, `MIN_P`, `PRESENCE_PENALTY` | today's values | Qwen's card, coding: 0.6 / 0.95 / 20 / 0 / 0 | the model card differs |
| `MODEL_RAM_MB`, `MODEL_DISK_MB` | 5 800 / 5 800 | from phase 1 / 22 400 | preflight and `model.sh` hard-code Bonsai's today |

Consumers that change:

- **`bin/bonsai-server`**: flags from the model file instead of hard-coded. Bonsai's command line
  must come out **identical** — verified by comparing `/props` before and after on the 4060 Ti.
- **`scripts/build.sh`**: already stamps per `LLAMA_DIR`; takes patches from `PATCH_SET`. A
  mainline tree gets its own directory, so switching `MODEL` never rebuilds the other.
- **`scripts/model.sh`**: size in the message from `MODEL_DISK_MB`. Nothing else: it is pin-driven.
- **`scripts/preflight.sh`**: disk and RAM from the model file. For Qwen the RAM check is on
  `MemTotal`, not `MemAvailable`, and a WSL2 host below it gets the `.wslconfig` hint (WSL2 sees
  half the Windows RAM by default: a 32 GB PC gives it 16).
- **`scripts/pi.sh`**: `PI_AGENT_DIR` per model — `pi-agent` for Bonsai (existing installs keep
  their sessions), `pi-agent-$MODEL` otherwise, because `settings.json`'s compaction keys are
  global per agent dir. `reasoning` stays off: the Qwen3.6 template reads `enable_thinking` and
  `preserve_thinking`, not `reasoning_effort`.
- **`bin/bonsai-pi`**: a healthy server on `PORT` is reused today whatever it serves. With two
  models that silently connects `MODEL=qwen36-35b` to a running Bonsai. Check `/v1/models` against
  `MODEL_ALIAS` and stop with a message on a mismatch.
- **Not touched:** the localagent extension (frozen), the Vulkan path (the RX 570 box's RAM is
  unknown and its CPU slow; a follow-up if anyone asks). Names stay `bonsai-server`/`bonsai-pi`.

## Phase 1 — measure before building (4060 Ti, ~2 h, mostly unattended)

Uses the fork build that is already installed, plus one mainline build beside it. Nothing in
`BONSAI_HOME` changes except a new file under `models/`. Before starting: `free -g` shows >= 30 GB
total (else raise `memory=` in `%UserProfile%\.wslconfig` and `wsl --shutdown`), no display on the
card, no other `llama-server`.

```bash
# runs/T-034-qwen-moe/measure.sh — one config per line of CONFIGS, JSONL out.
set -euo pipefail
source ~/bonsai-local/config.env
SERVER="${SERVER:-$LLAMA_SERVER}"                     # SERVER=... for the mainline build
M="$BONSAI_HOME/models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
P=8084; U="http://127.0.0.1:$P"
pgrep -f 'build/bin/llama-server' >/dev/null && { echo "a llama-server runs - stop it"; exit 1; }
[[ -f corpus.txt ]] || cat "$LLAMA_DIR"/src/*.cpp "$LLAMA_DIR"/common/*.cpp > corpus.txt
head -c 3400 corpus.txt > p1k.txt; head -c 150000 corpus.txt > p40k.txt; head -c 400000 corpus.txt > p100k.txt

# "ctx cpu_moe kv_v" — start with every expert on the CPU, then move experts onto the card
# until VRAM is full; the same for a smaller window. Add lines as the first results come in.
CONFIGS="${CONFIGS:-262144 40 q8_0
262144 34 q8_0
131072 40 q8_0
131072 30 q8_0
65536 26 q8_0}"

req() {  # file n_predict cache -> timings
  jq -Rs --argjson n "$2" --argjson c "$3" '{prompt: ("Continue:\n" + .), n_predict: $n, cache_prompt: $c}' "$1" \
    | curl -sS "$U/completion" -H 'content-type: application/json' -d @- \
    | jq -c '{n: .timings.prompt_n, pp: .timings.prompt_per_second, tg: .timings.predicted_per_second}'
}
while read -r ctx moe kvv; do
  "$SERVER" -m "$M" --port $P -c "$ctx" -ngl 99 --fit off --n-cpu-moe "$moe" -fa on \
    -ctk q8_0 -ctv "$kvv" --parallel 1 --no-context-shift --jinja > "server-$ctx-$moe.log" 2>&1 &
  pid=$!
  until curl -sf "$U/health" >/dev/null; do kill -0 $pid 2>/dev/null || { echo "$ctx $moe: failed to load"; continue 2; }; sleep 2; done
  short=$(req /dev/null 256 false); p1k=$(req p1k.txt 128 false); p40k=$(req p40k.txt 128 true)
  again=$(req p40k.txt 128 true)                        # prompt_n small = the hybrid cache is reused
  p100k='null'; ((ctx >= 131072)) && p100k=$(req p100k.txt 128 false)
  vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
  rss=$(( $(ps -o rss= -p $pid) / 1024 ))
  jq -nc --arg bin "$SERVER" --argjson ctx $ctx --argjson moe $moe --arg kvv $kvv --argjson vram $vram \
    --argjson rss $rss --argjson short "$short" --argjson p1k "$p1k" --argjson p40k "$p40k" \
    --argjson again "$again" --argjson p100k "$p100k" '$ARGS.named'
  kill $pid; wait $pid 2>/dev/null || true; sleep 5
done <<<"$CONFIGS" | tee -a results.jsonl
```

Steps:

1. **Download** into `$BONSAI_HOME/models/` with the pins above (`curl -fL -C -` then
   `sha256sum`), on the Linux filesystem, never under `/mnt/c`.
2. **Fork build, the grid above.** A config that fails to load, or whose VRAM reads above
   ~7 900 MiB, marks the edge; move `CPU_MOE` up by 2 and add the line. Three runs of the
   configs that matter, the median.
3. **Mainline, the best two configs.** `git clone https://github.com/ggml-org/llama.cpp
   ~/llama-mainline`, note the commit, build `llama-server` with the flags from
   `scripts/build.sh` (CUDA branch), `SERVER=~/llama-mainline/build/bin/llama-server
   CONFIGS="…" bash measure.sh`.
4. **Render one conversation** through `/apply-template` with a tool call and a thinking block,
   with and without `--no-reasoning-preserve`: does the Qwen3.6 template drop earlier thinking the
   way Bonsai's does ([dev.md](../docs/dev.md#thinking-in-the-prompt))?

What decides what:

| Question | Read from | Goes to |
| --- | --- | --- |
| Window for `dedicated` | the largest `ctx` whose `tg` at `p40k` is within ~15 % of the best config | `profiles/qwen36-35b/dedicated.env` |
| Window for `display` | the same with ~1 GB less VRAM (run the grid with a desktop on the card, or cap by arithmetic and verify once) | `…/display.env` |
| Fork or mainline | `tg` and `pp` of the same config on both; mainline if clearly faster, else the fork (one tree to build) | `LLAMA_*` in `models/qwen36-35b.env` |
| Hybrid prompt cache works | `again.n` small against `p40k.n` | if not: a `--ctx-checkpoints`/cache flag, or a showstopper |
| RAM need | `rss` plus page cache: `free -m` before and after load | `MODEL_RAM_MB` |

## Phase 2 — the config split (here, no GPU needed; one commit per change)

1. Move `profiles/*.env` to `profiles/bonsai/`, add `models/bonsai.env`, `MODEL` in
   `config.env`. Bonsai behaviour unchanged; `bash -n` every script, `./install.sh model pi` twice.
2. `bonsai-server` from model-file flags. Verify on the 4060 Ti: `/props` identical for Bonsai.
3. `build.sh`: `PATCH_SET`, per-model `LLAMA_DIR`. Rebuilding Bonsai's tree must not happen
   (stamp unchanged).
4. `preflight.sh` / `model.sh`: sizes and RAM from the model file, `.wslconfig` hint.
5. `pi.sh` / `bonsai-pi`: per-model agent dir, alias check.
6. `models/qwen36-35b.env` and `profiles/qwen36-35b/*.env` with the phase 1 numbers and a comment
   naming the run.

Budget, starting point for `dedicated` at a 131 072 window, to be re-derived from phase 1 and
phase 3 by the rules in [dev.md](../docs/dev.md#context-budget):

| | Value | Constraint |
| --- | --- | --- |
| `BUDGET` | 16384 | the study measured this model at 91 % reasoning share; 8192 is Bonsai's |
| `RESERVE_TOKENS` | 32000 | >= `BUDGET` + tool call (~4k) + 4096 clamp = ~24.5k |
| `MAX_TOKENS` | 32000 | <= `RESERVE_TOKENS` |
| `KEEP_RECENT_TOKENS` | 24000 | real cost 1.4-2x = ~48k, far under the 99k trigger |

A bigger window is not free even when it fits: after a compaction the whole kept context is
reprocessed at the `pp` rate phase 1 measures, and every turn's attention reads the whole cache.
The `p100k` numbers say what a 200k context costs per turn.

## Phase 3 — behaviour (4060 Ti, one session)

`MODEL=qwen36-35b ./install.sh pi`, then one plain `bonsai-pi` session with the Tron prompt from
[model-comparison.md](../docs/model-comparison.md), not `--localagent`. From the session JSONL:
steps, wall time, compactions and the context after each, `cacheRead` after a compaction (the
hybrid cache again, under pi), `stopReason: length`, tok/s over the session. Against Bonsai's
64k run (108 steps, 91 min, 4 compactions, result working) and the study's Qwen3.6 run (>60 min,
3 compactions at 64k, result broken). The window is the variable: if it removes the compactions
and the result is still broken, that is the answer on this model, and the slot waits for Qwen 4.

## Phase 4 — docs, and when Qwen 4 lands

- `docs/dev.md`: a `## Second model: Qwen MoE` section with the phase 1 table, the fork/mainline
  decision, the budget; the KV and VRAM tables get a Qwen column.
- `README.md`: `MODEL=qwen36-35b` under Configure, the RAM requirement under Requirements. Bonsai
  stays the headline and the default.
- **Qwen 4 35B-A3B:** `models/qwen4-35b.env` with its pin and a mainline commit that knows its
  architecture, `profiles/qwen4-35b/` copied from Qwen3.6, phase 1 with `M=` and `SERVER=` changed,
  phase 3 once. If its KV geometry differs from Qwen3.6, the windows move; the code does not.

## Open for the author

- **RAM on the 4060 Ti PC** and WSL2's `memory=` there. At 64 GB `UD-Q4_K_XL` is the pin; at 32 GB
  it is tight beside Windows and `UD-IQ4_XS` becomes the default.
- **Whether `qwen36-35b` ships as a supported model or stays a branch** until Qwen 4 exists.
  The config split is worth keeping either way; the Qwen files could wait.
