# T-031 — Measure the Qwen Sharp chat template on Bonsai

- **Summary:** One `bonsai-pi` session with and without `peculiar-ragdoll/Qwen-Sharp-Chat-Templates` v22.5.0 via `--chat-template-file`: thinking tokens per turn and turns to a result. It targets answer prose, not thinking, so the expectation is small; the cost of finding out is half an hour
- **Category:** spike
- **Importance:** low
- **Effort:** S
- **Depends on:** none

## Why

The T-019 workflow run on the RTX showed the spec-architect spending five minutes per turn: 8k
of thinking to the budget before a `cat`, twelve turns for one spec.
[dev.md](../docs/dev.md#reasoning) has measured that this model ignores instructions about
thinking length, effort levels included, and that only `--reasoning-budget` stops it. The
per-agent budget was therefore the first lever (T-019, closed with the workflow frozen). Sharp is
the candidate found alongside it, and this ticket records what it would and would not change, so
the measurement is short and the result unambiguous.

**What Sharp is for this setup.** Bonsai-2-27B is Qwen3.8-27B with the architecture unchanged,
and the GGUF embeds the Qwen 3.5-family template (`general.architecture = qwen35`). Sharp is
froggeric's Qwen-Fixed-Chat-Templates v22.5 plus a terseness block appended to the system prompt.
Compared side by side with the embedded template, read from the GGUF header without downloading the model:

| | Embedded | Sharp v22.5.0 | For us |
| --- | --- | --- | --- |
| Tool calls | `<tool_call><function=…><parameter=…>` | same | the fork detects Qwen3-Coder by these strings (`common/chat.cpp`), parser unchanged |
| `preserve_thinking` | kwarg, default true | same kwarg, alias `preserve_reasoning` | `--no-reasoning-preserve` keeps working |
| Effort default | `xhigh`, raises on unknown values | `medium`, no steering line, accepts `none`…`xhigh` | server sends `medium` either way: no difference |
| Thinking-on path | — | "byte-identical to upstream plus the terseness block" | froggeric's fixes are for thinking-off |

So with thinking on, `medium`, and llama.cpp's own parser, **the whole delta is the terseness
block**: "Answer directly, after thinking … Never: preamble, restating, filler … If a user request
is genuinely ambiguous, ask a sharp question, don't guess."

**Why the expectation is small.** The block targets the answer, and its README says so: "where
the deliverable is mostly code or a structured artifact there is less padding to remove, so
expect less from it". Our cost is thinking to the budget before a trivial tool call, and the
block is one more instruction of the kind dev.md measured as ignored. Sharp's retention argument
("the model remembers what it thought last turn, avoiding amnesia and loops") does not apply
either: inside a dispatched child no user message follows the brief, so its thinking is already
preserved, and the loop happens anyway.

**Why it is still worth the half hour.** Its one agentic number: Qwen3.8-27B on SWE-bench-Live,
15 of 25 solved against 16 stock, median 20.0 minutes to a fix against 54.6, both at medium.
That would be fewer turns to a result, not fewer tokens per turn. Other quant, unknown runtime,
n = 25; whether it carries to the ternary model under a hard budget is exactly what one session
shows.

**The workflow is out of scope.** "Ask a sharp question, don't guess" would clash with the
localagent agents' `ESCALATE`, but that workflow is frozen and not recommended
([status](../docs/localagent.md#status)), so only a plain session counts.

## What

1. **Wire it as an opt-in.** `CHAT_TEMPLATE_FILE` in `config.env`, empty by default; when set,
   `bonsai-server` adds `--chat-template-file "$CHAT_TEMPLATE_FILE"`. The file itself goes into
   the repo (Apache-2.0, ~30 KB) at a pinned version: `templates/qwen-sharp-v22.5.0.jinja`, with
   the source URL and version line at the top. `--jinja` is already on, and it must precede the
   flag.
2. **Confirm it is served:** `curl /props | jq -r .chat_template | head -1` shows
   `template_version = "qwen3.8-froggeric-v22.5.0"`; render one conversation with a tool call
   through `/apply-template` and check the tool block and the `<think>` opener are what the
   embedded template renders, apart from the appended terseness text.
3. **Measure in a plain `bonsai-pi` session**, not in the workflow: the Tron prompt from
   `docs/dev.md` (session `2026-09-19T16-24-33` is the stock baseline, same profile), once with
   the file. From the session JSONL: thinking tokens per turn, turns to a working result, wall
   clock, and whether any turn ends in a question instead of an action.
4. **Read the result on one axis.** Thinking per turn still at the 8192 budget → Sharp did not
   touch the question; note it in `docs/dev.md#reasoning` as tried, leave the variable empty,
   close. Turns to result clearly down → a second session to confirm. No workflow run: the
   localagent workflow is frozen ([status](../docs/localagent.md#status)); `terse: false` is not
   an option either way, it removes the effect.

## Verify

The `dedicated` profile (CTX 64000, BUDGET 8192), same machine, stock and Sharp in
the same session of work. Numbers into `docs/dev.md#reasoning` beside the effort table; the
variable stays opt-in until a second plain session confirms the gain.
