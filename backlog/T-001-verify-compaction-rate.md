# T-001 — Verify the compaction rate under load

- **Summary:** Re-run the Tron prompt and confirm pi no longer compacts on every turn
- **Category:** chore
- **Importance:** high
- **Effort:** S
- **Depends on:** none

## Why

pi's compaction defaults assume a 200k context window. At `CTX=48000` they made the
post-compaction context land *above* the trigger again, so pi compacted on every single turn:
4 compactions in 30 entries, roughly a third of a 31-minute session spent summarizing and
reprocessing, and the task never finished. The numbers and the mechanism are in
[`docs/dev.md`](../docs/dev.md#context-budget).

`RESERVE_TOKENS`, `KEEP_RECENT_TOKENS` and `MAX_TOKENS` have been retuned and
`--no-reasoning-preserve` now keeps earlier turns' thinking out of the prompt. What is
verified so far is only that the server accepts the flag and that `/apply-template` drops an
old `reasoning_content`. **The actual compaction rate under load is not verified.**

## What

Run a full agentic task against the server and count `compaction` entries in the resulting
session log at `~/.pi/agent/sessions/{cwd-slug}/*.jsonl`.

Target: at most one compaction per 2-4 agent steps, against one per turn before. Also check
that `input` on the request following a compaction drops well below the trigger
(`CTX - RESERVE_TOKENS` = 36 000) — that it does *not* is the exact failure this fixed.

If the rate is still too high, the next lever is `BUDGET`, which dominates the per-step cost.
