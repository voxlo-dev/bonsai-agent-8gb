# The localagent workflow

A multi-agent build pipeline for a weak local model: plan gate, then one worker dispatch per
small unit (spec -> tests -> code -> test run), then e2e and docs. It lives in
[`pi/localagent-workflow/`](../pi/localagent-workflow/) and runs as `bonsai-pi --localagent`
through the extension in [`pi/extensions/localagent/`](../pi/extensions/localagent/).

Its point is not throughput. A 27B model holds a feature badly and forgets what it decided three
turns ago; this pipeline gives every step a tiny single-purpose context and writes the run's memory
to disk instead of the window. That costs turns, and **the turn count is the bill** - see
[Economics](#economics). Reach for it when the model is weak or context discipline is the priority,
never for a one-line fix.

This file is the workflow's home: the shape, the two measured runs, and why each piece is what it
is. The window and compaction numbers it runs inside are in [`dev.md`](dev.md#context-budget).

## Status

**Experimental.** The core of this repo - `bonsai-server` and `bonsai-pi` - is not; this workflow
is. Experimental here means two things: it may change without a deprecation note, and its numbers
come from one machine and a handful of runs.

| | |
| --- | --- |
| Known to work | one small feature (a todo CLI), planned interactively with the user first, on the CUDA backend, in the previous three-agent shape |
| Not shown to work | **the current shape** (one worker per unit, harness gate, turn limit, agent budget) has not run yet; large tasks (the Tron run below was aborted after five hours); anything on the Vulkan backend at 7 tok/s |
| Measured | three runs, T-013, T-018 and the Tron run, all below in [Economics](#economics) |
| Open | [T-013](../backlog/T-013-localagent-first-run.md), [T-019](../backlog/T-019-workflow-cost.md), [T-031](../backlog/T-031-sharp-chat-template.md) |

Its ancestor was evaluated across eight local models before this repo existed, and no model of
that generation produced a working artifact through it; one held the whole process. That series is
[the model comparison](model-comparison.md), and it is the most honest description available of
what a multi-agent workflow costs a local model.

## Shape

| Phase | Step | Agent |
| --- | --- | --- |
| Plan | plan with the user, **gate**, scaffold once | orchestrator, `localagent-scaffold` |
| Build, per unit | pending -> done: `spec.md`, one test per criterion, the code, the test run | `localagent-worker` |
| Finalize | one e2e flow where the plan names a surface, then the docs | `localagent-e2e`, `localagent-docs` |

The orchestrator is the session itself: pure control flow, `PLAN.md` and `STATE.md` its only
writes, `dispatch` its only way to get anything built. `STATE.md` is the ledger a context reset
must be survivable from. The gate after a unit is the harness's: `dispatch` runs the test command
and lists the changed files in the status line it returns.

Until the Tron run this was three agents per unit - spec-architect, implementer, reviewer - and
before T-018 four, with a wall between test-author and implementer. Each cut is measured below.

## Running it on pi

The workflow is the author's own, written for OpenCode in the project thesis behind
[the model comparison](model-comparison.md), where its seven agents were run against eight local
models. Its skill and the orchestrator prompt describe pi now: no
agent registration, `dispatch({ agent, brief })` as the only way to start an agent, template paths
passed absolute. `codegraph`, which this setup does not have, is gone from the agent prompts; the
agent frontmatter keeps the OpenCode dialect. `install.sh pi` copies the extension with the
workflow into `$PI_AGENT_DIR/extensions/localagent/`. Without the flag the extension registers
nothing.

**Own extension, not pi-subagents.** [pi-subagents](https://pi.dev/packages/pi-subagents) 0.69.0
was tried first, installed into a scratch agent dir against a stand-in endpoint:

- Parent prompt with it: 31.3k chars (system prompt + tool schemas), without it 5.8k. The
  `subagent` tool alone is 18.9k chars, of which 13.8k is a parameter schema that none of its
  `toolDescriptionMode`s shortens; a minimal custom description still left 29.1k. The
  orchestrator needs `{agent, brief}`.
- It checks `permission:` per tool only (`read: deny`), no path globs, so it rejected the
  implementer's OpenCode block - then still a wall, see [Economics](#economics) - as an invalid
  agent definition.
- Its builtin `worker` answers to the alias `implementer`: a small model that drops the
  `localagent-` prefix would silently reach an agent that is not this workflow's.

With this extension the parent prompt is 12.3k chars against 6.8k without the flag: 764 for
the `dispatch` tool, the rest the orchestrator prompt and the skill entry - the workflow itself.

**Each agent is a separate `pi -p` process** (the pattern of pi's own
`examples/extensions/subagent`), started from pi's own entry point so it runs the pinned version:

- `--no-extensions --no-skills --no-prompt-templates --no-context-files`: nothing the orchestrator
  loaded reaches it, not `AGENTS.md`, not `dispatch` (no nested dispatch). The brief is its
  whole context, as the workflow demands. pi's base prompt stays: the agent prompt is appended
  (`--append-system-prompt`), since the base prompt explains the tools to a small model.
- Dispatches are queued, one at a time: the server has one slot (`--parallel 1`), and the
  workflow requires the sequential shape anyway.
- **Agents run on a second `models.json` entry, `<MODEL_ALIAS>-agent`**, the same server with
  `samplingParams` that send `reasoning_budget_tokens` = `AGENT_BUDGET` (4096) and their own
  budget message per request; the fork's server reads both from the body and falls back to its
  flags. The orchestrator keeps `BUDGET`. Why: inside a dispatched child no user message follows
  the brief, so the template keeps every earlier turn's thinking in the prompt (the
  `preserve_thinking` switch only drops thinking *before* the last user message, see
  [dev.md](dev.md#thinking-in-the-prompt)). At 8192 a child crossed pi's 48k compaction trigger
  in five or six turns, every time - the Tron numbers below.
- **A dispatch is cut off after `AGENT_MAX_TURNS` (15)** and comes back as a `BLOCKED` tool
  error naming the log. The prompts' own "two attempts, then escalate" rule was never once
  followed: the Tron U2 implementer ran 332 turns.
- **After a `DONE`, `dispatch` runs the test command** the orchestrator passed as `test` and
  appends `· tests: green|RED (exit N): <tail>` and `· changed: <git status files>`. The
  orchestrator used to spend eight or nine turns on that gate, inventing checks as it went.
- The result is the agent's status line (`DONE`, `FIXES_REQUIRED`, `ESCALATE`, `BLOCKED`,
  `PASS`, `NO_SURFACE`), the last one in its final message, so a chatty reply does not fill the
  orchestrator's window. **Only that line comes back**, which is why an agent with something to
  say writes a file and names it. A child that ends on anything but `stop` - `length` included,
  see [Context budget](dev.md#context-budget) - or exits non-zero comes back as a tool error,
  which the workflow treats as `BLOCKED`.
- Its session goes to `sessions/{cwd-slug}/dispatch/{orchestrator-session-id}/`, beside the
  orchestrator's own log. That JSONL is written live, so a second terminal can follow what an
  agent is doing while it runs.

**The plan gate is told, not guessed.** `ctx.hasUI` goes into the orchestrator's system prompt as
a `## Session` line: a human is here, so stop and wait - or nobody is, so record the auto-approval.
In T-013 the model decided this itself and wrote "plan auto-approved - headless test run, no human
reachable" into `STATE.md` while a human sat in front of it. pi knows the answer; the model does
not.

**Flag order.** pi hands an unknown flag the next argument as its value when that argument does
not start with `-`. Extension flags count as unknown there, so `bonsai-pi --localagent "task"`
swallows the task. `--` ends option parsing and makes the rest the prompt:
`bonsai-pi --localagent -- "task"`, with or without `-p`.

Verified against a scripted stand-in endpoint that plays orchestrator and implementer: without
the flag no `dispatch` and no skill; with it the orchestrator prompt and the skill are in the
system prompt, the child has no `dispatch` and no `AGENTS.md`, and the orchestrator gets
`DONE src/foo.ts` from a reply that wraps it in prose.

## Economics

Two runs of the **same prompt** (a todo CLI: add/list/complete/remove over a JSON file, clear
failures with a non-zero exit) on the same profile (`dedicated`, CTX 64000, BUDGET 8192), one
before the rebuild and one after, then the study's Tron prompt in the T-018 shape. Scripts and
artifacts: `runs/T-013-localagent-cli/`, `runs/T-018-workflow-without-tdd/` and
`runs/T-013-localagent-tron/` (gitignored, kept), `report.sh` beside each.

| | T-018, spec -> implement -> review | T-013, TDD behind a wall |
| --- | --- | --- |
| Wall clock | 1:39:48 | 2:14:20 |
| Turns | 124 (30 orchestrator + 94 agents) | 198 (60 + 138) |
| Output tokens | 164 418 | 210 593 |
| Product / test / artifact lines | 133 / 271 / 302 | 181 / 373 / 675 |
| Rework rounds | 0 | several, one of them a 46-minute deadlock |

Both produced a working CLI. Wall clock is ~99 % model time on this machine, and only 14 of
T-013's 198 turns had to reprocess their prompt, so context reloading after a dispatch is not the
cost: **the turn count is the bill**, and every turn burns a full thinking budget.

Where the time went, per agent:

```
                          T-018      T-013
implementer               46:42      30:37
reviewer                  17:54      12:03  (as test-author)
orchestrator, between     19:57      37:05
spec-architect             9:08      22:30
docs                       3:26       9:13
scaffold                   2:38       5:23
e2e                           -      17:26
```

**The wall was the expensive part.** In T-013 the test-author wrote
`assertEqual([(1, "a", False)], json.load(f))`, which parsed JSON can never satisfy. The
implementer was not allowed to look: 23 turns and 29 minutes reconstructing the expectation from
failure output, then the spec-architect ruled `ESCALATE unfounded` - wrong, the test really was
broken - and the test-author fixed it in two minutes. 46 minutes, 34 % of the run, for a one-line
defect that is obvious on sight. That is the wall's built-in economics: it costs exactly when the
test is wrong, and a 27B model writes wrong tests often. Note which half the blindness protected -
the blind *test* was broken, the blind *code* was correct. The spec was the reliable artifact, not
the blindness.

Read the table carefully, though: **the implementer got more expensive, not cheaper** (+16 min),
because it now verifies itself, and **half the saving is an e2e step that did not run** - the
T-018 orchestrator judged a single-process CLI to have no e2e surface, where T-013's ran e2e and
produced a 317-line driver with 88 checks against a one-flow rule. Both calls are defensible under
the skill, so that 17 minutes may come back on another run. The structural savings are the
spec-architect (stubs gone) and the orchestrator (half the sub-steps, half the turns).

### The Tron run: where the three-agent shape stops

The study's prompt (an online two-player Tron game, browser client, relay server), same profile,
the T-018 shape plus the first T-019 commits, 2026-09-21/22. **Aborted after about five hours
with one of three units done.** What the session logs say, orchestrator and children:

```
                              minutes   turns   compactions
scaffold, first attempt          19       37        0   killed: fought node --test, then wrote product code
scaffold, second attempt         11       28        0
U1 spec-architect                49       20        2   spec on disk after 24 min; then 25 min of wc -l and rewrites; killed
U1 implementer                   27       21        1
U1 reviewer                      32        -        -   DONE, 8 of 8 met: no finding, as in T-018
U2 spec-architect                17       16        0
U2 implementer                  235      332       12   aborted; never escalated
orchestrator, between            28       34        0   17 turns on the two gate checks alone
```

Three mechanisms, each visible in the logs:

- **Thinking accumulates inside a child and compacts it.** Base context 3k, plus up to 8k of
  thinking per turn, trigger at 48k: the U1 spec-architect compacted two minutes after writing
  its file, the U2 implementer every fifteen minutes, its summaries growing to 19k characters and
  becoming the context. After a compaction the agent no longer knows it is done: the second U1
  summary says "task complete", and the agent reads the file again to trim five lines.
- **Rules with numbers are checked with turns.** "~80 lines" became `wc -l` five times through
  two compactions. "Two attempts, then escalate" was never followed in 332 turns. Prompt-only
  bounds do not bound this model.
- **The orchestrator restates and invents.** Its briefs (600-1000 tokens each) told the
  implementer to write tests, against that agent's prompt, so the unit got 209 lines of author
  tests and then 191 lines of reviewer tests for the same eight criteria. After each `DONE` it
  ran eight or nine turns of checks the skill did not ask for: I/O scans, test counts, commit
  juggling.

The reviewer, across every run, has now reviewed three units and found nothing, at 18, 32 and 32
minutes. That was the T-019 stop condition: "if the reviewer waves a real defect through, the
split buys nothing". It never got a defect to wave through, and it cost a third of every unit.

## The pieces, and what each one is answering

- **One worker per unit: spec, then tests from its criteria, then code.** The three-agent split
  bought one thing, tests that say what was asked for instead of what was built, and the Tron run
  priced it at two extra dispatches per unit for a reviewer that has never found anything. The
  order survives inside one context: the worker writes `spec.md` (interface in prose, three to
  five criteria), then a test per criterion, then the code. T-018 had already found that the spec
  was the reliable artifact, not the blindness; T-013 had shown what a wall costs when the blind
  test is wrong (46 minutes, a third of the run).
- **`spec.md` in prose, no stub files, no line count.** Stubs existed only to make two blind
  halves agree on a signature, at 7-10 minutes per unit. The "~80 lines" cap cost the Tron
  spec-architect 25 minutes of `wc -l`; the template now says the spec is measured in what it
  says, and no prompt in the workflow carries a number the model could check with a tool.
- **The gate is the harness.** `dispatch` runs the tests after a `DONE` and lists the changed
  files. The orchestrator's version of that gate was 17 turns per unit in the Tron run.
- **The turn limit is the escalation rule.** Fifteen turns per dispatch, enforced by the
  extension. A unit that does not fit is re-cut in the plan, which is the one correction that is
  cheaper than any rework.
- **Units are one file and three to five criteria** because a dispatch is fifteen turns. The
  Tron plan had three units for a game; the same plan is eight or nine.
- **Agents think with 4096, the orchestrator with 8192.** The child's context is the brief plus
  its own thinking, and at 8192 the thinking alone filled the window in five turns.
- **Briefs are facts, not rules.** Working directory, commands, the plan entry and interface
  lines inline, paths. The prompts hold the rules; a brief that restates them is where the Tron
  orchestrator started inventing its own.
- **Turn budgets on the cheap steps** (e2e 12, docs 8) stay in the prompts as guidance; the
  extension's limit is what actually stops them.
- **Nothing is enforced *in the prompts*.** `wall.ts`, the `permission.read` blocks and the
  brief-path allowlist are gone since T-018. What is enforced now is enforced by the extension:
  the turn limit, the agent budget, the test run. Those are checks the skill demanded anyway,
  moved from the model into code because the model did not hold them.

## What is not shown yet

- **Everything above the Tron section describes a shape that has not run.** The next
  measurement is the todo CLI again, against T-018's 124 turns and 1:40; the plan for it is in
  [T-019](../backlog/T-019-workflow-cost.md).
- **Whether a worker holds the order** spec -> tests -> code inside one context. It is
  verifiable in the child's session log, as the reviewer's order was in T-018.
- **Whether 4096 is enough** for the implementing half of a unit. 2048 was the first proposal;
  the author judged it too tight for code. The measurement will say.

Next round: [T-019](../backlog/T-019-workflow-cost.md).
