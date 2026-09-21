# State: {Project Name}

Plan: localagent/PLAN.md
Phase: build            # planning | plan-gate | build | finalize | blocked
Tests: {command}
E2E: {command} → {the one driver script every e2e run grows}   # or: none

## Units

Status ladder: pending → specced → implemented → done
Attempts = reviewer rounds on this unit (escalate the unit at 2). An agent's own fix cycles are not
counted here — each self-verifies and only reports back once.

| ID | Title | Depends | Status | Attempts | Dir |
| --- | --- | --- | --- | --- | --- |
| U1 | {title} | — | pending | 0 | units/U1 |
| U2 | {title} | U1 | pending | 0 | units/U2 |

## Interfaces

One line per done unit — what later units can build on.

- {U1: exposes `foo(x): Bar` in src/foo.ts}

## Run log

One line per step, appended after it, in this shape and no other. No prose about what the step
did or why; the status line already says it, and the ledger is read after a reset, not enjoyed.

- {U1 spec → DONE, 5 turns}
- {U1 implement → DONE, 11 turns}
- {U1 review → FIXES_REQUIRED (criteria 3, 5), 9 turns}

## Blockers

- (none)
