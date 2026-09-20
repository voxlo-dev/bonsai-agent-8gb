# T-014 — Verify the 64k budget under load

- **Summary:** Run the Tron prompt at CTX 64000 / BUDGET 8192 and check the compaction rate, `length` cut-offs and result quality
- **Category:** chore
- **Importance:** high
- **Effort:** S
- **Depends on:** none

## Why

T-002 measured that 64k loads (7 747 MiB of 8 188, 36 tok/s, no layer on the CPU) and the
default moved there, which let `BUDGET` go back to 8192 with `RESERVE_TOKENS` 16000,
`MAX_TOKENS` 16000 and `KEEP_RECENT_TOKENS` 12000 (`docs/dev.md#context-budget`). None of
that is measured under load. The question behind it is quality: at `BUDGET` 4096 the T-012
run finished, but claimed passing tests it had never run and left the online mode untested.

## What

The run is prepared in `runs/T-002-64k-budget8k/run.sh` (the user starts it in their own
terminal). Read the session jsonl afterwards and compare with the two earlier runs:

| | T-001 (48k, budget 8192) | T-012 (48k, budget 4096) |
| --- | --- | --- |
| Steps | 79, ended on `length` | 168, ended on `stop` |
| Compactions | 5, every 5-19 steps | 7, every 8-33 steps |
| Budget hits | 4 | 6 |

Check: no step ends on `length`; the compaction rate at the larger window; whether the
result is better than T-012's single `index.html` with untested online mode. If quality
tracks the budget, the trade-off (fewer, longer steps vs. more compaction room) belongs in
`docs/dev.md#reasoning`.
