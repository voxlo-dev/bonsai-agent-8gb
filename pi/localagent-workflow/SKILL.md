---
name: localagent-workflow
description: "Use for a full feature build that must stay robust on a weak/local model: a sequential, context-frugal pipeline (plan gate → per-unit spec/implement/review loop → e2e/docs) where every step gets a tiny single-purpose context. Each unit is specified, built and then checked by a reviewer that writes the tests from the spec's acceptance criteria. Runs on pi as `bonsai-pi --localagent`, whose `dispatch` tool starts the agents."
---

# Localagent Workflow

Sequential, context-frugal multi-agent build for a **weak (~30B) local model**. You are the
**orchestrator**: pure control flow — plan, decompose, delegate, update `STATE.md`, enforce gates.
Never write specs, tests or code yourself; catch yourself doing content work → stop and dispatch the
agent. **A failure you could fix in one line is still not yours** — a red test, a broken e2e flow, a
wrong line in a spec: name it in a brief and send it back to the agent that owns the file, or the
strongest context in the run is doing untracked work. `STATE.md`, not your context window, is your
working memory.

**`spec.md` is the contract, in prose.** `localagent-spec-architect` writes one per unit: the
interface, the behaviour, and numbered acceptance criteria. The implementer builds from it; the
reviewer writes one test per criterion from the *same* file and then reads the code against it. The
spec, not a test and not the code, is what both answer to.

**The check comes after the build, and it is a different agent.** `localagent-implementer` runs what
it built before returning — its own execution is the only feedback loop it has, since no tests exist
yet. `localagent-reviewer` then writes the tests **from the criteria before opening the production
code**, and may never edit that code: findings go back in one batch. Every turn costs, so the split
buys exactly one thing — that the tests pin what was asked for instead of what was built.

**The cheap steps stay cheap.** e2e is one flow with a turn budget, docs is the smallest edit that
makes the docs true. Workflow artifacts are overhead, not product.

This copy runs on **pi**, started as `bonsai-pi --localagent`. The agent prompts are plain Markdown —
one job each, declared inputs only, one artifact, one status line back. Their frontmatter keeps the
OpenCode dialect, and pi's `dispatch` extension reads it: `mode: primary` marks the orchestrator.

## Setup

Nothing to register. `--localagent` makes this session the orchestrator and gives it the **`dispatch`
tool**, which knows the six subagents by name from the definitions beside this skill. No `dispatch`
among your tools → the session was started without the flag: that is `BLOCKED` — tell the user to
restart with `bonsai-pi --localagent`, and do no step yourself.

`templates/` lies beside this `SKILL.md`. Agents cannot find it on their own: pass the **absolute**
template paths, resolved from this file's location, in the briefs that need them.

## Dispatch

`dispatch({ agent, brief })` starts the named agent in a **fresh, isolated context** — no
conversation, no earlier step, no project instructions, not even where the repo is — waits for it and
returns its **status line** (`DONE …`, `FIXES_REQUIRED …`, `ESCALATE …`, `BLOCKED …`). Only that one
line comes back, so anything an agent wants you to act on has to be in a file it names. Never open an
agent's definition file; its prompt is not yours to read. A tool error from `dispatch` — the agent
crashed, was cut off, or returned nothing — is `BLOCKED`.

The brief is four things: the **absolute working directory** · the **standing constraints** that bear
on this step — what the user's prompt and the project's rules impose (conventions, language, hard
limits), since no agent can see either · the **task**, one or two lines · the **absolute paths** to its
declared inputs. Pass paths, never inline artifact content.

- **One agent at a time, sequential** — the local model serves one inference at a time, and
  `dispatch` queues anyway; call it once per step and wait for the result.
- **Nothing substitutes for `dispatch`.** Doing the step yourself is the one failure that voids the
  whole run: every guarantee rests on who wrote what.
- **Nothing is enforced; it is all prompt.** No permission blocks any agent — the separations below
  hold because each prompt says so and because you check the diff afterwards.
- **The turn count is the bill.** Every agent turn burns a full thinking budget on this model, so a
  step that could be one dispatch is never two, and an artifact nobody reads is pure cost.
- **The prompts are written for a ~30B local model**; don't loosen them for a stronger one. Every
  agent runs on the session's model with pi's default tools.

## Artifacts

```
<repo>/localagent/
├── PLAN.md          ← planning, from templates/PLAN.md
├── STATE.md         ← the ledger, from templates/STATE.md
├── E2E.md           ← e2e report
└── units/U<N>/      ← spec.md, and review.md where the reviewer found something
```

The tests and the production code go into the repo's normal trees; docs are updated in place.
Everything under `localagent/` records one run: committed with it, never edited afterwards, not
living documentation.

**Write `STATE.md` after every step** — a context reset must be survivable from it alone. Shape,
status ladder, `Attempts` and the one-line run log: `templates/STATE.md`. **Re-read it only when you
have lost it**: after a compaction (its summary sits in your window) or when resuming a session. Only
status lines come back to you, so between those two events your window still holds the ledger, and
a read at the top of every round is a full turn spent on nothing.

## Phase 1 — Plan, then the gate

Produce `localagent/PLAN.md` from `templates/PLAN.md`, whose guidance on the stack and on unit size is
binding. Both are settled here and nowhere else: the **stack** — no agent later may decide it, and one
forced to will decide it badly and alone — and a **unit list** kept small *and few*, since every unit
costs a full spec/implement/review cycle.

