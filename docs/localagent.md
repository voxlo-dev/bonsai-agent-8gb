# The localagent workflow

A multi-agent build pipeline for a weak local model: plan gate, then per unit
spec -> implement -> review, then e2e and docs. It lives in
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
| Known to work | one small feature, planned interactively with the user first, on the CUDA backend |
| Not shown to work | large tasks, the reviewer's findings path (it has never fired), anything on the Vulkan backend at 7 tok/s |
| Measured | two runs, T-013 and T-018, both below in [Economics](#economics) |
| Open | [T-013](../backlog/T-013-localagent-first-run.md), [T-019](../backlog/T-019-workflow-cost.md), [T-030](../backlog/T-030-dispatch-runs-the-gate.md) |

Its ancestor was evaluated across eight local models before this repo existed, and no model of
that generation produced a working artifact through it; one held the whole process. That series is
[the model comparison](model-comparison.md), and it is the most honest description available of
what a multi-agent workflow costs a local model.

## Shape

| Phase | Step | Agent |
| --- | --- | --- |
| Plan | plan with the user, **gate**, scaffold once | orchestrator, `localagent-scaffold` |
| Build, per unit | pending -> specced | `localagent-spec-architect` |
| | specced -> implemented | `localagent-implementer` |
| | implemented -> done | `localagent-reviewer` |
| Finalize | one e2e flow where a surface exists, then the docs | `localagent-e2e`, `localagent-docs` |

The orchestrator is the session itself: pure control flow, `PLAN.md` and `STATE.md` its only
writes, `dispatch` its only way to get anything built. `STATE.md` is the ledger a context reset
must be survivable from.

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
before the rebuild and one after. Scripts and artifacts: `runs/T-013-localagent-cli/` and
`runs/T-018-workflow-without-tdd/` (gitignored, kept), `report.sh` beside each.

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

## The pieces, and what each one is answering

- **`spec.md` in prose, no stub files.** Stubs existed only to make two blind halves agree on a
  signature, at 7-10 minutes per unit. Without a wall, a later unit's implementer just reads the
  earlier unit's real code. The spec caps at ~80 lines, six-ish numbered acceptance criteria; each
  criterion becomes a test *and* a piece of implementation, so an inflated list inflates two agents.
- **The implementer runs what it built** before returning - not "it compiles", but the command, the
  route, the function. It is the only check in that step, since no tests exist yet. T-013's own
  artifact shows the gap: `python3 todo.py` did nothing, because the module had no `__main__`
  block. Contract-compliant, never executed.
- **The reviewer writes the tests from the criteria, before opening the production code.** Prompt
  order is the only lever here: tests written from the code pin what exists instead of what was
  asked for. It is verifiable afterwards in the child's session log, and in T-018 both reviewers
  held the order - spec, tests, run, *then* `todo.py`.
- **The reviewer never edits production code.** Its own tests it may fix freely; code findings go
  back to the implementer in one batch, one rework round, then escalate. Otherwise the checker is
  also the author and nobody is checking. Only a violated acceptance criterion is a finding - this
  model overproduces rather than rubber-stamps, and an invented finding costs a full round.
- **Turn budgets on the cheap steps** (e2e 12, docs 8). In T-013 they were the two steps meant to
  be cheapest and together cost 26 minutes; in T-018 docs took 3:26 for a README of 42 lines
  instead of 9:13 for one of 122.
- **Nothing is enforced any more.** `wall.ts`, the `permission.read` blocks and the brief-path
  allowlist are deleted; what remains is prompt plus the orchestrator's own `git diff` and test run
  after each unit.

## What T-018 did not prove

- **The findings path never ran.** Both units came back clean, so the reviewer returned `DONE`
  twice and the rework round was never exercised. The reviews themselves are substantive - U1
  flags that `save(path, tasks=None)` would silently persist `[]`, U2 argues about argparse's
  two-line stderr - but "does it find a real defect" is still open.
- **The implementer's self-verification is the new cost centre**: 32:20 and 36 turns for U2 alone,
  a third of the run.
- **The orchestrator still spends ~20 minutes between dispatches** on its ledger, including a final
  smoke test of its own and a fairly literary run log.
- Small breach worth watching: the U2 implementer ran `git diff` against the parent repo although
  the prompt told it to ignore it. One turn, but nothing stops that sort of thing but the prompt.

Next round: [T-019](../backlog/T-019-workflow-cost.md).
