# T-019 — Cut what the localagent workflow still costs per unit

- **Summary:** After the Tron run (five hours, one unit, aborted) the workflow is reshaped: one worker per unit, harness-run gate, 15-turn dispatch limit, 4096 agent budget. Measure the new shape on the todo CLI against T-018's 124 turns before anything larger
- **Category:** spike
- **Importance:** medium
- **Effort:** M
- **Depends on:** T-018 (its run is the evidence below)

## Why

T-018 cut the run from 198 turns / 2:14 to 124 turns / 1:40 and removed the deadlock class
entirely. The numbers and the per-agent breakdown are in
[`docs/localagent.md`](../docs/localagent.md#economics). What that run also showed is where the
remaining bill sits, and it is no longer the harness:

| | T-018 | T-013 |
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
for this model; that is the finding T-018 said to stop on.

**Half of T-018's saving was an e2e step that did not run.** The orchestrator judged a
single-process CLI to have no e2e surface; T-013's judged the opposite and got a 317-line driver.
Both are defensible under the skill as written, which means the run-to-run variance is larger than
the next optimisation.

## What happened in between: the Tron run

Branch `t019-workflow-cost` at its first three commits, the study's Tron prompt, 2026-09-21/22.
Aborted after about five hours with one of three units done. The per-agent numbers and the three
mechanisms (thinking accumulating to a compaction inside every child, numeric rules checked with
turns, an orchestrator restating and inventing rules) are in
[`docs/localagent.md`](../docs/localagent.md#the-tron-run-where-the-three-agent-shape-stops).
Logs: `runs/T-013-localagent-tron/`, orchestrator sessions and the `dispatch/` folder.

Three of seven dispatches never returned. That is the finding that reshaped the workflow rather
than tuning it: the three-agent split was costing two dispatches per unit for a reviewer that has
found nothing in three units, and no prompt-only bound held.

## What is on the branch now

| Where | Change |
| --- | --- |
| `config.env`, `bin/bonsai-pi`, `scripts/pi.sh` | `AGENT_BUDGET` 4096 and `AGENT_BUDGET_MSG` as a second `models.json` entry `<alias>-agent` with `samplingParams`; `AGENT_MAX_TURNS` 15. Both reach the extension through the environment |
| `pi/extensions/localagent/index.ts` | children run on the agent model; a dispatch past the turn limit is killed and returned as `BLOCKED … turn budget`; after a `DONE` the tool runs the `test` command and appends `tests:` and `changed:` |
| `pi/localagent-workflow/` | `localagent-worker` replaces spec-architect, implementer and reviewer; skill, orchestrator and templates follow: briefs carry facts only, the plan entry inline, units of one file and three to five criteria, no numeric rule anywhere in a prompt |
| `docs/localagent.md` | the Tron numbers, the new shape and what it is answering, and the plain statement that it has not run yet |

## What to run, in this order

The four changes are one shape; they are measured together. The comparison is against T-018's
todo-CLI run (124 turns, 1:40, 164k output tokens) on the same profile.

1. **`./install.sh pi`** on the branch. Check `$BONSAI_HOME/pi-agent/models.json` has the
   `bonsai-27b-agent` entry with `samplingParams`. Then, with `bonsai-server` up, one request
   by hand to confirm the server accepts the other model name and the smaller budget:

   ```bash
   curl -s "$SERVER_URL/v1/chat/completions" -H 'content-type: application/json' -d '{
     "model":"bonsai-27b-agent","max_tokens":600,"reasoning_budget_tokens":64,
     "reasoning_budget_message":"\n\nBudget. Answer now.\n",
     "messages":[{"role":"user","content":"Think about it, then name three prime numbers."}]}' \
     | python3 -c 'import json,sys; m=json.load(sys.stdin)["choices"][0]["message"]; print(len(m.get("reasoning_content","")), "reasoning chars |", m["content"][:200])'
   ```

   The reasoning should be a few hundred characters at most. If the server rejects the model
   name, the agent entry needs the alias's name and the extension a different way to select it.

2. **The turn limit and the gate, ten minutes each, without a full run.** A worker by hand,
   the way `dispatch` starts it, in a scratch repo that already has a green test command:

   ```bash
   source config.env; W=$(pwd)/scratch; A=pi/localagent-workflow/agents
   PI_CODING_AGENT_DIR="$PI_AGENT_DIR" "$PI_BIN" --mode json -p --model "local/$AGENT_MODEL_ID" \
     --no-extensions --no-skills --no-prompt-templates --no-context-files --session-dir "$W/.s" \
     --append-system-prompt "$(awk 'n>=2{print} /^---$/{n++}' $A/localagent-worker.md)" \
     -- "Working directory: $W. Test command: npm test. Unit U1: a complete chess engine with
   move generation, check, mate, castling, en passant and PGN export in one file. Builds on: none.
   Spec template: $(pwd)/pi/localagent-workflow/templates/unit-spec.md" \
     | grep -c '"type":"message_end"'
   ```

   By hand there is no limit, so this measures how far a hopeless unit gets in fifteen turns and
   whether the agent budget shows in the per-turn `usage.output`. The limit itself and the gate
   are then one orchestrator session with the flag, watched: the first worker `DONE` must come
   back with `· tests: … · changed: …`, and a unit re-briefed as the chess engine must come back
   `BLOCKED … turn budget 15` naming the log.

3. **The todo CLI**, same prompt and profile as T-018, `runs/T-019-cli/` with `report.sh`.
   Read off: turns per dispatch, compactions inside children (target 0), orchestrator turns per
   unit (target 2), wall clock (target under 60 minutes), and whether each worker held
   spec -> tests -> code in its session log. A child that compacts at 4096 means the turn
   limit is too high for that budget, not that the budget is too small.

4. **Only then Tron**, with the plan cut to eight or nine units and two stop conditions set
   before the start: a second `BLOCKED` on the same unit after a re-cut ends the run, and a
   wall clock of three hours ends it too. Past either, the result is the number, not the game.

## Verify

Same profile (`dedicated`, CTX 64000, BUDGET 8192, AGENT_BUDGET 4096), `runs/` next to the
others, `report.sh` for the numbers. Targets for the CLI: under 124 turns and under 1:40 with
the same clean result, no compaction in any child. If a worker does not hold the spec-first
order, or the CLI does not finish inside the turn limits, record it in `docs/localagent.md`
as the shape's limit rather than tuning further.
