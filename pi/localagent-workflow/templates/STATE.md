# State: {Project Name}

Plan: localagent/PLAN.md
Phase: build            # planning | plan-gate | build | finalize | blocked
Tests: {command}
E2E: {command} → {the one driver script every e2e run grows}   # or: none

## Units

Status ladder: pending → done (one worker dispatch), or → blocked
Attempts = worker dispatches on this unit beyond the first (escalate the unit at 2). A worker's own
fix cycles inside its dispatch are not counted; the harness cuts those off.

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

- {scaffold → DONE, 9 turns}
- {U1 worker → DONE, tests green, 11 turns}
- {U2 worker → DONE, tests RED (2 of 4), rework dispatched}
- {U2 worker rework → DONE, tests green}

## Blockers

- (none)
