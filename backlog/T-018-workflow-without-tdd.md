# T-018 — Rebuild the localagent workflow without TDD

- **Summary:** Drop the visibility wall, the stubs and the test-author; let a reviewer write the tests after the implementation and check it against the spec
- **Category:** fix
- **Importance:** high
- **Effort:** M
- **Depends on:** T-013 (its run is the evidence below)

## Why

The T-013 run (`runs/T-013-localagent-cli/`, session `2026-09-20T10-38-37`) finished a todo CLI
correctly — 12/12 tests green, every error case per spec — but took 2 h 14 for 196 lines of
product code. Measured against the T-002 reference, where the same model built a working Tron
game in one context:

| | T-013 (workflow) | T-002 (one context) |
| --- | --- | --- |
| Wall clock | 2 h 14 | 1 h 31 |
| Turns | 198 (60 orchestrator + 138 agents) | 108 |
| Output tokens | 210 593 | 118 522 |
| Product | 196 lines + 373 lines of tests | a playable game with tests |

133 of those 134 minutes were model time. Context reloading after a dispatch, the suspected
cost in T-013, was not it: only 14 of 198 turns had to reprocess their prompt. The harness does
not show up in the bill at all — **the turn count is the bill**, and every turn burns a full
thinking budget (agents averaged 1 232 output tokens per turn).

**The wall is the single most expensive part.** The test-author wrote an assertion JSON can
never satisfy (`assertEqual([(1, "a", False)], json.load(f))` — tuples against parsed objects).
The implementer may not look at it: 23 turns and 29 minutes reconstructing the expectation from
failure output, including probe scripts written to `/tmp`. The spec-architect then ruled
`ESCALATE unfounded` (wrong — the test really was broken), and the test-author fixed it in two
minutes. Around 46 minutes, **34 % of the run**, for a one-line defect that is obvious on
sight. That is the wall's built-in economics: it costs exactly when the test is wrong, and a
27B model writes wrong tests often. Note what the run says about blindness: the blind *test*
was broken, the blind *code* was correct. The spec was the reliable source, not the blindness.

**The stubs exist only to serve the wall.** Their whole purpose is to make two blind halves
agree on a signature. Without a wall, a later unit's implementer reads the earlier unit's real
code, and the stub step (7–10 minutes per unit) has no reason left.

Two further faults from the same run, cheap to fix along the way:

- **The plan gate never happened.** The session has exactly one user message. `STATE.md`
  records "plan auto-approved — headless test run, no human reachable", while a human was
  sitting in front of it. The only routine human checkpoint is the one the model defines away,
  and the skill's "Headless: pause if a human is reachable, else record auto-approval" invites
  it. pi knows the answer (`ctx.hasUI`), the model does not.
- **The cheap steps have no budget.** The skill demands one e2e flow and no edge cases; the
  agent produced a 317-line driver with 88 checks (17 min). The docs agent spent 20 turns and
  9 minutes on a 122-line README for a four-command CLI. Together 26 minutes for the two steps
  that were supposed to be the cheapest. Final ratio: 829 lines of workflow artifacts against
  196 lines of product.

What did work, and must survive the rebuild: no agent edited another's files, nothing stopped
on `length`, the orchestrator kept its ledger, ran the tests itself, diffed and committed per
unit, and it delegated instead of writing content (its only writes were `PLAN.md`/`STATE.md`).
The mechanics hold; the economics do not.

## What

### The new per-unit chain

| Step | Agent | Returns |
| --- | --- | --- |
| pending → specced | `spec-architect` | `spec.md`: behaviour, the interface in prose, numbered acceptance criteria. No stubs, with a length cap |
| specced → implemented | `implementer` | the code, **executed by itself** before `DONE`, not just compiled |
| implemented → done | `reviewer` | tests per criterion, green; review against the spec; findings or `DONE` |

Three rules the T-013 evidence says to write into the prompts explicitly:

1. **The reviewer writes tests from the acceptance criteria, not from the code.** Tests written
   after the fact pin what exists instead of what was asked for; prompt order is the only lever
   here. Read the spec, write one test per criterion, run them, *then* review the code against
   the same criteria.
2. **The reviewer never edits production code.** It may fix its own tests freely; code findings
   go back to the implementer in **one** batch, one rework round, then escalate. Otherwise the
   reviewer is implementer and checker in one and nobody is checking. It must name every
   acceptance criterion and mark it; only a violated criterion is a finding — this model
   overproduces (see the 88 e2e checks) rather than rubber-stamps.
3. **The implementer must run what it built.** It loses its feedback loop when no tests exist
   yet, and every defect now costs a round trip. T-013's own artifact shows the gap: `python3
   todo.py` does nothing because the module has no `__main__` block — contract-compliant, never
   executed.

### Delete

- `pi/extensions/localagent/wall.ts`, the `permission.read` block in the implementer's
  frontmatter, and the wall handling in `index.ts` (the `-e` injection, the brief-path
  allowlist, `LOCALAGENT_WALL`). `denies()` goes with it.
- `pi/localagent-workflow/agents/localagent-test-author.md`
- `pi/localagent-workflow/templates/unit-stub.md`
- From the skill: the wall, the wall drop, the `tests-red` rung, and the escalation rows that
  only exist between two blind halves (`test-mismatch`, `unfounded`).

### Change

- `templates/STATE.md`: ladder `pending → specced → implemented → done`; attempts count
  reviewer rounds.
- `templates/unit-spec.md`: the Contract section is prose now, not stub paths.
- `agents/localagent-{e2e,docs}.md`: a hard turn budget, and for e2e the one-flow rule as a
  refusal, not a preference.
- `agents/localagent-orchestrator.md` and the skill: the new chain, and the plan gate as
  binding whenever a human is present.
- `pi/extensions/localagent/index.ts`: tell the orchestrator through its prompt whether the
  session is interactive (`ctx.hasUI`), so the gate is not the model's judgement call.
- `docs/dev.md#localagent-workflow`: replace the wall paragraphs with what happened and why it
  is gone. The measurement is what this repo keeps, not the code.

### Verify

Re-run `runs/T-013-localagent-cli/` with the same prompt and profile (`dedicated`, CTX 64000,
BUDGET 8192) so the numbers stay comparable, then `report.sh`. Target: clearly under the 198
turns and 2 h 14 — removing the wall loop alone accounts for ~46 minutes and the capped
finalize steps for ~15. Check specifically whether the reviewer finds real defects or waves
things through, how many rework rounds happen, and whether the plan gate now stops for the
user. If the reviewer turns out to rubber-stamp, that is the point to stop and record the
workflow as unsuitable for this model rather than tune it further.
