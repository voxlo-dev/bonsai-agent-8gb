# T-012 — Fit the thinking budget under pi's output clamp

- **Summary:** Near the compaction trigger pi allows 7 904 output tokens, BUDGET is 8 192 - pick the lever and re-measure
- **Category:** fix
- **Importance:** high
- **Effort:** S
- **Depends on:** none

## Why

pi clamps `max_tokens` to `contextWindow - estimated context - 4096`. Just below the
trigger (`CTX - RESERVE_TOKENS` = 36 000) that is `RESERVE_TOKENS - 4096` = 7 904. A turn
that uses the full `BUDGET` of 8 192 for thinking is then cut off before its tool call, and
`stopReason: length` ends the agent loop. That is how the T-001 run (session
`2026-09-19T17-24-22`) ended, at step 79. 4 of its 79 steps hit the budget; outputs of
those steps were 8.3-11.4k. Details in [`docs/dev.md`](../docs/dev.md#context-budget).

## What

The constraint is `BUDGET + tool call <= RESERVE_TOKENS - 4096`, with a tool call up to ~3k
(largest write measured at ~3.3k output without thinking). Two levers:

- **`BUDGET` 4096** - fits under 7 904 with room for the call. `docs/dev.md#reasoning`
  measured a 3k budget producing plan + code. Cheapest, keeps the compaction rate.
- **`RESERVE_TOKENS` 16000** (and `MAX_TOKENS` 16000) - keeps 8 192 of thinking, but the
  trigger drops to 32 000 and the working room between compactions to ~16k.

Recommendation: `BUDGET` 4096. Re-run the Tron prompt, check no step ends on `length`, and
compare the compaction rate with the T-001 numbers.
