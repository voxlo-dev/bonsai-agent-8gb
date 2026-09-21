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
there). `bonsai-server` must be up. It copies T-018's product back to the moment before U2's
review — U1's tests only, U2 `implemented`, no review result in the run log — plants the defect,
and hands the reviewer T-018's own U2 brief with only the path changed. Afterwards it runs the
reviewer's tests against the planted and the original code: red then green means the tests
caught the defect; red on both means they are wrong.

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# T-019 step 1: the localagent reviewer, alone, against T-018's finished U2 with one planted
# defect. Runs the agent the way dispatch starts it (pi -p, same flags, prompt appended), with
# T-018's own U2 reviewer brief, only the path changed. Needs bonsai-server running.
#
#   ./run.sh                 plant, then the reviewer (~10 min)
#   STEP=rework ./run.sh     the implementer on the review it wrote, then the reviewer's tests
#
# PLANT is the defect. The default sends the "unknown task id" error to stdout instead of
# stderr: criterion 6 catches it, a quick manual run by the implementer would not.
set -euo pipefail
here="$(dirname "$(readlink -f "$0")")"
ROOT="$(cd "$here/../.." && pwd)"
SRC=${SRC:-$ROOT/runs/T-018-workflow-without-tdd/work}
UNIT=U2
TEST_CMD="python3 -m unittest discover -v"
PLANT=${PLANT:-"sed -i 's/print(f\"error: unknown task id {args.id}\", file=sys.stderr)/print(f\"error: unknown task id {args.id}\")/' todo.py"}
STEP=${STEP:-review}
WORK=$here/work
OUT=$here
source "$ROOT/config.env"
curl -sf -o /dev/null "http://$SERVER_HOST:$PORT/health" || { echo "no server on $SERVER_HOST:$PORT - start bonsai-server" >&2; exit 1; }

