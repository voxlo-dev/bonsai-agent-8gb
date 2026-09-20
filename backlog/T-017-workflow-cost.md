# T-017 — Cut what the localagent workflow still costs per unit

- **Summary:** The rebuild works; now attack the three items the T-016 run left standing — the implementer's 32-minute self-verification, the orchestrator's 20 minutes of bookkeeping, and a reviewer whose findings path has never run
- **Category:** spike
- **Importance:** medium
- **Effort:** M
- **Depends on:** T-016 (its run is the evidence below)

## Why

T-016 cut the run from 198 turns / 2:14 to 124 turns / 1:40 and removed the deadlock class
entirely. The numbers and the per-agent breakdown are in
[`docs/localagent.md`](../docs/localagent.md#economics). What that run also showed is where the
remaining bill sits, and it is no longer the harness:

| | T-016 | T-013 |
| --- | --- | --- |
| implementer | 46:42 (U2 alone 32:20 / 36 turns) | 30:37 |
| orchestrator between dispatches | 19:57 | 37:05 |
| reviewer | 17:54, **0 findings** | 12:03 as test-author |

Three things follow.

**The implementer is the cost centre now, and that is partly by design.** It runs what it built
because nothing else checks it — but 36 turns for a four-command CLI is more than verification
needs. Worth knowing before tuning: how much of it is the verification, how much is building.

**The reviewer has never reported a finding.** Two clean units, two `DONE`s. The reviews are
substantive — U1 names the `save(path, tasks=None)` data-loss hazard, U2 reasons about argparse's
two-line stderr — and both held the spec-before-code order, which the session logs show. But the
one-batch findings path, the rework round and the attempt counter are all untested. If the
reviewer waves a real defect through, the split buys nothing and the workflow is the wrong shape
for this model; that is the finding T-016 said to stop on.

**Half of T-016's saving was an e2e step that did not run.** The orchestrator judged a
single-process CLI to have no e2e surface; T-013's judged the opposite and got a 317-line driver.
Both are defensible under the skill as written, which means the run-to-run variance is larger than
the next optimisation.

## What

Measure first, then change at most one thing per run — the comparison only holds while the prompt
and the profile stay fixed.

- **Split the implementer's time** into build and self-verification from the session log (tool
  calls between the last write and `DONE`). Only then decide whether the prompt needs a
  verification budget, a "verify once, at the end" rule, or nothing at all.
- **Test the findings path deliberately:** re-run one unit with an implementer brief that produces
  a known defect (a criterion silently unimplemented), and see whether the reviewer reports it,
  how the rework round runs, and whether the attempt counter behaves. This is the run that decides
  whether the reviewer is a check or a ceremony.
- **The orchestrator's 20 minutes:** its `STATE.md` run log had grown to an essay per step. Decide
  whether the ledger needs a line budget, and whether its own final smoke test is worth its turns.
- **Settle the e2e question for CLI-shaped projects** in the skill, so the decision stops being a
  coin flip: either a CLI is a surface (drive it as a subprocess) or it is not, one sentence, and
  the plan gate records it.
- One small breach to close with a sentence in the implementer prompt: the U2 implementer ran
  `git diff` against the parent repo although the brief said to ignore it.

## Verify

Same prompt, same profile (`dedicated`, CTX 64000, BUDGET 8192), `runs/` next to the other two,
`report.sh` for the numbers. Targets: under 124 turns without losing the clean result, and a
reviewer that reports the planted defect. If it does not report it, record the workflow as
unsuitable for this model in `docs/localagent.md` rather than tuning further.
