# T-019 — Cut what the localagent workflow still costs per unit

- **Summary:** The rebuild works; now attack the three items the T-018 run left standing — the implementer's 32-minute self-verification, the orchestrator's 20 minutes of bookkeeping, and a reviewer whose findings path has never run
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

## What

Measure first, then change at most one thing per run — the comparison only holds while the prompt
and the profile stay fixed. Branch `t019-workflow-cost` carries the prompt changes as **one commit
each**, so a run can be pinned to any of them:

| Commit | Change | Answers |
| --- | --- | --- |
| `509eae8` | the e2e surface is settled in `PLAN.md` at the gate and binds finalize; a CLI counts | the coin flip: no variance left in whether e2e runs |
| `ab8a0b1` | `STATE.md` template gets a one-line run log; no re-read every round; no own smoke test | the orchestrator's 20 minutes |
| `86ee00a` | the implementer verifies with one throwaway probe script; `git` is not its tool | the implementer's 32 minutes, and the `git diff` breach |

The reviewer prompt is untouched on purpose: the run below tests it as it is.

### 1. The reviewer, alone, against a planted defect — first, before any turn counting

This is the run that decides whether the reviewer is a check or a ceremony, and it does not
need the whole pipeline: the reviewer is one `pi -p` process with its prompt appended, exactly
as `dispatch` starts it. So run it by hand against a copy of T-018's product with one criterion
broken, ~10 minutes instead of 1:40. **Pick a defect the implementer's own run would not show
but a criterion test does** — a wrong exit code on one error path, a message on stdout instead
of stderr — otherwise the run measures the self-verification, not the reviewer.

`runs/T-019-reviewer-findings/run.sh` (runs/ is gitignored, so it lives here until it exists
there). `bonsai-server` must be up. Fill the four variables from T-018's `STATE.md`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs one localagent agent by hand, the way dispatch starts it, against a copy of a finished
# unit with one planted defect. STEP=review (default): plant, then the reviewer. STEP=rework:
# the implementer on the review it wrote. Needs bonsai-server running and the pinned pi.
set -euo pipefail
ROOT=${ROOT:-$HOME/bonsai-local}            # this repo
SRC=${SRC:?the repo T-018 built, with localagent/ and the product}
UNIT=${UNIT:-U2}
TEST_CMD=${TEST_CMD:-python3 -m unittest -v}
CONSTRAINTS=${CONSTRAINTS:-Python 3, standard library only, no new dependencies}
PLANT=${PLANT:?shell command that breaks exactly one criterion in the copy, e.g. "sed -i ... todo.py"}
STEP=${STEP:-review}
WORK=${WORK:-$PWD/work}
OUT=$PWD                                    # logs and sessions stay out of the copy
source "$ROOT/config.env"
curl -sf -o /dev/null "$SERVER_URL/health" || { echo "no server at $SERVER_URL" >&2; exit 1; }

agents="$ROOT/pi/localagent-workflow/agents"
prompt() { awk 'n>=2{print} /^---$/{n++}' "$agents/localagent-$1.md"; }   # body without frontmatter
run() {  # run <agent> <brief> — same flags as the extension's dispatch
  local log="$OUT/$1.$(date +%H%M%S).jsonl"
  PI_CODING_AGENT_DIR="$PI_AGENT_DIR" "$PI_BIN" --mode json -p \
    --no-extensions --no-skills --no-prompt-templates --no-context-files \
    --session-dir "$OUT/sessions" --append-system-prompt "$(prompt "$1")" -- "$2" \
    | tee "$log" >/dev/null
  python3 - "$log" <<'EOF'
import json, re, sys
final = None; turns = 0
for line in open(sys.argv[1]):
    try: e = json.loads(line)
    except ValueError: continue
    if e.get("type") == "message_end" and e.get("message", {}).get("role") == "assistant":
        final = e["message"]; turns += 1
text = "\n".join(p["text"] for p in final["content"] if p.get("type") == "text") if final else ""
lines = [l.strip("`* ") for l in text.splitlines() if l.strip()]
status = next((l for l in reversed(lines) if re.match(r"(DONE|FIXES_REQUIRED|ESCALATE|BLOCKED)\b", l)), lines[-1] if lines else "")
print(f"{turns} turns, stopReason {final.get('stopReason') if final else None}: {status}")
EOF
}

