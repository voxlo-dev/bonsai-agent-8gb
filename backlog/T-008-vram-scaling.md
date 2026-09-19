# T-008 — Measure context per VRAM size and with a shared display

- **Summary:** Derive CTX and the pi budget for >8 GB cards, and for 8 GB cards that also drive a display
- **Category:** decision
- **Importance:** medium
- **Effort:** M
- **Depends on:** T-002, T-001

## Why

The defaults fit exactly one case: 8 GB with ~7.3 GB free. From `docs/dev.md#vram-budget`
(26 MiB per 1k tokens on top of ~6 GB fixed) a 12 GB card would hold roughly 200k context,
and a display on the same 8 GB GPU (0.5-1.2 GB) leaves only ~24-32k - below what the context
budget needs to avoid compacting constantly. Both are extrapolations.

## What

Measure VRAM at a few CTX values on a larger card, and the largest CTX that keeps all layers
on an 8 GB card with a desktop attached. Derive `RESERVE_TOKENS` / `KEEP_RECENT_TOKENS` per
window size and write down the formula, so a user can set CTX from free VRAM without guessing.
Decide whether `bonsai-server` should pick CTX from free VRAM itself.