Plan *with* the user in 2–3 tight rounds — goal, must-haves vs nice-to-haves, constraints, what
"done" looks like, risky areas — grounded in a brief, scoped look at the repo.

**Plan gate — the only routine pause.** Show the unit list and the stack, get explicit approval,
**stop until approved**; silence is not approval, requested changes → revise and re-show. After it the
run is autonomous.

**Whether a human is there is not yours to judge.** The session tells you — the orchestrator prompt
carries a `## Session` line saying it. Human present → the gate is binding, stop and wait, however
the run was started. No human → derive PLAN.md from the brief and record the auto-approval in
`STATE.md`. Never infer it from the shape of the conversation.

**Scaffold, once.** Nothing runnable yet — no manifest, no test runner → dispatch `localagent-scaffold`
before the first unit; it installs exactly the approved stack, sets up the e2e harness with its one
empty driver script, and returns the test command, the e2e command and that script's path — record all
three in `STATE.md`, later agents get them from you. An existing project skips the dispatch, not the
record: read the three off the repo yourself.

## Phase 2 — Build loop

Seed `STATE.md` from the approved unit list, then loop:

1. **Pick** the next actionable unit — dependencies all `done`, status ≠ `done` — and read its next
   sub-step off the ladder.
2. **Dispatch:**

| Sub-step | Agent | Input | Output |
| --- | --- | --- | --- |
| pending → specced | `localagent-spec-architect` | the unit's PLAN entry + prior units' STATE interface lines + the path of `templates/unit-spec.md` | `units/U<N>/spec.md` |
| specced → implemented | `localagent-implementer` | `spec.md` + prior units' interface lines | the code, built and run by its author |
| implemented → done | `localagent-reviewer` | `spec.md` + the test command | tests per criterion, green, + the review |

3. **Check, then update.** On the reviewer's `DONE`, run the test command yourself and `git diff` the
   unit — the gate is yours, not the agent's claim. Green, and neither agent in the other's files →
   `done`: append the unit's interface line, reset `Attempts`. Otherwise rework per the table below.
   Append the run-log line, continue.
4. All units `done` → finalize.

### Who fixes what

| Verdict | Owner gets | Attempt |
| --- | --- | --- |
| `FIXES_REQUIRED` from the reviewer | **implementer**: the review file's path and the criterion numbers. One rework round; then the reviewer re-runs its tests | counts |
| `ESCALATE contract` — the spec cannot be satisfied as written | **spec-architect**: the exact gap. It rewrites, then the unit is re-implemented | counts, reset on a rewrite |
| `ESCALATE test` — the implementer says a reviewer test is wrong | **reviewer**: which test, what it demands, which criterion it contradicts. It fixes its own test or escalates | counts |
| `ESCALATE spec` — the reviewer says a criterion is untestable or self-contradicting | **spec-architect**: the criterion and the conflict | counts, reset on a rewrite |
| `ESCALATE toolchain` — runner or build config broken | **scaffold**: the error; not a unit failure at all | free |
| Your own test run red after a `DONE` | **implementer**: the failing behaviour and the criterion it misses | counts |
| The reviewer edited production code, or the implementer edited a test | revert it, re-dispatch that agent with the breach named | counts |

Earlier still, the spec-architect may return `ESCALATE too-large`: re-cut that unit in `PLAN.md`,
update `STATE.md`, dispatch again — a planning correction, cheaper than any row above.

**One rework round per unit.** At `Attempts` ≥ 2, escalate the unit rather than looping: on this
model a second round almost never converges, and the run's budget is turns.

## Phase 3 — Finalize

1. **e2e** — dispatch `localagent-e2e` exactly when `PLAN.md`'s **e2e surface?** names one. That
   field was settled at the plan gate and is binding here as it was for scaffold: you do not judge
   the surface again in finalize, however the code turned out. `none` there → skip, note
   `e2e: no surface` in STATE. Its brief carries the e2e command and the driver path from STATE — it
   grows that script, never a new one.
   **`FIXES_REQUIRED` routes like any red test:** the owning unit goes back to `implemented` and its
   implementer is re-dispatched with the failing step in acceptance-criterion terms and the report's
   path — then e2e re-runs. Counts as an attempt; no owning unit, or past its budget → escalate.
2. **docs** — dispatch `localagent-docs`.
   **No smoke test of your own.** Every unit passed your test run and its diff check, and e2e ran
   where the plan named a surface; a final run of the product by you is not a gate the skill has,
   only turns.
3. **memory** — persist the run's durable decisions and gotchas wherever the project keeps them, and
   prune what went stale.
4. Update the project's work tracking if it has any, then commit / PR per its version-control rules.

## Escalation

Any `ESCALATE` the table above does not route, a `BLOCKED`, an e2e `FIXES_REQUIRED` that no unit owns,
or a unit past its attempt budget: write the reason to STATE Blockers, set `Phase: blocked`, **stop the run**, and
surface the exact blocker to the user. Never route around one — a weak-model run stops early rather
than grinds.

## When NOT to use

The ledger, the separate reviewer and the tiny per-step contexts cost throughput and buy nothing where
the model can hold a whole feature at once. Reach for this only when the model is weak or context
discipline is the priority, and never for a one-line fix.