case "$STEP" in
  review)
    rm -rf "$WORK"; cp -r "$SRC" "$WORK"; rm -rf "$WORK/.git" "$WORK/localagent/units/$UNIT/review.md"
    (cd "$WORK" && eval "$PLANT" && git init -q && git add -A && git commit -qm "planted")
    cd "$WORK"
    run reviewer "Working directory: $WORK (absolute). Constraints: $CONSTRAINTS.
Task: review unit $UNIT — write one test per acceptance criterion, run them, review the code.
Inputs: $WORK/localagent/units/$UNIT/spec.md. Test command: $TEST_CMD"
    echo "--- files the reviewer touched (production code here is a breach):"; git status --short
    echo "--- review.md:"; cat "localagent/units/$UNIT/review.md" 2>/dev/null || echo "(none written)"
    ;;
  rework)
    cd "$WORK"; git add -A; git commit -qm "reviewed" || true
    run implementer "Working directory: $WORK (absolute). Constraints: $CONSTRAINTS.
Task: rework unit $UNIT — fix exactly the criteria the review names, run what you built, return.
Inputs: $WORK/localagent/units/$UNIT/spec.md, $WORK/localagent/units/$UNIT/review.md. Test command: $TEST_CMD"
    echo "--- files the implementer touched (a test file here is a breach):"; git status --short
    echo "--- the reviewer's tests after the rework:"; (eval "$TEST_CMD" && echo GREEN) || echo RED
    ;;
esac
```

Record: did the reviewer report the planted criterion, by number, and nothing else? Did it hold
the spec-before-code order (its session JSONL shows the read order)? On `STEP=rework`: did the
implementer fix only that, and do the reviewer's tests go green? The attempt counter is the
orchestrator's and is not exercised here; it is covered by the full run below.

**If the reviewer waves the defect through, stop.** Record the workflow as unsuitable for this
model in `docs/localagent.md` and close the ticket on that; the commits above then optimise a
pipeline nobody should run.

### 2. The full run, once per commit, same prompt and profile as T-013 and T-018

Then the turn count, against T-018's 124. Check out the branch at the commit to test, `./install.sh
pi` (it copies the workflow), same todo-CLI prompt, `runs/T-019-{commit}/` with `report.sh`
beside it. Three things to read off each:

- **`509eae8`** — whether e2e ran, and what it cost with the 12-turn budget. This is the one
  commit that may make the run *longer*; the number it buys is the variance it removes.
- **`ab8a0b1`** — the orchestrator's minutes between dispatches, and whether the run log stayed
  one line per step. Also whether the orchestrator survived without the per-round re-read: a
  wrong status pick after a compaction is the failure to watch.
- **`86ee00a`** — the implementer's turns, split into build and verification from its session
  log: tool calls between the last write of a product file and `DONE`. If the split shows the
  build was the cost, the probe rule bought little and the next lever is the spec's size.

### 3. Still open after the runs

- [`T-030`](T-030-dispatch-runs-the-gate.md) holds the structural lever: the orchestrator's
  test run and diff check done by `dispatch` itself. Decided after these numbers, not before.
- Per-agent thinking budget is a guess, not a lever, until someone checks whether the pinned
  `llama-server` honours `reasoning_effort` per request. If it does, docs and scaffold could run
  with less than 8192 without touching the profile.

## Verify

Same prompt, same profile (`dedicated`, CTX 64000, BUDGET 8192), `runs/` next to the other two,
`report.sh` for the numbers. Targets: under 124 turns without losing the clean result, and a
reviewer that reports the planted defect. If it does not report it, record the workflow as
unsuitable for this model in `docs/localagent.md` rather than tuning further.
