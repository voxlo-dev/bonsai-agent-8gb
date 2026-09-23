# T-019 — Cut what the localagent workflow still costs per unit

- **Summary:** **Frozen 2026-09-23**; the report is [at the end](#report-the-workflow-is-frozen-2026-09-23). Reshaped three times: after Tron (one worker per unit, harness gate, turn limit, 4096 agent budget), after the first CLI run (limit as a backstop, harness-written run log, shorter prompts), and during this ticket's own runs (tests decide, no revert). The CLI now finishes clean at the cost of working alone; Tron fails on what the model can do, not on the harness
- **Status:** frozen until a stronger local model; no further runs
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

## What was on the branch for the 2026-09-22 runs

| Where | Change |
| --- | --- |
| `config.env`, `bin/bonsai-pi`, `scripts/pi.sh` | `AGENT_BUDGET` 4096 and `AGENT_BUDGET_MSG` as a second `models.json` entry `<alias>-agent` with `samplingParams`; `AGENT_MAX_TURNS` 15. Both reach the extension through the environment |
| `pi/extensions/localagent/index.ts` | children run on the agent model; a dispatch past the turn limit is killed and returned as `BLOCKED … turn budget`; after a `DONE` the tool runs the `test` command and appends `tests:` and `changed:` |
| `pi/localagent-workflow/` | `localagent-worker` replaces spec-architect, implementer and reviewer; skill, orchestrator and templates follow: briefs carry facts only, the plan entry inline, units of one file and three to five criteria, no numeric rule anywhere in a prompt |
| `docs/localagent.md` | the Tron numbers, the new shape and what it is answering, and the plain statement that it has not run yet |

## What was run on 2026-09-22, in this order

**Steps 1 to 3 ran; the results are below. Step 4 was not started. Superseded by
[the second reshape](#the-session-logs-and-the-second-reshape-2026-09-23).**

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

## The session logs, and the second reshape (2026-09-23)

The CLI run's orchestrator and child logs, read turn by turn, are in
[`docs/localagent.md`](../docs/localagent.md#the-t-019-cli-run-where-the-turns-went): per dispatch,
where the turns went. The short version: none of the three `BLOCKED`s was a unit too large (two
were green or at their final test run); the spec -> tests -> code -> run core is five to seven
turns, and the rest of a dispatch was orientation before it and an unasked check after; the
orchestrator spent 18 of 35 turns on `STATE.md` and `PLAN.md`. The model over-attends to whatever
is in reach, so the second reshape takes things away instead of adding bounds:

| Commit | Change |
| --- | --- |
| `5865555` | `AGENT_MAX_TURNS` 15 -> 30, a backstop against a runaway; no prompt names a limit any more (worker, e2e 12, docs 8 gone). The `BLOCKED` no longer says "too big, re-cut" |
| `bf1aa17` | `dispatch` snapshots the work tree (a git tree through a private index; the user's index and HEAD untouched). `changed:` is this dispatch's diff; a `BLOCKED` or `ESCALATE` dispatch is reverted. Status line: Markdown stripped, `NO STATUS: …` when there is none. Turns and minutes on every line |
| `fe52d27` | `dispatch` appends every result to `localagent/LOG.md`; `STATE.md` and its template are gone, the orchestrator writes `PLAN.md` only. The protocol is the orchestrator prompt alone (SKILL.md, 164 lines, is a pointer and no longer offered). One failure rule instead of the five-row table |
| `76020f4` | Worker prompt: the four steps and the `ESCALATE` exits, the spec's two sections inline, `unit-spec.md` gone. Scaffold: installs, does not run the empty suite, writes no placeholder |
| `1f42d83` | the after-snapshot is taken before the harness's test run, so `__pycache__` is not the agent's |

Prompts and templates: 539 lines before, 296 after. Verified here against a scripted stand-in
endpoint, in pi: `DONE` with a green run, `ESCALATE` reverting a modified and an added file,
`NO STATUS`, a runaway cut off at a lowered limit and reverted, all four lines in `LOG.md`. Not
verified: anything a real model does with the shorter prompts.

## What to run next

1. **`./install.sh pi`** on the branch. `$PI_AGENT_DIR/extensions/localagent/workflow/templates/`
   holds `PLAN.md` only; `bonsai-pi --localagent` announces "at most 30 turns each".

2. **The todo CLI**, same prompt and profile as T-018 and the 2026-09-22 run, in
   `runs/T-019-cli-2/` with its own `git init` in the work dir (the snapshot needs a repo, and
   without its own `changed:` would describe this one). Let it finish: U1 to the last unit, e2e,
   docs. `localagent/LOG.md` gives turns and minutes per dispatch directly; the orientation count
   comes from the child logs:

   ```bash
   # per dispatch: the turn of the first write or edit, and the total
   python3 -c '
   import json, sys
   for f in sys.argv[1:]:
       n = first = 0
       for l in open(f):
           m = json.loads(l).get("message") or {}
           if m.get("role") != "assistant": continue
           n += 1
           if not first and any(c.get("name") in ("write", "edit") for c in m["content"]): first = n
       print(f.rsplit("/", 1)[-1][:19], "first write at turn", first, "of", n)
   ' "$PI_AGENT_DIR"/sessions/*T-019-cli-2-work*/dispatch/*/*.jsonl
   ```

   | Read off | 2026-09-22 | Target |
   | --- | --- | --- |
   | wall clock, whole CLI | 1:00 for U1-U2 (T-018: 1:40 for all) | < 1:00 for all |
   | orchestrator turns | 35 for two units | < 20 for all |
   | orchestrator turns on the ledger | 18 | only the plan and a re-cut |
   | `BLOCKED` | 3 | 0 |
   | first write in a worker | turn 4 to 7 | turn 1 or 2 |
   | compactions in children | 0 | 0 |
   | spec -> tests -> code in each worker | held | held |

   If the first write still comes at turn four or later, the orientation is not the prompt's
   doing and a shorter prompt will not fix it; record that rather than tuning further.

3. **Only then Tron**, the plan cut to eight or nine units, with the stop conditions set before
   the start: a unit's second failure ends the run (the orchestrator's own rule now), and three
   hours of wall clock ends it too.

## Step 2, first attempt: the orchestrator skipped the workflow (2026-09-23)

Branch at `9f91a49`, T-018's prompt unchanged, `runs/T-019-cli-2/` (`work-solo/`,
`report-solo.txt`). **No dispatch, no `PLAN.md`.** The orchestrator prompt reached the model, since
its first reasoning quotes the plan gate. It then read "This is a test environment" as a
benchmark, called the task small, and built it alone: `todo.py` plus a 31-check
`test_todo.sh`, all green, in **0:33, 22 turns, 48k output tokens**. That wall clock includes about
four minutes before a user `Resume.`. Nothing in the reasoning names a limit or a failure. It was a
choice, and "You write `localagent/PLAN.md` and nothing else" did not stop it.

Two things follow. **This is the baseline the workflow has to beat on this task**: the best
workflow run so far (T-018, 1:40, 124 turns, 164k) cost three times the wall clock and turns for
the same four commands. And the shorter orchestrator prompt no longer holds the session to its
role. The 2026-09-22 run and T-018 both dispatched on the same user prompt, and so far this is one
run, not a rate.

The repeat adds one closing line to the prompt, "Use the localagent workflow for this task."
(`prompt.txt`, the original kept as `prompt-solo.txt`). That makes it no longer T-018's prompt
word for word. The alternative, a sentence in the orchestrator prompt saying no task is too small,
was not taken: it would be the first rule added back after a reshape that took rules away.

## Step 2, second attempt: the tests should decide, not the status line (2026-09-23)

The prompt with the added line, `work-2/`, `report-2.txt` (its first orchestrator is the solo run,
which shared the path). It was stopped after **49 minutes with two of five units**: scaffold 4
turns, U1 `DONE` green in 18. The plan gate and the escalation rule both held: U2 was
`BLOCKED` twice, re-cut in between, and the run stopped on the second failure. Neither `BLOCKED`
was a unit too large:

- **U2, first attempt:** 26 tests green at turn 26. The next four turns went to checks nobody
  asked for: a subprocess probe, counting the criteria again, a `NOTES.md`. It had written no
  status line when the 30-turn backstop cut it off, and the revert threw the finished unit away.
  This is the third time: two of the 2026-09-22 `BLOCKED`s were green too. "Green: return." in
  the worker prompt does not hold.
- **U2, second attempt (re-cut to `add` only):** about 14 turns went on why unittest did not find
  the new test file, whose class lacked `unittest.TestCase`. It still had one red test (chmod) at
  turn 30.
- Both attempts also lost turns to a plan error: `todo.py` next to the package `todo/`.

**Change, in `dispatch`:** the test command decides whether a dispatch's work stays.

- Whenever the agent runs a bash command containing the unit's test command, the child is paused
  (SIGSTOP) and the harness runs the exact test command itself. A pipe, a subset or an exit code
  does not decide. **A green run after a red one ends the dispatch as `DONE`**: the tests were
  written before the code, so that is the worker's own "done", and the checks that follow it go
  away. Without a red run first (a baseline check on the earlier units' tests) the dispatch goes
  on.
- A dispatch cut off at the backstop that changed something outside `localagent/` and whose tests
  are green is `DONE`, kept. Only a red one is `BLOCKED` and reverted.

How much of this depends on the stack: the verdict does not, since it is the plan's test command
under `bash -lc`, as in the gate after a `DONE`. The trigger does. The agent's command must
contain the test command as written (whitespace ignored). `npm test -- foo` matches `npm test`;
`npx jest` or a bare `pytest` against `python3 -m pytest` does not. When the trigger misses, the
dispatch ends the old way, with its status line or at the backstop, where the second rule still
applies.

Verified against a scripted stand-in endpoint in pi: red, then code, then green ends as `DONE`
and never reaches the step after it; built without running the tests and cut off at a lowered
limit, green, is `DONE` kept; the same with wrong code is `BLOCKED` reverted. Not verified: what
a real model does with it.

## Step 2, third attempt: the first clean run (2026-09-23)

Branch at `1f9fa84`, same prompt, `runs/T-019-cli-2/work/`. **Finished with no `BLOCKED`**: plan,
two units, e2e `PASS`, README. The result works: the tests pass, and an unknown command, a
missing id and a corrupt store each fail with a clear message and exit 1.

| Read off | this run | solo run | 2026-09-22 | target |
| --- | --- | --- | --- | --- |
| wall clock | 0:34:31, 2:46 of it at the plan gate | 0:33, ~4 min before a `Resume.` | 1:00 for U1-U2 | < 1:00 ✓ |
| orchestrator turns | 20 | - | 35 for two units | < 20 (at the line) |
| orchestrator turns on the ledger | 4 | - | 18 | only the plan ✓ |
| `BLOCKED` | 0 | - | 3 | 0 ✓ |
| dispatches | U1 8 turns, U2 13, e2e 13, docs 7 | - | | |
| first write in a worker | turn 3, 2 | - | turn 4 to 7 | 1 or 2 (close) |
| compactions in children | 0 | - | 0 | 0 ✓ |
| turns / output tokens | 61 / 55k | 22 / 48k | 105 / 106k | |

The plan cut the CLI into two units instead of five, and no scaffold ran (stdlib only). U2 is
the first dispatch ended by the harness at green after red. **On this task the workflow now costs
what working alone costs.** For about the same time and 15% more output it also leaves a spec
per unit, an e2e check and a README.

**Order: one worker of two did not hold it.** U1 wrote `spec.md` and `todo.py` in the same turn
(3), then the tests (4). Its tests were never red, so the green-after-red gate had nothing to
fire on. It ended itself after one unasked sanity-check turn. U2 held spec -> tests -> code.
The gate depends on the order: a worker that writes code first is not cut short at green. Under
this ticket's Verify rule, a broken order means the order goes back into the prompt in words. But
the worker prompt already says "Written before the code". One of two is not a rate yet.

**Next:** Tron (step 3), which is where the workflow either earns its cost or does not. Before
that, possibly a second CLI run, to see whether the order slip repeats.

## Step 3, Tron: the revert goes (2026-09-23, run in progress)

`runs/T-019-tron/`, started on `7d85620`. The scaffold dispatch hit the 30-turn backstop during a
long Playwright install and was reverted. The revert deleted `package.json`, the config and the
lockfile, and left `node_modules` half removed, because the snapshot had caught the install's
files as the dispatch's own. The orchestrator then split the scaffold in two to fit the limit.

So the revert has now cost a green unit (CLI, second attempt) and broken a dependency tree. What
it guarded against, a retry passing the gate on inherited work, is already visible in the
per-dispatch `changed:`. **Removed** after this run started (the running session keeps the
version it loaded): a failed dispatch's files stay, the next dispatch starts on them with a clean
context, and the turn limit stays as the backstop. Verified against the stand-in endpoint: green
after red `DONE`, green at the limit `DONE`, red at the limit `BLOCKED` with its files in place.
`./install.sh pi` after the Tron run, not during it.

A second change came before the restart. The orchestrator also wrote a test file next to
`PLAN.md`, which its prompt forbids. The push to act came from the server's `BUDGET_MSG`, "write
the files with your tools, one at a time", read after a cut-off thinking block. It now reads "make
your next tool call" (`config.env`; first worded "make your next step one tool call", shortened before Tron attempt 2 started). The agents keep their own message, since writing
files is their job. This touches every session on the server, not only the workflow. T-002's
solo Tron run, the comparison here, ran with the old wording.

The first attempt was stopped after 34 minutes (scaffold `BLOCKED` and reverted, split, second
half `DONE`) and kept as `work-1/` with `report-1.txt`. The restart runs without the revert and
with the new message.

## Verify

Same profile (`dedicated`, CTX 64000, BUDGET 8192, AGENT_BUDGET 4096), `runs/` next to the
others. The CLI finishes clean, under 1:00, with no `BLOCKED` and no compaction in any child. If a
worker does not hold spec -> tests -> code with the shorter prompt, that is the finding, and the
order goes back into the prompt in words before anything else changes.

## Report: the workflow is frozen (2026-09-23)

**Decision (the user's): the localagent workflow stays as it is, as a feature, and is not
developed further. No more runs until a stronger local model is out.** Too much of what fails
now fails on what the model can do, and nothing in these runs suggests that more harness work
would change that for this model.

### What the runs showed

| Run | Result | Wall | Turns | Output |
| --- | --- | --- | --- | --- |
| CLI, solo, no workflow | works, 31 checks | 0:33 | 22 | 48k |
| CLI, workflow, 2026-09-22 | stopped, 2 of 3 units | 1:00 | 105 | 106k |
| CLI, workflow, attempt 2 (revert) | stopped, 2 of 5 units | 0:49 | 96 | 77k |
| **CLI, workflow, attempt 3** | **works, no `BLOCKED`, e2e `PASS`, README** | **0:34** | 61 | 55k |
| Tron, solo (T-002) | a working game with tests | 1:30 | 108 | 118k |
| Tron, workflow, attempt 1 | stopped at 0:34: the revert broke `node_modules` | 0:34 | 68 | 58k |
| **Tron, workflow, attempt 2** | **stopped at 2:50, the game core not finished** | 2:50 | 123 | 225k |

On the CLI the workflow now costs what working alone costs, and leaves a spec per unit, an e2e
check and a README behind. On Tron it cost twice the solo run's time and output, and had not
finished its first unit, the pure game core, when it was stopped. The core was re-cut twice
(U1 → U1a/U1b → U1b-a/U1b-b), and every dispatch took 40 to 60 minutes.

### What was the harness, and is fixed

In commit order on this branch, after `9f91a49`:

1. **The tests decide, not the status line** (`2774fec`). The agent's first green run of the
   test command after a red one ends the dispatch as `DONE`. The harness pauses the child and
   runs the exact command itself, so a pipe or a subset does not decide. It cuts the tail of
   unasked checks after green, which had cost the CLI's U2 its whole dispatch. It fired once in
   each of the two runs that followed it.
2. **No revert** (`9f07a8a`). The revert threw away a green unit (CLI attempt 2) and deleted
   `package.json` and half of `node_modules` under a scaffold the backstop had cut off
   mid-install (Tron attempt 1). A failed dispatch's files stay, and the next one starts on them
   with a fresh context.
3. **The budget message asks for one tool call** (`186bb45`). "Write the files" led the
   orchestrator to write a test file next to its plan.
4. **A cut-off dispatch is `BLOCKED`, whatever the suite says; no split rule for it; the scaffold
   proves the test command fails on an empty suite** (the commit with this report). The
   intermediate rule, green at the backstop counts as `DONE`, failed twice in Tron attempt 2:
   - Its result line said "ran 30 turns", and the orchestrator's rule "a dispatch that ran out of
     turns: split the unit" won over the `DONE`. It re-cut twice and noted "contradictory
     signals".
   - The green was hollow. `npm test` was `node --test`, which does not pick up `*.spec.mjs` and
     exits 0 when it finds no test at all, so U1's syntax-broken test file read as green.

   `pytest`, `unittest` (3.12+), `jest`, `vitest` and `mocha` fail on an empty suite, and
   `node --test` does not. The scaffold now runs the command once on no tests and changes it
   until it fails. It hands the final command back on its result line, and the orchestrator uses
   that line. The split rule was left over from the idea that a cut-off unit is too large, which
   the 2026-09-22 logs had already disproved. Verified against the stand-in endpoint: green after
   red is `DONE`; cut off, green or red, is `BLOCKED` with its files in place. **Not verified with
   the real model**: this last change never ran on it.

### What is the model, and is not fixable here

From the Tron worker sessions (`runs/T-019-tron/`, dispatch logs):

- **About two minutes per turn, 4k to 9k output tokens per turn.** Whole test files are
  rewritten (9k tokens each), and game ticks are simulated by hand in the thinking to derive
  expected positions.
- **A compaction every 10 to 12 turns inside a worker, 7 in all.** After one, the worker no
  longer knows what is on disk. U1 "found" an `units/U1/game.js` that did not exist, and argued
  with itself for four turns about whether its own write had landed.
- **Edits that do not match, then full rewrites.** Syntax errors in its own tests (an apostrophe
  in a test name, missing brackets), then turns spent finding them.
- **Test-runner discovery took 15 turns** in U1b, and several turns in U1a, which ran experiments
  on Node's test discovery.
- **U1 deleted the scaffold's `tests/e2e.mjs`** in its sixth turn.
- **The plan had three units, not the eight or nine the ticket asked for**, and it passed the
  gate. Smaller units would have lowered the context pressure; they would not have removed any
  of the above.

None of these is a harness decision. A prompt could name some of them, but every rule added to
a prompt so far was either ignored or checked with turns. The CLI, where units are small and
the logic trivial, works. Tron, where one unit needs real reasoning, does not.

### What stays open

- **Resume when a stronger local model is out.** Rerun the CLI (`runs/T-019-cli-2/run.sh`) and
  Tron (`runs/T-019-tron/run.sh`) as they are. Both scripts check the installed shape. The
  comparisons are the solo runs: CLI 0:33, Tron 1:30.
- **The fourth change has not run on a real model.** It is the first thing the next run shows.
- Logs: `runs/T-019-cli-2/` (`work-solo`, `work-2`, `work`, with reports),
  `runs/T-019-tron/` (`work-1`, `work`, with reports). They are gitignored and kept.
