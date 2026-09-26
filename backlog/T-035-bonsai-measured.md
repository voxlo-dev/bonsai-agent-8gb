# T-035 — Measure Bonsai the way T-034 measures Qwen: window beyond 64k, the KV cache, and the quality run

- **Summary:** Speed, window and KV quality are measured for both models and in the docs. Left: the behaviour day, one `bonsai-pi` session each for Bonsai at 96k, Bonsai at 64k and Qwen3.6 (T-034), which decides the new defaults, and then the study-harness run that puts the quality claim on the record (was T-027)
- **Category:** spike
- **Importance:** high
- **Effort:** M left (one unattended day, one evaluation, two OpenCode runs)
- **Depends on:** the 4060 Ti machine; T-034's "Before phase 3" steps for session B

## Done

Phase 1 (speed and window) and phase 2 (KV quality against f16), 2026-09-25/26. Results in
[`docs/context-window.md`](../docs/context-window.md), with the consequences in
[`dev.md`](../docs/dev.md#kv-cache) and [`performance.md`](../docs/performance.md#the-long-context-gap):

- The shipped `q8_0`/`q4_0` has no quality case against it and stays. `q8_0`/`q8_0` is not faster.
- **96 000 at `q4_0`/`q4_0`** is the largest window on the card, backed on speed (-6 %) and on
  quality at 92k.
- `-nkvo` is out.
- The long-context gap is not the mixed-type kernel.
- MTP was decided against; why is now in `performance.md`.

## Recommended defaults, pending the behaviour day

| | Now | Candidate | Why |
| --- | --- | --- | --- |
| Bonsai `dedicated` | 64k, `q8_0`/`q4_0`, budget 8192/16000/16000/12000 | **96k, `q4_0`/`q4_0`, budget 8192/16000/16000/16000** | +50 % window for -6 % decode. The trigger moves to 80k, and the largest turn measured (11 441) keeps the peak at ~91.5k, inside the 92.7k verified clean |
| Bonsai `display` | 48k, `q8_0`/`q4_0`, budget 4096/12000/12000/8000 | **64k, `q4_0`/`q4_0`, the dedicated budget 8192/16000/16000/12000** | the cache is 64 x 18 = 1 152 MiB, *less* than today's 48 x 26 = 1 248, and it gets the budget set that produced the best run on record instead of the one that cut thinking at 4096 |
| `MODEL` default | `bonsai` | `bonsai` | Qwen needs 28 GB RAM, which an 8 GB-VRAM repo cannot assume |
| Qwen `dedicated` | shipped as measured (T-034) | – | its session is session B below |

`KEEP_RECENT_TOKENS` 16000 at 96k: at a real cost of 1.4-2x that is ~22-32k after a compaction
(21-24k at 64k with 12000), which leaves ~50k of working room to the 80k trigger. The `display`
candidate is arithmetic and gets one check with a desktop on the card (VRAM, one 43k prompt),
not a session.

## Phase 3 — the behaviour day (4060 Ti, one day, mostly unattended)

Three plain `bonsai-pi` sessions (never `--localagent`), the same prompt, fresh directories, on the
same day, so temperature 1.0 is the only difference between them and the model or window. Every
session starts with the study's Tron prompt from
[model-comparison.md](../docs/model-comparison.md), verbatim. Once the model says it is finished,
it gets the study's follow-up `Test it and get it to work.`, once. No other input.

**0. The missing check, 5 minutes.** 96k at `q4_0`/`q4_0` with a ~95k prompt: pp has to stay near
350 tok/s. It was verified to 92.7k, and the last 3k are the ones a spill would hit. If it spills,
the candidate becomes 92 000 with `KEEP_RECENT_TOKENS` 15000, and the rest of the day is unchanged.

**The sessions**, each ~1.5 h, started back to back:

| | Setup | Command |
| --- | --- | --- |
| A | Bonsai, 96k candidate, own pi dir | see below |
| B | Qwen3.6, `dedicated` as shipped (T-034) | `MODEL=qwen36-35b bonsai-pi` |
| C | Bonsai, 64k as shipped: the same-day control | `bonsai-pi` |

```bash
# A: the candidate through the environment, which wins over the profile; own pi dir so its
# config and sessions stay apart from the default's.
export CTX=96000 KV_K=q4_0 KV_V=q4_0 KEEP_RECENT_TOKENS=16000 \
       PI_AGENT_DIR=$HOME/.local/share/bonsai-local/pi-agent-96k
./install.sh pi && mkdir -p ~/tron-a && cd ~/tron-a && bonsai-pi
```

C re-runs the reference instead of reusing the 2026-09-19 session, because that one predates the
current `BUDGET_MSG`, and n = 1 at temperature 1.0 is too thin to set against a new session.

**Evaluation**, one short Claude session afterwards with the three JSONL files
(`pi-agent-96k/`, `pi-agent-qwen36-35b/`, `pi-agent/` under `sessions/`) and this script:

```python
# BUDGET=8192 python3 runs/T-035-bonsai-measured/session_stats.py SESSION.jsonl... — the numbers.
# usage.input is the uncached prompt, cacheRead the reused prefix: context = input + cacheRead.
# The budget message does not show in the log, so a step counts as at the budget when its thinking
# reaches 90 % of BUDGET at ~4 chars per token. BUDGET=16384 for the Qwen session.
import datetime, json, os, sys
B = int(os.environ.get('BUDGET', 8192))
def ts(d):
    t = d.get('timestamp')
    return datetime.datetime.fromisoformat(t.replace('Z', '+00:00')).timestamp() if isinstance(t, str) else t / 1000
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path)]
    steps = out = biggest = peak = length = hits = 0
    comps, after, rates, prev, pending = [], [], [], None, False
    for d in rows:
        if 'compact' in str(d.get('type', '')):
            comps.append(d.get('tokensBefore')); pending = True
        if d.get('type') == 'message' and d['message'].get('role') == 'assistant':
            m, u = d['message'], d['message'].get('usage', {})
            steps += 1; out += u.get('output', 0); biggest = max(biggest, u.get('output', 0))
            ctx = u.get('input', 0) + u.get('cacheRead', 0); peak = max(peak, ctx + u.get('output', 0))
            if pending: after.append(f"{ctx} (cached {u.get('cacheRead', 0)})"); pending = False
            length += m.get('stopReason') == 'length'
            hits += sum(len(c.get('thinking', '')) for c in m['content'] if c.get('type') == 'thinking') / 4 >= 0.9 * B
            if prev and u.get('output') and ts(d) > prev: rates.append(u['output'] / (ts(d) - prev))
        prev = ts(d)
    rates.sort()
    print(f"{path}\n  wall {(ts(rows[-1]) - ts(rows[0])) / 60:.0f} min, {steps} steps, {out} output tokens, largest turn {biggest}"
          f"\n  compactions {len(comps)} at {comps}, context after: {after}"
          f"\n  peak context {peak}, stopReason length {length}, at the budget {hits} (est.)"
          f"\n  tok/s per step incl. prompt: median {rates[len(rates) // 2] if rates else 0:.1f}")
```

Beside the numbers, for each session, the study's two axes. **Result**: does the game start, can
two browsers log in, host and join, and does a round play? Judge it by hand in two browser
windows, the same way the study did. **Process**: did it end on its own, did it test, did it claim
tests it never ran?

**Decision rules:**

- **Bonsai 96k becomes `dedicated`** if A ends on its own, with no `length` stop, and its result is
  at least as good as C's, with a wall time no worse than C's by more than ~10 %, or with fewer
  compactions. If A's result is worse and C's works, it stays at 64k, and one more A/C pair is worth
  running before that is final, because n = 1.
- **The `display` candidate** follows A's verdict on `q4_0`/`q4_0` and gets its one check with a
  desktop.
- **Qwen (B)**: T-034's phase 4. A working game ships it as supported. A broken one keeps it
  experimental. If B has many budget hits and weak steps after them, the next Qwen session tries
  `BUDGET` 8192.
- Whatever wins moves the profile files. A new `dedicated` also moves `README.md`'s "64k" and the
  `dev.md#context-budget` table, and gets the session added there as its measurement.

## Phase 4 — the quality claim (was T-027)

After the day, on the Bonsai profile that won: **Bonsai through OpenCode, twice**, with the study's
exact prompt and follow-up, OpenCode against `bonsai-server` (`$SERVER_URL/v1`), and a fresh
directory each time. That drops it into the study's table: same harness, prompt and card class, and
two runs because the study's own caveat is n = 1. Then **`docs/evidence.md`** with the prompt, the
invocations, the numbers of these two runs and of the three sessions, and the resulting repos as
tarball links. The README's "what is measured" paragraph follows the result. It says "first" or
"beats" only if both OpenCode runs pass where the study's table fails.

Not in scope: the Vulkan path (T-017's), the localagent workflow (frozen), MTP for Bonsai
([performance.md](../docs/performance.md#mtp-no-head-for-this-gguf)).
