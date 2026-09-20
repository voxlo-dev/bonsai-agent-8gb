# T-015 — Decide whether to shrink pi's 4096-token safety margin

- **Summary:** pi's `CONTEXT_SAFETY_TOKENS` = 4096 costs a quarter of the reserve; decide between patching it, upstreaming it and leaving it
- **Category:** decision
- **Importance:** low
- **Effort:** S
- **Depends on:** T-014

## Why

pi clamps a request to `contextWindow - estimated context - 4096`, so the usable output at
the compaction trigger is `RESERVE_TOKENS - 4096`. That constant is what forces
`RESERVE_TOKENS` 16000 for a `BUDGET` of 8192, and the trigger to 48 000 in a 64k window
(`docs/dev.md#context-budget`). Its own estimate was accurate to ~300 tokens in the T-001
measurement, so 4096 looks generous for this setup, where one model serves one session.

Shrinking it to, say, 1024 would move the trigger to 51 000 with the same budget, or allow
`RESERVE_TOKENS` 12000 with `BUDGET` 8192.

## What

Three options, and the decision is which one this repo takes:

- **Leave it.** Costs ~3k of working room per compaction cycle. No maintenance.
- **Patch it** in `$BONSAI_HOME/pi/node_modules/.../dist` from `scripts/pi.sh`. Fast, but it
  edits a pinned dependency's bundle: `PI_VERSION` no longer describes what runs, and every
  version bump has to re-find the constant. Against `AGENTS.md` ("pins are deliberate").
- **Ask upstream** to make it configurable, e.g. a `compaction.safetyTokens` setting. Slow,
  but it is the only route that survives a pi update.

Decide after T-014: if the run shows the trigger is not the limiting factor, leave it.
