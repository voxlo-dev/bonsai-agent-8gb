# T-013 — Run the localagent workflow on Bonsai

- **Summary:** Drive one small feature through `bonsai-pi --localagent` and see where a 27B model breaks the pipeline
- **Category:** spike
- **Importance:** medium
- **Effort:** M
- **Depends on:** none

## Why

The `dispatch` extension is verified only against a scripted stand-in endpoint
([docs/dev.md](../docs/dev.md#localagent-workflow)). Whether the model follows the orchestrator
protocol - plan gate, `STATE.md` after every step, briefs in four parts, no content work of its
own - and whether the agents return a status line at all is unknown. Every dispatch also evicts
the orchestrator's KV cache (one slot), so its context is re-read after each step; how much
time that costs per unit is unmeasured.

## What

In an empty scratch repo, `bonsai-pi --localagent` with a 2-unit task (e.g. a small CLI with
tests). Record from the session logs (`sessions/{cwd-slug}/` and its `dispatch/` folder):
dispatches per unit, status lines returned, wall blocks hit, `stopReason: length` in any child,
compactions in the orchestrator, prefill time after each dispatch (server log). Note which
workflow rules the model broke. Result into `docs/dev.md#localagent-workflow`; prompt changes
the run calls for go into `pi/localagent-workflow/` as their own change.
