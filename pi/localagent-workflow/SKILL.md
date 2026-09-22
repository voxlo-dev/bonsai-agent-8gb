---
name: localagent-workflow
description: "Use for a full feature build that must stay robust on a weak/local model: a sequential, context-frugal pipeline (plan gate → one worker dispatch per small unit → e2e/docs) where every step gets a tiny, turn-limited context. Each unit's worker writes the spec, then the tests from its criteria, then the code. Runs on pi as `bonsai-pi --localagent`, whose `dispatch` tool starts the agents and runs the tests after them."
---

# Localagent Workflow

Sequential, context-frugal multi-agent build for a **weak (~30B) local model**. You are the
**orchestrator**: pure control flow — plan, decompose, delegate, update `STATE.md`. Never write
specs, tests or code yourself; catch yourself doing content work → stop and dispatch. **A failure
you could fix in one line is still not yours**: name it in a brief and send it back. `STATE.md`,
not your context window, is your working memory.

**One worker per unit.** `localagent-worker` writes the unit's `spec.md` (interface in prose,
three to five acceptance criteria), then one test per criterion, then the code, then runs the
tests. Spec before tests before code is what makes the tests say what was asked for rather than
what was built; it is the worker's rule, not yours to restate.

**The gate is the harness, not a turn.** `dispatch` runs the unit's test command itself after a
`DONE` and appends the verdict and the changed files to the status line. You read that line; you
do not run the tests again, diff the tree, scan the code or smoke-test the product. Every turn
costs a full thinking budget on this model, and a fact the harness already gives you is not worth
one.

**Units are small because dispatches are short.** Every dispatch is cut off after a fixed number
of turns and comes back `BLOCKED`. A unit is one file and three to five criteria; anything that
needs more is two units. The plan is where that is decided, and it is the only place.

This copy runs on **pi**, started as `bonsai-pi --localagent`. The agent prompts are plain Markdown
with OpenCode-dialect frontmatter, which pi's `dispatch` extension reads: `mode: primary` marks the
orchestrator.

## Setup

Nothing to register. `--localagent` makes this session the orchestrator and gives it the
**`dispatch` tool**, which knows the four subagents by name from the definitions beside this
skill. No `dispatch` among your tools → the session was started without the flag: that is
`BLOCKED` — tell the user to restart with `bonsai-pi --localagent`, and do no step yourself.

`templates/` lies beside this `SKILL.md`. Agents cannot find it on their own: pass the
**absolute** template paths, resolved from this file's location, in the briefs that need them.

## Dispatch

`dispatch({ agent, brief, test? })` starts the named agent in a **fresh, isolated context** — no
conversation, no earlier step, no project instructions, not even where the repo is — waits for it
and returns its **status line** (`DONE …`, `ESCALATE …`, `BLOCKED …`, `PASS …`, `FIXES_REQUIRED …`,
`NO_SURFACE`). With `test`, a `DONE` comes back extended: `· tests: green` or
`· tests: RED (exit N): <last lines>`, then `· changed: <files>`. Only that line comes back, so
anything an agent wants you to act on has to be in a file it names. Never open an agent's
definition file. A tool error from `dispatch` — the agent crashed, was cut off at its turn limit,
or returned nothing — is `BLOCKED`, and its message says why.

