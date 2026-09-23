# T-027 — Put the quality claim on the record: prompts, logs, and the comparison run

- **Summary:** Publish the evidence behind "a 27B-class agent on 8 GB": the Tron-game prompt and session, and the same tasks on the next-best 8 GB candidate
- **Category:** spike
- **Importance:** high
- **Effort:** M
- **Depends on:** none; T-025 and the launch post (T-028) cite it

## Why

The speed numbers are reproducible from `runs/`. The quality claim is not: "it builds a
server-authoritative game with two integration tests" (`docs/dev.md`, session
`2026-09-19T16-24-33`) and "Qwen3.6-35B-A3B is not good enough to count as an agent" are
observations from sessions nobody else can open. The first public discussion will ask for
exactly this, and the study work that holds the comparison is behind a university login.

## Done

The study's evaluation is translated and in the tree as
[`docs/model-comparison.md`](../docs/model-comparison.md), with the n = 1 caveat at the top, the
citation at the bottom and a closing section that states plainly that no Bonsai run is in it. The
README's opening now leads with that gap rather than around it.

## What the study already holds (`.temp/localagent-auswertung.md`, one week old, no Bonsai)

Same Tron prompt, OpenCode harness, RTX 4060 8 GB, 64k context, UD-Q4_K_XL, KV q8_0, n = 1 per
cell. Singleshot: Qwen3.8-27B (IQ4_XS, partial offload) "quasi perfect" after ~6 h at 3.9 tok/s;
Qwen3.6-35B-A3B built but broken (canvas), >60 min, 3 compactions, 25.9 tok/s in the sandbox;
GPT-OSS-20B working but judged a fluke; five others broken or aborted. Workflow: only
Qwen3.6-35B-A3B ran the whole pipeline including e2e and self-commit, result broken; the rest
aborted. The study's own conclusion is that Qwen3.6 is the *best agent by process* on this card
and Qwen3.8 the best by result. That is the baseline the repo has to beat, on record.

So "Qwen3.8 only 4 tok/s" is measured (3.9). "Qwen3.6 not an agent" is *not* what the study
says; it says Qwen3.6 keeps the process and misses the last meter. The claim for Bonsai is
therefore narrower and stronger: result quality of the dense 27B at MoE speed, in one harness.

## What

1. **A `docs/evidence.md`** (or a section in `docs/localagent.md`): the exact Tron prompt, the
   `bonsai-pi` invocation and profile, the session's turn count, wall time, tokens, compactions,
   and the resulting repo or a tarball link. No localagent run: the workflow is frozen and
   not recommended, and its failures are in [localagent.md](../docs/localagent.md#status).
2. **The comparison, cheapest valid form:** one Bonsai singleshot through *OpenCode* with the
   study's exact prompt and follow-up, on the 4060 Ti. That drops it straight into the study's
   table with the same harness, prompt and card class; no re-run of eight models. Record wall
   time, tok/s, process and result on the study's two axes. The `bonsai-pi` Tron session
   (`2026-09-19T16-24-33`) stays as the second data point, labelled as a different harness.
3. **Second run of the same cell**, because the study's own caveat is n = 1 and the GPT-OSS
   case shows why. Two Bonsai runs beat one, and it costs an hour at 36 tok/s.
4. Cite the study for Qwen3.8 (3.9 tok/s, ~6 h) and Qwen3.6 (process yes, result no) instead
   of re-measuring them; note the harness difference against the community's 33–39 tok/s
   for Qwen3.6 with experts on the CPU.
5. Wording in the README follows the result. The defensible claim today is "the result
   quality of the dense 27B that took 6 hours at 4 tok/s, at 36 tok/s, in the same 8 GB";
   "first" and "no other model can" only if both Bonsai runs pass where the study's table fails.
