# T-002 — Settle whether 64k context fits

- **Summary:** Measure 64k context on 8 GB or drop the claim from the docs
- **Category:** decision
- **Importance:** medium
- **Effort:** S
- **Depends on:** none

## Why

`README.md` advertises `CTX=64000 bonsai-server` as a supported override and
[`docs/dev.md`](../docs/dev.md#vram-budget) estimates ~7.75 GB for it — but the estimate has
never been run. On an 8 GB card that margin is thin enough that it either works or falls back
to partial offload, which costs about 10x decode speed. Documenting an untested number as if
it were measured is the problem; every other figure in that file is a measurement.

A larger window would also relax the context budget considerably: the compaction settings
exist because 48k is tight.

## What

Start the server at `CTX=64000`, read the actual VRAM figure from `nvidia-smi`, and confirm
all 65 layers are offloaded (the startup log reports this).

Then either raise the documented default and re-derive `RESERVE_TOKENS` /
`KEEP_RECENT_TOKENS` for the larger window, or state in `docs/dev.md` that 64k does not fit
and remove the example from `README.md`. Both outcomes are fine; the open state is not.
