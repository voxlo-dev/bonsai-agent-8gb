# T-035 — Measure Bonsai the way T-034 measures Qwen: window beyond 64k, the KV cache, and the quality run

- **Summary:** One measurement pass over Bonsai-2-27B that asks the questions T-034 asks of Qwen3.6, so the two models land in one table: what window fits beyond 64k and at what cost (a smaller KV type, KV in RAM), what the KV types do to quality (was T-033), and the study-harness run that puts the quality claim on the record (was T-027). Supersedes T-027 and T-033
- **Category:** spike
- **Importance:** high
- **Effort:** M (S for phase 1, S for phase 2, M for phase 3)
- **Depends on:** the 4060 Ti machine, ~10 GB free disk (the KLD base), >= 16 GB RAM visible to WSL2 (the KV-in-RAM configs). Phase 4 lands in `profiles/bonsai/` if T-034's split is in by then, in `profiles/` otherwise

## Why

T-034's phase 1 measures Qwen3.6 across windows, offload splits and two llama.cpp trees, with
long prompts and cache reuse. Bonsai, the default, has less than that: speed at short context and
~40k, one window (64k) and "80k does not fit", a KV type chosen by a general rule, and a quality
claim that rests on sessions nobody else can open. Three gaps, one pass:

**1. Beyond 64k.** At 64k with `q8_0`/`q4_0` the card holds 7 747 of 8 188 MiB, and 80k does not
fit ([VRAM budget](../docs/dev.md#vram-budget)), so the KV space is somewhere between 1 664 and
~2 080 MiB. Only the KV type or its location can move the window:

| KV (per 1k tokens) | Window from 1 664-2 080 MiB |
| --- | --- |
| `q8_0`/`q8_0` (34 MiB) | 49-61k |
| `q8_0`/`q4_0` (26 MiB, shipped) | 64k measured, < 80k |
| `q4_0`/`q4_0` (18 MiB) | 92-115k |
| KV in RAM (`-nkvo`) | RAM-bound, up to the native 262k |

`q4_0`/`q4_0` is the only way past 64k that keeps everything on the card, which makes its quality
(gap 2) the price of the window. `-nkvo` runs the 16 attention layers' attention on the CPU. It is
expected to be slow at depth (a 262k `q8_0` cache is 8.9 GB read from RAM per token), but nobody has
measured it on this model, and the other 48 layers are Gated DeltaNet and do not care. The fork's
own list reports crashes with a quantized KV cache around 200k (`KNOWN_ISSUES.md`), which is one
more reason to measure before shipping a window like that.

**2. The KV cache (was T-033).** `q4_0` for V was chosen by the rule "keys are more sensitive",
never measured here. The author suspects it is too aggressive for coding; the T-019 logs show
process failures, not KV symptoms, but the choice has no number behind it. Gap 1 raises the stakes:
`q4_0` for K too is what buys a larger window. The weights are ternary, so a KV difference may be
lost in their own error, which is why the scale runs from `f16` to `q4_0`/`q4_0`. At 40k the
decode is ~13 % below the roofline, and [performance.md](../docs/performance.md#the-long-context-gap)
blames the mixed-type flash-attention kernel for that, so a same-type cache may be faster despite
the bytes.

**3. The quality claim (was T-027).** The study's table
([model-comparison.md](../docs/model-comparison.md)) has no Bonsai row: same Tron prompt, OpenCode,
8 GB card, n = 1 per cell. Qwen3.8-27B is best by result at 3.9 tok/s (~6 h); Qwen3.6-35B-A3B best
by process with a broken result. The defensible claim today is "the dense 27B's result quality, at
36 tok/s, in the same 8 GB", and only a Bonsai run in that harness can confirm or narrow it. Done
already: the study is translated into the tree with its n = 1 caveat, and the README leads with
the gap.

## Phase 1 — speed and window (4060 Ti, ~2 h, mostly unattended)

On the installed build at the pinned `1a07bfa`, nothing in `BONSAI_HOME` changes except
`llama-perplexity` built in place for phase 2. Scripts, logs and results in
`runs/T-035-bonsai-measured/`. Same shape and prompts as T-034's `measure.sh`, so the rows
compare. A line of `CONFIGS` is `ctx ctk ctv [extra flags]`:

```bash
# runs/T-035-bonsai-measured/measure.sh — one config per line of CONFIGS, JSONL out.
set -euo pipefail
source ~/bonsai-local/config.env
SERVER="${SERVER:-$LLAMA_SERVER}"; M="$MODEL_PATH"
P=8084; U="http://127.0.0.1:$P"
pgrep -f 'build/bin/llama-server' >/dev/null && { echo "a llama-server runs - stop it"; exit 1; }
[[ -f corpus.txt ]] || cat "$LLAMA_DIR"/src/*.cpp "$LLAMA_DIR"/common/*.cpp > corpus.txt
head -c 3400 corpus.txt > p1k.txt; head -c 150000 corpus.txt > p40k.txt; head -c 400000 corpus.txt > p100k.txt

CONFIGS="${CONFIGS:-64000 q8_0 q4_0
56000 q8_0 q8_0
60000 q8_0 q8_0
96000 q4_0 q4_0
112000 q4_0 q4_0
131072 q8_0 q8_0 -nkvo
262144 q8_0 q8_0 -nkvo}"

req() {  # file n_predict cache -> timings
  jq -Rs --argjson n "$2" --argjson c "$3" '{prompt: ("Continue:\n" + .), n_predict: $n, cache_prompt: $c}' "$1" \
    | curl -sS "$U/completion" -H 'content-type: application/json' -d @- \
    | jq -c '{n: .timings.prompt_n, pp: .timings.prompt_per_second, tg: .timings.predicted_per_second}'
}
chat() {  # one real turn, thinking and code at the shipped sampling
  jq -n '{messages: [{role: "user", content: "Write a Python function that parses an ISO 8601 duration such as P3DT4H5M into seconds, with pytest tests."}],
          max_tokens: 3072, temperature: 1.0, top_p: 0.95, top_k: 20, min_p: 0}' \
    | curl -sS "$U/v1/chat/completions" -H 'content-type: application/json' -d @- \
    | jq -c '{n: .usage.completion_tokens, tg: .timings.predicted_per_second}'
}
i=0
while read -r ctx ctk ctv extra; do
  i=$((i + 1))
  # $extra unquoted on purpose: it is a list of flags
  "$SERVER" -m "$M" --port $P -c "$ctx" -ngl 99 --fit off -fa on -ctk "$ctk" -ctv "$ctv" \
    --parallel 1 --no-context-shift --jinja --reasoning on --reasoning-effort medium \
    $extra > "server-$i.log" 2>&1 &
  pid=$!
  until curl -sf "$U/health" >/dev/null; do kill -0 $pid 2>/dev/null || { echo "$i $ctx $ctk/$ctv $extra: failed to load"; continue 2; }; sleep 2; done
  short=$(req /dev/null 256 false); p1k=$(req p1k.txt 128 false); c=$(chat)
  p40k='null'; again='null'; p100k='null'
  if ((ctx >= 48000)); then p40k=$(req p40k.txt 128 true); again=$(req p40k.txt 128 true); fi
  ((ctx >= 110000)) && p100k=$(req p100k.txt 128 false)
  vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
  rss=$(( $(ps -o rss= -p $pid) / 1024 ))
  jq -nc --argjson i $i --arg bin "$SERVER" --argjson ctx $ctx --arg ctk $ctk --arg ctv $ctv --arg extra "$extra" \
    --argjson vram $vram --argjson rss $rss --argjson short "$short" --argjson p1k "$p1k" --argjson chat "$c" \
    --argjson p40k "$p40k" --argjson again "$again" --argjson p100k "$p100k" '$ARGS.named'
  kill $pid; wait $pid 2>/dev/null || true; sleep 5
done <<<"$CONFIGS" | tee -a results.jsonl
```

The first row must reproduce ~36 tok/s short and ~25 at 40k, or the machine is not in its
reference state. Three passes, the median. A config that fails to load or reads above ~7 900 MiB
marks an edge; step the window down by 4k and add the line. `chat` at `temperature` 1.0 varies in
length, so its tok/s counts, its token count does not.

What each row answers:

| Rows | Question |
| --- | --- |
| `64000 q8_0 q4_0` | the reference, and the baseline for everything below |
| `56000`/`60000 q8_0 q8_0` | T-033's speed question: is the same-type kernel faster at 40k (`p40k.tg`)? |
| `96000`/`112000 q4_0 q4_0` | the largest window on the card, and the decode at depth (`p100k.tg`) |
| `-nkvo` rows | whether KV in RAM is usable at all: `tg` at 40k and 100k against the on-card rows |
| `again.n` everywhere | the hybrid prompt cache is reused (small), or a turn reprocesses everything |

## Phase 2 — quality of the KV types (4060 Ti, ~1 h; was T-033)

**2a. KL divergence against an f16 cache, one 16k chunk.** 16k of `f16` cache is 1 GiB and fits
beside the weights. `llama-perplexity` is not built by `build.sh`; building it in place changes
nothing the server uses:

```bash
source ~/bonsai-local/config.env
cmake --build "$LLAMA_DIR/build" --target llama-perplexity -j8
P=("$LLAMA_DIR/build/bin/llama-perplexity" -m "$MODEL_PATH" -f corpus.txt -c 16384 --chunks 1 -ngl 99 -fa on)
"${P[@]}" -ctk f16 -ctv f16 --kl-divergence-base base.kld 2>&1 | tee f16-f16.log
for kv in q8_0/q8_0 q8_0/q4_0 q4_0/q4_0; do
  "${P[@]}" -ctk "${kv%/*}" -ctv "${kv#*/}" --kl-divergence-base base.kld --kl-divergence 2>&1 | tee "${kv/\//-}.log"
done
grep -H -E "Mean +KLD|99.0% +KLD|Same top p" q*.log
```

`base.kld` holds the full logits of 8k scored tokens, several GB; delete it afterwards.

**2b. Perplexity at 96k**, because a window beyond 64k is only worth something if `q4_0`/`q4_0`
still reads it. A KLD base at this length would hold ~49k tokens of logits x 248k vocabulary,
~24 GB, so this step compares perplexity only: the reference is `f16` with the cache in RAM,
the candidate `q4_0`/`q4_0` on the card.

```bash
P=("$LLAMA_DIR/build/bin/llama-perplexity" -m "$MODEL_PATH" -f corpus.txt -c 98304 --chunks 1 -ngl 99 -fa on)
"${P[@]}" -nkvo -ctk f16 -ctv f16 2>&1 | tee ppl96k-f16-ram.log     # slow: attention on the CPU
"${P[@]}" -ctk q4_0 -ctv q4_0 2>&1 | tee ppl96k-q4-q4.log
grep -H "Final estimate" ppl96k-*.log
```

If the `f16` run is still going after an hour, `-ctk q8_0 -ctv q8_0 -nkvo` is the reference instead.

## Phase 3 — behaviour and the quality claim (4060 Ti; was T-027)

1. **The study cell: Bonsai through OpenCode, twice.** The study's exact Tron prompt and
   follow-up from [model-comparison.md](../docs/model-comparison.md), OpenCode against
   `bonsai-server` (`$SERVER_URL/v1`, the shipped `dedicated` profile), a fresh directory each
   time. Recorded on the study's two axes, process and result: wall time, tok/s, compactions,
   whether the game runs for two players. Two runs, because the study's own caveat is n = 1.
2. **One `bonsai-pi` session on the candidate profile from phase 1**, the same Tron prompt: the
   window beyond 64k, if it passed phases 1 and 2. From the session JSONL: steps, wall
   time, compactions and the context after each, `cacheRead` after a compaction,
   `stopReason: length`, tok/s over the session. It goes in one table with Bonsai's 64k run
   (108 steps, 91 min, 4 compactions, working) and T-034's Qwen3.6 session.
3. **`docs/evidence.md`:** the prompt, the invocations and profiles, the numbers from 1 and 2, and
   the resulting repos as tarball links. The existing `bonsai-pi` Tron session
   (`2026-09-19T16-24-33`) stays in it as a data point, labelled as a different harness.

## Phase 4 — decisions and where they land

- **KV default:** `q8_0`/`q4_0` within ~0.5 points of `q8_0`/`q8_0` on "same top p" and with a mean KLD
  of the same order means there is no quality case, and the suspicion is answered. If
  `q8_0`/`q8_0` is at least as fast at 40k, the author decides with the numbers whether a few
  thousand tokens of window are worth the same-type kernel. `q5_0` stays out (the fork lists it as
  several times slower, #191).
- **A profile beyond 64k:** if `q4_0`/`q4_0` passes 2a and 2b and holds speed at depth, a new
  profile (`long`, or `dedicated` itself moves) with the four budget values re-derived by the rules
  in [dev.md](../docs/dev.md#context-budget). `-nkvo` ships only if its speed at 40k is within ~15 %
  of the on-card rows, which is not expected.
- **Docs:** `dev.md#kv-cache` gets the measurement in place of the rule; `dev.md#vram-budget` gets the
  `q4_0`/`q4_0` and `-nkvo` rows; `performance.md` gets the long-context gap re-measured. The README's "what is measured" paragraph follows phase 3,
  and "first" or "beats" only if both OpenCode runs pass where the study's table fails.

Not in scope: MTP, decided against for now. For the record, since it is not written down anywhere
else: the official GGUF has no MTP block (tensors end at `blk.63`). The only head is the community
one in `ProCreations/Ternary-Bonsai-2-27B-MTP`, shipped inside a 7.66 GB PQ2_0 bundle that does not
fit on 8 GB. Using it would take a merged PTQ1_0 file and a pin past fork PR #205 (2026-09-21).
Also out: the Vulkan path (T-017's), the `display` profile (re-derived from the `dedicated`
result by subtracting the desktop's 0.5-1.2 GB, verified once), and the localagent workflow (frozen).