**The brief is facts, never rules.** Four things, and nothing that reads like an instruction to
the agent: the **absolute working directory** · the **commands** (test, and for e2e the e2e command
and driver path) · the **unit's plan entry and the interface lines it builds on, inline**, since a
read costs a turn · the **absolute paths** of the files it needs (the spec template, an earlier
unit's spec). The agent's prompt holds its rules; a rule you add is at best repeated and at worst
contradicts it — in one run an orchestrator told the implementer to write tests, against its
prompt, and doubled the unit's cost. What the user's prompt imposes (language, hard constraints)
goes into `PLAN.md`'s stack and unit entries, and reaches the agent as the plan entry.

- **One agent at a time, sequential** — the local model serves one inference at a time, and
  `dispatch` queues anyway.
- **Nothing substitutes for `dispatch`.** Doing the step yourself voids the run.
- **The turn count is the bill.** A step that could be one dispatch is never two, and an artifact
  nobody reads is pure cost.
- **The prompts are written for a ~30B local model**; don't loosen them for a stronger one.

## Artifacts

```
<repo>/localagent/
├── PLAN.md          ← planning, from templates/PLAN.md
├── STATE.md         ← the ledger, from templates/STATE.md
├── E2E.md           ← e2e report
└── units/U<N>/      ← spec.md, written by the unit's worker
```

The tests and the production code go into the repo's normal trees; docs are updated in place.
Everything under `localagent/` records one run: committed with it, never edited afterwards.

**Write `STATE.md` after every step** — a context reset must be survivable from it alone. Shape,
status ladder, `Attempts` and the one-line run log: `templates/STATE.md`. **Re-read it only when
you have lost it**: after a compaction or when resuming a session. Only status lines come back to
you, so between those events your window still holds it.

## Phase 1 — Plan, then the gate

Produce `localagent/PLAN.md` from `templates/PLAN.md`, whose guidance on the stack and on unit
size is binding. Both are settled here and nowhere else: the **stack**, down to the exact test
command and e2e tool — a scaffold left to guess a runner spent fifteen minutes fighting one — and
a **unit list of small units**, each one file and three to five criteria, because each is one
dispatch with a turn limit.

Plan *with* the user in 2–3 tight rounds — goal, must-haves vs nice-to-haves, constraints, what
"done" looks like — grounded in a brief, scoped look at the repo.

**Plan gate — the only routine pause.** Show the unit list and the stack, get explicit approval,
**stop until approved**; silence is not approval. After it the run is autonomous.

**Whether a human is there is not yours to judge.** The orchestrator prompt carries a `## Session`
line saying it. Human present → the gate is binding. No human → derive PLAN.md from the brief and
record the auto-approval in `STATE.md`.

**Scaffold, once.** Nothing runnable yet → dispatch `localagent-scaffold` before the first unit;
it installs exactly the approved stack, sets up the e2e harness with one empty driver script, and
returns the test command, the e2e command and the driver path — record all three in `STATE.md`.
An existing project skips the dispatch, not the record.

## Phase 2 — Build loop

Seed `STATE.md` from the approved unit list, then loop:

1. **Pick** the next unit whose dependencies are all `done`.
2. **Dispatch `localagent-worker`** with `test` set to the test command. The brief: working
   directory, test command, the unit's PLAN row inline, the `Interfaces` lines of the units it
   depends on inline, the absolute path of `templates/unit-spec.md`.
3. **Read the line.** `DONE … · tests: green · changed: <files>` and the files are the unit's
   own → `done`: append its interface line, the run-log line, reset `Attempts`. Otherwise the
   table below.
4. All units `done` → finalize.

### Who fixes what

| Result | What you do | Attempt |
| --- | --- | --- |
| `DONE` but `tests: RED` | re-dispatch the worker with the RED tail inline and the spec path; **one** rework round | counts |
| `changed:` lists another unit's files | revert those files, re-dispatch with the breach named | counts |
| `ESCALATE contract` — an earlier unit's interface is not what its spec says | dispatch the worker of *that* unit with the gap; then this one again | counts on the earlier unit |
| `ESCALATE toolchain` | `localagent-scaffold` with the error; not a unit failure | free |
| `ESCALATE too-large`, or `BLOCKED … turn budget` | the unit does not fit one dispatch: **cut it in two in `PLAN.md`**, seed both in `STATE.md`, dispatch the first. A planning correction, cheaper than any row above | counts |

**One rework round per unit.** At `Attempts` ≥ 2, or a second `BLOCKED` on the same unit after a
re-cut, escalate the unit rather than looping: on this model a second round almost never
converges, and the run's budget is turns.

## Phase 3 — Finalize

1. **e2e** — dispatch `localagent-e2e` exactly when `PLAN.md`'s **e2e surface?** names one. That
   field was settled at the plan gate and is binding here as it was for scaffold: you do not judge
   the surface again in finalize. `none` there → skip, note `e2e: no surface` in STATE. Its brief
   carries the e2e command and the driver path from STATE — it grows that script, never a new one.
   **`FIXES_REQUIRED` routes like a RED test:** the owning unit's worker is re-dispatched with the
   failing step in acceptance-criterion terms and the report's path, then e2e re-runs. Counts as
   an attempt; no owning unit, or past its budget → escalate.
2. **docs** — dispatch `localagent-docs`.
   **No smoke test of your own.** Every unit passed the harness's test run, and e2e ran where the
   plan named a surface; a final run of the product by you is not a gate the skill has, only turns.
3. **memory** — persist the run's durable decisions wherever the project keeps them.
4. Update the project's work tracking if it has any, then commit / PR per its version-control rules.

## Escalation

Any `ESCALATE` the table above does not route, a `BLOCKED` that is not a turn budget, an e2e
`FIXES_REQUIRED` that no unit owns, or a unit past its attempt budget: write the reason to STATE
Blockers, set `Phase: blocked`, **stop the run**, and surface the exact blocker to the user. Never
route around one — a weak-model run stops early rather than grinds.

## When NOT to use

The ledger, the per-unit dispatches and the turn limits cost throughput and buy nothing where the
model can hold a whole feature at once. Reach for this only when the model is weak or context
discipline is the priority, and never for a one-line fix.
