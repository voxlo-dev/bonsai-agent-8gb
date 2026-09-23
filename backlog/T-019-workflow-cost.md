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

**Steps 1 to 3 ran on 2026-09-22; the results are below. Step 4 was not started.**

The four changes are one shape; they are measured together. The comparison is against T-018's
todo-CLI run (124 turns, 1:40, 164k output tokens) on the same profile.

1. **`./install.sh pi`** on the branch. Check `$BONSAI_HOME/pi-agent/models.json` has the
   `bonsai-27b-agent` entry with `samplingParams`. Then, with `bonsai-server` up, one request
   by hand to confirm the server accepts the other model name and the smaller budget:

   ```bash
   source config.env
   curl -sS "$SERVER_URL/v1/chat/completions" -H 'content-type: application/json' -d '{
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

4. **Only then Tron** *(not run — see the findings below)*, with the plan cut to eight or nine
   units and two stop conditions set before the start: a second `BLOCKED` on the same unit after
   a re-cut ends the run, and a wall clock of three hours ends it too. Past either, the result is
   the number, not the game.

## What the runs showed, 2026-09-22

Steps 1 to 3 ran on `t019-workflow-cost` at `9b32420`, profile `dedicated`, `AGENT_BUDGET` 4096,
`AGENT_MAX_TURNS` 15. Step 4 (Tron) was not started: the CLI run was stopped at an hour, because
the three findings below are what it had to give. Logs: `runs/T-019-turn-limit/` (2a),
`runs/T-019-gate/` (2b), `runs/T-019-cli/` with `report.sh` and `report.txt` (3).

**1. The shape works. The agent model, the harness gate and the turn limit all do what they
promise.** Step 1: the server takes `bonsai-27b-agent` and the smaller budget (277 reasoning
characters at `reasoning_budget_tokens` 64). Step 2b: the plan gate held, the first worker came
back `DONE … · tests: green · changed: …`, and the chess unit came back
`BLOCKED … 15-turn budget … re-cut it` with its log path. The orchestrator went further than the
test asked: it refused the oversized unit at the gate before dispatching it, re-cut it after the
first `BLOCKED`, and stopped the run itself after the second rather than grinding. Every worker
that reached code held spec → tests → code.

**2. The turn limit does not cut where the cost is.** The CLI run, same prompt and profile as
T-018:

| | T-019 | T-018 | target |
| --- | --- | --- | --- |
| wall | 1:00 (stopped, U3 not started) | 1:40 | < 1:00 |
| turns | 105 | 124 | < 124 |
| orchestrator turns | 35 | | 2 per unit |
| agent turns | 70 | | |
| compactions in children | **0** | | 0 |
| output tokens | 106k | 164k | |

Six dispatches for what the plan cut into three units: `scaffold` 15 turns `BLOCKED` then 8 turns
ok, U1 10 turns `DONE` green, U2 `BLOCKED` at 15, re-cut `BLOCKED` at 15, third attempt `DONE`.
The limit did not catch units that were too large — U1 did the same kind of work in 10 turns. It
caught a scaffold and a CLI router, work nobody would call oversized. Two of the three `BLOCKED`s
cost a full 15-turn dispatch each to learn nothing.

The 4096 budget is confirmed by 2a: a hopeless unit (chess engine, one file) ran its 15 turns and
compacted once at turn 13, at 55k context — the worker rewrote the whole spec four times and the
whole file four times, about 5k context per rewrite. At CLI-sized units no child compacted at all.
So the ceiling is the file size a worker rewrites, not the turn count.

**3. A blocked dispatch leaves its work on disk, and the next one inherits it.** The third U2
dispatch returned `DONE · tests: green` after **3 turns and 34 seconds without writing a single
file**: the two `BLOCKED` attempts had left working code behind, the harness ran the tests, they
were green. The gate cannot tell "built it" from "found it". The same root cause makes `changed:`
cumulative — nothing is committed between dispatches, so U1's line already listed the scaffold's
files, and in 2b the orchestrator spent a turn wondering whether a worker had touched another
unit's files. In 2b the orchestrator also read a leftover draft from the cut-off attempt and had
to reason about whether it was allowed to keep it.

Two smaller things, both in the logs: the orchestrator spends turns interpreting the skill's
escalation table (whether a re-cut counts as an attempt), and the model sometimes writes its
status line in Markdown bold, so a verdict arrives as `DONE**`.

**What this leaves to decide** (T-030, and the reviewer question the branch was opened for): the
turn limit per dispatch is the wrong knob if it fires on a scaffold; a blocked dispatch needs its
tree reverted, or the gate needs to state what the dispatch itself changed.

A note on the measurement, not the shape: the work dir needs its own `git init`, or the gate's
`changed:` reports this repo's status, since `runs/` is gitignored. Both run scripts do it now;
T-018's did not, so its `changed:` lines were never about its own work dir.

## Verify

Same profile (`dedicated`, CTX 64000, BUDGET 8192, AGENT_BUDGET 4096), `runs/` next to the
others, `report.sh` for the numbers. Targets for the CLI: under 124 turns and under 1:40 with
the same clean result, no compaction in any child. If a worker does not hold the spec-first
order, or the CLI does not finish inside the turn limits, record it in `docs/localagent.md`
as the shape's limit rather than tuning further.