agents="$ROOT/pi/localagent-workflow/agents"
prompt() { awk 'n>=2{print} /^---$/{n++}' "$agents/localagent-$1.md"; }   # body without frontmatter
run() {  # run <agent> <brief> - same flags as the extension's dispatch
  local log="$OUT/$1.$(date +%H%M%S).jsonl" t0=$SECONDS
  echo "--- $1 started $(date +%T)"
  PI_CODING_AGENT_DIR="$PI_AGENT_DIR" "$PI_BIN" --mode json -p \
    --no-extensions --no-skills --no-prompt-templates --no-context-files \
    --session-dir "$OUT/sessions" --append-system-prompt "$(prompt "$1")" -- "$2" \
    > "$log"
  echo "--- $1 took $(( (SECONDS - t0) / 60 )):$(printf %02d $(( (SECONDS - t0) % 60 )))"
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
    [ ! -e "$WORK" ] || { echo "$WORK exists - move or delete it first" >&2; exit 1; }
    cp -r "$SRC" "$WORK"; cd "$WORK"
    rm -rf .git __pycache__ todo.json "localagent/units/$UNIT/review.md"
    # Back to the moment before T-018's U2 review: U1's tests only, U2 implemented, no review
    # result in the run log.
    python3 - <<'EOF'
import re
t = open("test_todo.py").read()
start = t.index("@contextlib.contextmanager\ndef _chdir_temp")
end = t.index('if __name__ == "__main__":')
open("test_todo.py", "w").write(t[:start] + t[end:])
s = open("localagent/STATE.md").read()
s = s.replace("Phase: finalize ", "Phase: build    ")
s = re.sub(r"\| U2 \| CLI \| U1 \| done \|", "| U2 | CLI | U1 | implemented |", s)
s = s[:s.index("- 2025-09-20: U2 reviewer DONE")].rstrip() + "\n"
open("localagent/STATE.md", "w").write(s)
EOF
    cp todo.py "$OUT/todo.orig.py"
    eval "$PLANT"
    ! cmp -s todo.py "$OUT/todo.orig.py" || { echo "PLANT changed nothing in todo.py" >&2; exit 1; }
    echo "--- planted:"; diff "$OUT/todo.orig.py" todo.py || true
    git init -q && git add -A && git commit -qm planted
    run reviewer "$(cat <<EOF
Working directory: $WORK

Standing constraints: The contract is the spec — $WORK/localagent/units/U2/spec.md. You write one test per acceptance criterion (1-7 in the spec), BEFORE reading the production code in todo.py; your tests are answers to the criteria, not descriptions of what the code happens to do. Python 3 stdlib unittest only, fresh \`tempfile.TemporaryDirectory()\` + \`chdir\` per test (as the spec's "How it is reached" pins), call \`todo.main(argv)\` in-process (import \`main\` from todo). You may edit test_todo.py — it currently holds 6 passing U1 tests from the U1 reviewer (one class per unit is fine; ADD the U2 tests, do NOT delete or alter the U1 ones; \`python3 -m unittest discover -v\` must end green for all of them together). You may NEVER edit todo.py or any file other than test_todo.py — if the code is wrong or out of scope, that is a finding, not something you patch.

Task: For U2, add the seven tests (criteria 1-7) to $WORK/test_todo.py, run \`python3 -m unittest discover -v\` from the working directory until the whole suite passes, then write the review: read todo.py against the spec (main signature/return contract 0-or-1-never-raises, no exit-2 paths, output formats exactly as pinned, U1 functions untouched and called as-is, nothing outside Scope) and write findings to $WORK/localagent/units/U2/review.md. Note where a finding sits on the criteria-vs-format-pinning line.

Inputs: U2 spec at $WORK/localagent/units/U2/spec.md (acceptance 1-7, Success output format pinned in one place — it is the source for exact-stdout assertions); production file at $WORK/todo.py (open ONLY after the tests are written). Prior unit interface (U1): see "Consumes from prior units" in the spec. Test command: python3 -m unittest discover -v from the working directory.

Return status: DONE if the full suite is green and the review written; FIXES_REQUIRED if any criterion's behaviour is wrong or missing (name the criterion numbers); ESCALATE with kind (spec/toolchain) if the spec as written cannot be satisfied.
EOF
)"
    echo "--- files the reviewer touched (anything but test_todo.py and review.md is a breach):"; git status --short
    echo "--- review.md:"; cat "localagent/units/$UNIT/review.md" 2>/dev/null || echo "(none written)"
    echo "--- its tests on the planted code (criterion 6 should fail):"
    $TEST_CMD 2>&1 | grep -E '(ok|FAIL|ERROR)$|^Ran|^OK|^FAILED' || true
    echo "--- its tests on the original code (should be green, else the tests are wrong):"
    tmp=$(mktemp -d); cp test_todo.py "$tmp/"; cp "$OUT/todo.orig.py" "$tmp/todo.py"
    (cd "$tmp" && $TEST_CMD 2>&1 | grep -E '(ok|FAIL|ERROR)$|^Ran|^OK|^FAILED') || true; rm -rf "$tmp"
    ;;
  rework)
    cd "$WORK"; git add -A; git commit -qm reviewed || true
    run implementer "Working directory: $WORK (absolute). Constraints: Python 3 stdlib only; U1's load/save/next_id are done and untouched.
Task: rework unit $UNIT — fix exactly the criteria the review names, run what you built, return. Do not edit test_todo.py.
Inputs: $WORK/localagent/units/$UNIT/spec.md, $WORK/localagent/units/$UNIT/review.md. Test command: $TEST_CMD"
    echo "--- files the implementer touched (test_todo.py here is a breach):"; git status --short
    echo "--- the reviewer's tests after the rework:"; ($TEST_CMD >/dev/null 2>&1 && echo GREEN) || echo RED
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
  T-018's baseline, from its U2 session (36 turns, 32:20): build 8 turns / 15:33 (6 of them
  reading around — spec with `cat -A`, U1's review, README, PLAN — before the first edit);
  verification 28 turns / 16:47. Of those, 6 turns went into getting a probe script to run at
  all, 9 into `git diff` and re-checking U1, 6 into final re-reads. The probe paid: it found
  `save(tasks)` binding the list to `path`, fixed in one edit. So the target is the fumbling
  around the probe, not the probe itself.

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
