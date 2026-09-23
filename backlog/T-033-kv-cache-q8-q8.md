# T-033 — Measure the KV cache at q8_0/q8_0 against q8_0/q4_0

- **Summary:** The V cache at `q4_0` was chosen by a general rule ("keys are more sensitive"), never measured on this model. Measure quality (KL divergence against an f16 cache) and speed (short and ~40k context) for `q8_0`/`q8_0` against the shipped `q8_0`/`q4_0`, and what window `q8_0`/`q8_0` leaves on 8 GB. The same-type flash-attention kernel may even be faster at long context
- **Category:** spike
- **Importance:** medium
- **Effort:** S (steps 1-3), M with step 4
- **Depends on:** none

## Why

The author suspects the KV quantization is too aggressive for coding work. Nothing observed so far
points there: the T-019 session logs show process failures (a turn limit, orientation, a ledger),
and the code bugs in them are ordinary ones
([localagent.md](../docs/localagent.md#the-t-019-runs-why-it-is-frozen)). But the choice itself has no measurement behind it,
which is this repo's own condition for revisiting it. [`dev.md`](../docs/dev.md#kv-cache) cites
the general rule and the ~25 % saving, nothing measured on this model.

Three facts shape the test:

- **It does not fit at 64k as a flag.** `q8_0`/`q8_0` is 34 MiB per 1k tokens against 26
  ([VRAM budget](../docs/dev.md#vram-budget)): +512 MiB at 64k, and the `dedicated` profile has
  441 MiB to spare. The arithmetic says ~60k at most. So `q8_0`/`q8_0` is a profile change - `CTX`
  and the four budget values move together - not a one-line switch.
- **Speed may go the other way from what the bytes suggest.** At 40k the measured 25.1 tok/s is
  ~13 % below what bandwidth allows, and [`performance.md`](../docs/performance.md#the-long-context-gap)
  puts that on the flash-attention kernel for *mixed* cache types. A same-type cache reads ~30 %
  more KV bytes per token and may still be faster.
- **The weights are ternary.** Their quantization error likely dwarfs the V cache's, so a KV
  difference may sit in the noise. That is why the comparison needs a scale: `q4_0`/`q4_0` as the
  too-far point, `f16`/`f16` as the reference.

## What to run

On the RTX 4060 Ti machine, `dedicated` profile, no display on the card, nothing else on the GPU.
`runs/T-033-kv-cache/`, the scripts below, the logs beside them.

**1. Quality: KL divergence against an f16 cache, one 16k chunk.** An f16 cache for 16k is
1 GiB (16 layers x 4 heads x 256 dims x 2 bytes x K and V), which fits beside the weights where
64k would not. `llama-perplexity` is not built by `build.sh`; build it in place, it changes nothing
the server uses:

```bash
source config.env; L="$LLAMA_DIR"; M="$MODEL_PATH"
cmake --build "$L/build" --target llama-perplexity -j8
cat "$L"/src/*.cpp "$L"/common/*.cpp | head -c 400000 > corpus.txt        # code, ~100k tokens
P=("$L/build/bin/llama-perplexity" -m "$M" -f corpus.txt -c 16384 --chunks 1 -ngl 99 -fa on)
"${P[@]}" -ctk f16 -ctv f16 --kl-divergence-base base.kld 2>&1 | tee f16-f16.log
for kv in q8_0/q8_0 q8_0/q4_0 q4_0/q4_0; do
  "${P[@]}" -ctk "${kv%/*}" -ctv "${kv#*/}" --kl-divergence-base base.kld --kl-divergence 2>&1 \
    | tee "${kv/\//-}.log"
done
grep -H -E "Mean +KLD|99.0% +KLD|Same top p" q*.log
```

`base.kld` holds the full logits of 8k scored tokens and runs to several GB; delete it afterwards.

**2. Speed at the same window.** 56k fits both types (`q8_0`/`q8_0`: 1.9 GB of KV). The
environment wins over the profile, so the server needs no edit:

```bash
source config.env; head -c 150000 corpus.txt > long.txt                    # ~40k tokens
for v in q4_0 q8_0; do
  CTX=56000 KV_V=$v bonsai-server > "server-$v.log" 2>&1 & sleep 90         # until ready
  for f in /dev/null long.txt; do
    jq -Rs '{prompt: ("Continue:\n" + .), n_predict: 256, cache_prompt: false}' "$f" \
      | curl -sS "$SERVER_URL/completion" -H 'content-type: application/json' -d @- \
      | jq -c --arg v "$v" --arg f "$f" '{v: $v, f: $f, n: .timings.prompt_n,
          pp: .timings.prompt_per_second, tg: .timings.predicted_per_second}'
  done
  pkill -f "$LLAMA_SERVER"; sleep 5
done | tee speed.jsonl
```

Three runs each, the median. `nvidia-smi --query-gpu=memory.used --format=csv` once the long run
has finished shows the VRAM for each type at 56k.

**3. The largest window `q8_0`/`q8_0` holds on 8 GB**, starting at 60000 and down in 2000 steps:
`CTX=… KV_V=q8_0 bonsai-server`, one long request, VRAM read after it, no layer on the CPU in the
log. The profile that would ship is that window with the four budget values re-derived by the
rules in [`dev.md`](../docs/dev.md#context-budget).

**4. Only if step 1 shows a gap or step 2 a speed gain:** the todo CLI in a plain `bonsai-pi`
session on that profile, same prompt, against one on `q8_0`/`q4_0` run the same day (the last
one took 0:33, 22 turns, 48k output). Not under `--localagent`, which is frozen. This is
the only step that measures behaviour, and the most expensive one; a KLD in the noise makes it
unnecessary.

## Deciding

- **Quality:** `q8_0`/`q4_0` within ~0.5 points of `q8_0`/`q8_0` on "same top p", with a mean KLD
  of the same order: no quality case, the suspicion is answered. `q4_0`/`q4_0` shows how far the
  scale goes.
- **Speed:** `q8_0`/`q8_0` at least as fast at ~40k: the trade is a few thousand tokens of window
  for a same-type kernel, and the author decides it with the numbers.
- Either way the result goes to [`dev.md`](../docs/dev.md#kv-cache) (with its measurement, replacing
  the general rule) and to `performance.md`'s long-context gap; a new default moves `KV_V` in
  `config.env` and the `dedicated` profile together, and `./install.sh pi` runs again.

Not in scope: the Vulkan path on the RX 570 (`fa_kv_ok` accepts both types there; its speed
question is a different kernel), and `q5_*`/`iq4_nl` for V, which are a follow-up if `q4_0`
shows a gap and `q8_0` costs too much window.
