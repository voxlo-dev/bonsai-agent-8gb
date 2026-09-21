# T-030 — Let `dispatch` run the orchestrator's two shell checks

- **Summary:** After a reviewer's `DONE`, the extension runs the test command and diffs the unit's files itself and returns the result with the status line, instead of the orchestrator spending two thinking turns per unit on a shell call and on reading a diff
- **Category:** decision
- **Importance:** medium
- **Effort:** S
- **Depends on:** T-019 (its numbers say whether the orchestrator's turns are still the cost)

## Why

The skill gives the orchestrator two checks after every unit: run the test command and read its
exit status, and `git diff` the unit to see that neither agent touched the other's files. Both are
mechanical, and on a 27B model both are expensive and unreliable in the wrong proportion: a shell
call costs a full thinking budget, and a model reading a diff to decide "did the reviewer edit
production code" is weaker than a `git diff --name-only` against two path lists.

`docs/localagent.md` says "Nothing is enforced any more", and that stays true in the sense it was
written: no wall, no permission block, no agent stopped from reading a file. This is different:
a check the skill already demands, moved from the model into code. The orchestrator keeps the
decision; the extension supplies the fact.

## What

- `dispatch` gets an optional `check` argument, or reads it off the brief: the test command and
  the unit's production and test paths. After the child returns, it runs the command, diffs
  the worktree since before the dispatch, and appends one line to the result:
  `tests: green · touched: <paths>` or `tests: RED · reviewer touched production: <path>`.
- The skill's step 3 then reads that line instead of asking for two shell turns.
- Measure: orchestrator turns per unit before and after, on the T-019 prompt and profile.

The counter-argument to weigh before doing it: every check that moves into the harness is one
the model no longer has to hold, and the workflow is also a measurement of what this model can
hold. Decide with T-019's numbers on the table.
