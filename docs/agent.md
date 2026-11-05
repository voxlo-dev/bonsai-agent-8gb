# The agent: harness configs, budget, prompt

How the harness configs are written against the server (pi, opencode), the context budget that
keeps pi from compacting itself to death, the agent prompt, and how the server runs. The
arithmetic was measured on Bonsai and holds for every model; the per-model values are in
`configs/`.

## Context budget

pi's compaction defaults assume a 200k window. On 48k they produce an endless compaction
loop. From `dist/core/compaction/compaction.js` and `settings-manager.js`:

- `shouldCompact`: `contextTokens > contextWindow - reserveTokens`, default `reserveTokens` 16384
- `keepRecentTokens` default 20000, estimated as `chars/4` over the messages only - the
  system prompt and the tool schemas are not counted, and chars/4 underestimates code and
  JSON tool arguments

Measured on a full-stack game prompt (session `2026-09-19T16-24-33`, 30 entries, 31 minutes):

| Compaction | tokensBefore | input of the next request |
| --- | --- | --- |
| 1 | 33 229 | 33 524 |
| 2 | 39 087 | 32 272 |
| 3 | 33 963 | 32 476 |
| 4 | 35 026 | - |

The trigger sat at 48000 - 16384 = **31 616**, and the context never came back below it:
those "20 000" kept tokens really were ~30 000. The first compaction cut at the very first
assistant message and freed nothing at all. pi then compacted on every single turn, at a
cost of one summarization call (2.3-3.8k tokens at ~30 tok/s) plus a full prompt
reprocess - `cacheRead` drops to 0 after a compaction - of ~33k at ~400 tok/s. Roughly a
third of that session went into compaction, and the task never finished.

A second, latent fault: `maxTokens` 24000 plus a 31 616 trigger let pi request 55 616
tokens from a 48000 window. With `--no-context-shift` the server stops there; the
`2026-09-19T15-32-43` session shows a `stopReason: length`.

The settings below keep the post-compaction state comfortably under the trigger and the
worst case inside the window. `harness/pi.py` writes the two compaction keys into the pi config dir's
`settings.json`.

Because these five constrain each other, they live in one configuration, `configs/NAME.env`, and
move together. The `-display` configuration of a model is its 48k set; the model's own
(dedicated) one is the 64k window below. The 48k set is what the measurements above were taken with - `CTX` 48000, `BUDGET` 4096, `MAX_TOKENS` 12000,
`RESERVE_TOKENS` 12000, `KEEP_RECENT_TOKENS` 8000 - for a GPU that also renders a desktop
and so cannot hold a 64k cache.

| | Value | Constraint |
| --- | --- | --- |
| `RESERVE_TOKENS` | 16000 | >= the largest single turn's output (11 441 measured), and >= `BUDGET` + a tool call + 4096 for the clamp |
| `MAX_TOKENS` | 16000 | `CTX - RESERVE + MAX_TOKENS <= CTX`, so exactly 64000 |
| `KEEP_RECENT_TOKENS` | 12000 | real cost ~1.4-2x, so ~24k in use against a 48 000 trigger |
| `BUDGET` | 8192 | 8192 + ~3.7k tool call <= `RESERVE_TOKENS` - 4096 = 11 904 |

That leaves ~20k of working room.

Measured on the same prompt with these settings (session `2026-09-19T17-24-22`, 79 agent
steps, 89 minutes): 5 compactions, with 13, 18, 12, 19, 5 and 12 steps between them -
against one per step before. Each fired at 36 974-37 513 tokens, and the next request came
back at 15.2-18.6k, less than half the trigger. The run ended on something else, below.

**pi caps the output near the trigger.** pi sends `max_tokens` as
`min(maxTokens, contextWindow - estimated context - 4096)` (`clampMaxTokensToContext`,
`CONTEXT_SAFETY_TOKENS` = 4096). Just below the trigger that leaves
`RESERVE_TOKENS - 4096` = 7 904 tokens, less than `BUDGET` (8192). The last step of that
session sat at 35 861 tokens, got `max_tokens` 8 334, spent 8 192 of it thinking, and was cut
off with `stopReason: length` before its tool call, which ended the agent loop. So the real
constraint is `BUDGET + tool call <= RESERVE_TOKENS - 4096`.

`BUDGET` is therefore 4096: with a tool call of up to ~3.3k (the largest write measured
without thinking) it stays under 7 904, and a 3k budget already produced plan + code (see
[Reasoning](bonsai.md#reasoning)). The other lever, `RESERVE_TOKENS` 16000, would keep 8 192 of
thinking but lower the trigger to 32 000 and the working room between compactions to ~16k.

Three runs of the same prompt, which is what the numbers below come from:

| | 48k, `BUDGET` 8192 | 48k, `BUDGET` 4096 | **64k, `BUDGET` 8192** |
| --- | --- | --- | --- |
| Steps / duration | 79 / 89 min | 168 / 112 min | 108 / 91 min |
| Ended | cut off on `length` | on its own | on its own |
| Compactions | 5, every 5-19 steps | 7, every 8-33 steps | 4, every 17-30 steps |
| Context after one | 15-19k | 15-19k | 21-24k |
| Steps at the budget | 4 | 6 | 2 |
| Result | unfinished | one `index.html`, online mode never tested, test passes claimed but not run | server + client + two integration tests, 869 lines, confirmed working |

The middle run is a `-display` configuration, the right one the dedicated one. Fewer, larger steps
beat many small ones here: half the steps of the 4096 run, in the same time, for a result
that holds up. The 64k run's closest approach to pi's clamp left 5 372 tokens of margin, so
the trigger was never the limit.

**The 4096 stays.** pi's `CONTEXT_SAFETY_TOKENS` is a constant in its bundle. Shrinking it means
patching a pinned dependency, which `PI_VERSION` would then no longer describe, or asking pi for a
setting. With 5 372 tokens of margin in the run above, ~3k more working room per compaction cycle
is not worth either. Revisit only if a configuration runs tighter than that (closed as T-015).

The 4096 re-run (session `2026-09-19T19-16-01`): 168 steps in
112 minutes, and the run ended on its own (`stopReason: stop`) with no step cut off on
`length`. 7 compactions, 8-33 steps apart, back at 14.5-19.4k each time. 6 steps hit the
budget. The largest output was 11 441 tokens, 4k thinking plus a ~7k `write`, at 7.6k
context where the clamp still allowed the full 12 000. The same step just below the trigger
would be cut off, so the tool-call allowance above is a typical case, not a bound.

## The agent prompt

`AGENTS.md` in pi's config dir, written by `harness/pi.py` from [`harness/pi/AGENTS.md`](../harness/pi/AGENTS.md), goes
into pi's system prompt at startup, for every session and both models; `--append-system-prompt`
and `--system-prompt` are the per-run equivalents. It is written as a description of the
situation with the reason for each point, not as rules, and that is a measured choice:

- **Rules are checked with turns.** The localagent runs showed a model that over-attends to
  everything in reach: "~80 lines" became `wc -l` five times, "read nothing else" became
  orientation reads, a stated turn limit became a count. Every hard rule added there was ignored or
  paid for in turns ([localagent.md](localagent.md#the-t-019-cli-run-where-the-turns-went)). So the
  file carries no number, no "never" or "must", and nothing the model could verify with a tool.
- **Thinking length is not a prompt matter.** This model ignores instructions about how long to
  think, the template's effort levels included ([Reasoning](bonsai.md#reasoning)); `BUDGET` is what stops
  it. The file only says why code belongs in the tool call: a block cut off at the budget loses
  whatever was drafted in it.
- **Each point answers a failure in a plain session**, not in the workflow. From the Tron runs
  ([agent-sessions.md](agent-sessions.md)): the 96k session that spent two hours debugging its own
  headless-DOM test harness and never returned to the game; the Qwen session that wrote eleven
  tests on a bug report and left the bug in place; the 4096 run that claimed test runs it never
  did; leftover servers holding the ports of the next test.
- **It stays task-neutral.** Nothing about games, browsers or the Tron prompt, which is the
  benchmark: a prompt tuned to it would measure the prompt. That includes the HTML comment at
  its top, which pi passes to the model with the rest, so the reasons live here and not there.

The first version (until 2026-09-27) was four imperatives: think short, one step per turn, no
restating, minimal tool arguments. None of it was ever measured against no file at all.

**Its first reading (T-041, 2026-10-02): no cost seen, no effect seen on Bonsai. It stays.** No
session quoted it or checked its points with tools. C2 did worse than C, but its log shows why,
and it is not the file: it did exactly what the third point argues against, an hour inside its
own test setup, and lost the end to a `pkill -f` that killed its own shell
([agent-sessions.md](agent-sessions.md#c2-and-w-bonsai-and-swift-bonsai-2)). Qwen3.6 with the same file (B2) gave its best session yet;
that is n = 1 and no comparison against no file. The `pkill -f` trap is the candidate for the
next point it carries, with a new reading after.

## Harness configs

`las harness pi|opencode CONFIG [--dir DIR]` writes the config of a coding agent for a
configuration into `DIR` (default `$LAS_HOME/harness/HARNESS/CONFIG`) and prints the variable that
points the harness at it. It installs no harness and touches nothing outside `DIR`: no `~/.pi`, no
global npm package, no opencode config of yours unless `--dir` says so. The bench writes its
container's pi config through the same code (`harness/pi.py`), into `$LAS_HOME/bench/pi-agent-{config}`.

### pi

`harness/pi.py` writes `models.json` (provider `local` at `SERVER_URL`, `contextWindow` from `CTX`),
`settings.json` (that provider as the default and the compaction keys under
[Context budget](#context-budget)), `AGENTS.md` and the pinned pi-bg-bash extension
([Background tasks](#background-tasks)); the harness reads them through `PI_CODING_AGENT_DIR`
(`getAgentDir()` in pi's `dist/config.js`: providers, settings, `AGENTS.md`, auth, sessions). The
bench's image pins pi at `PI_VERSION`; the budget arithmetic reads that version's compaction code,
so another pi needs the budget checked again.

The config dir is its own, never the global `~/.pi/agent`, for a reason that was measured on a
shared one:

- `defaultProvider`/`defaultModel` are global, so a plain `pi` would start on our model.
- The compaction keys are global or per project, not per model (`settings-manager.js`).
  A 200k model then kept 8k of recent history per compaction instead of 20k.
- `AGENTS.md`, telling the model to think briefly on a small window, went into every
  model's system prompt - or, when the user had their own, ours was skipped.

A project directory's own `.pi/settings.json` still applies; that is pi's per-project override
and intended.

Skills are not isolated by the config dir: pi discovers every skill in `~/.agents/skills` and in
each `.agents/skills` from the working directory up to the repository root - the skills of whatever
other agent the user runs - and lists them all in the system prompt. On this machine that was 17
workflow skills, ~8.6k characters, about 2k tokens of every request in a 64k window, for skills
written for another agent. The bench starts pi with `--no-skills`; `--skill <path>` still loads one
on purpose. Run by hand, pass `--no-skills` too.

pi reads providers from `models.json`. `contextWindow` decides when pi compacts, together with the settings under [Context budget](#context-budget) - not `maxTokens`, which is only the per-turn output cap. Unsloth's `unsloth start pi` hard-codes `maxTokens = min(context / 4, 8192)`, which cuts a single long reasoning turn off at 8k. That is why this setup writes its own config.

### opencode

`harness/opencode.py` writes one `opencode.json` with an OpenAI-compatible provider `local` at
`SERVER_URL`, the model under `MODEL_ALIAS` with `CTX` as its context limit and `MAX_TOKENS` as its
output limit, reasoning on, and that model as the default; point opencode at it with
`OPENCODE_CONFIG`. Unlike pi's, its compaction is not tuned here: the budget arithmetic above
was measured on pi and is not checked against opencode.

### Background tasks

pi's bash tool has no default timeout: a call without one runs until it returns or someone
presses Escape. A server started in the foreground, or a test that waits for a socket that never
answers, holds the whole session. In the Tron sessions on the 4060 Ti machine that happened four
times in 534 tool calls, all with Qwen3.8-Flash or Swift-Bonsai-2 (W, ES), each aborted by hand
after 5-15 minutes, and each time the model needed a `Resume.` to go on. None of the calls that
returned took longer than 3.8 minutes.

[pi-bg-bash](https://github.com/gvanderclay/pi-bg-bash) (pinned by `PI_BG_BASH_VERSION` and
`PI_BG_BASH_SHA256` in `config.env`, fetched by `harness/pi.py` from `PI_BG_BASH_URL`, default the npm
registry's tarball, once: it keeps it in `$LAS_HOME/cache/`, since the registry can hang on IPv6)
replaces pi's bash with the same tool plus a `background`
flag, and adds `bash_output`, `bash_tasks` and `bash_kill`. A background call returns a task id at
once; when the command exits, a message with its exit state and last lines arrives and starts a
turn. A foreground call with no `timeout` of its own that is still running after 120 s becomes such
a task, so a hung command no longer holds the session: the model reads that it moved and can stop
it. Ending the session kills every task's process group, a `server &` left behind included. Its
logs live in `~/.local/state/pi-bg/`, removed after 7 days. Cost: its tool descriptions add
~2.7k characters, about 700 tokens, to every request.

No default `timeout` is set on top of it: pi-bg-bash reads any `timeout` as the model's own, which
turns the 120 s move off and makes a background task's deadline. The model's own values are left
alone; Qwen3.6 sets one on most long commands.

Two short Qwen3.6 sessions on 2026-10-05 (a 3-minute build, a failing and a hanging unit test, a
health server to start and stop; `runs/bg-bash-qwen36/`):

- Without a line in the agent prompt it never used the flag: the build ran as `& wait` under its
  own 200 s timeout, the hanging test under its own 15 s, after which it deleted the test.
- With the line, the hanging test run (no `timeout`) moved to the background at 120 s and the
  model stopped it with `bash_kill` 3 s later, left the test file alone and said why it skipped
  it. It used `background: true` for the server, but with `&` in the command, so the task ended at
  once and the server lived on in its group until a `pkill`. The build it backgrounded with `&`
  and a log file and polled with `sleep`; one attempt passed `background=true` as an environment
  variable. Hence the prompt line names the plain command, without `&` or `timeout`.

## Vision

A browser test checks the DOM; what a canvas shows only a picture tells. In B2
([agent-sessions.md](agent-sessions.md#b2-qwen36)) Qwen3.6 saved Playwright screenshots and tried
to look at them through `xxd` and `read`, on a server that serves text only. `VISION` gives it the
picture: all three models ship a vision projector, and `VISION=1 ./install.sh model` puts the
pinned one at `$LAS_HOME/models/mmproj-$MODEL.gguf` (`MMPROJ_*` in the model file) and writes
`"input": ["text", "image"]` into pi's `models.json`. pi's `read` then sends a PNG to the model,
as a user message after the tool result, where it otherwise sends a note that the model cannot see
it. The agent prompt says which of the two it is: pi's own prompt and `read`'s description are the
same either way, so without a line a model takes screenshots it cannot look at, and finds out only
from the note after the call. `harness/pi/AGENTS.md` carries both lines, `harness/pi.py` keeps the one
for `VISION`. Once the projector is there `VISION` stays on, for `las serve` and every later harness
config; `VISION=0` turns it off, and like the window it has to reach both consumers: `las harness pi`
after changing it.

**On the CPU, so the configuration is untouched.** `server-flags.sh` adds `--mmproj` with
`--no-mmproj-offload`: the encoder (a ViT, `qwen3vl_merger` for all three) runs on the CPU
backend, and no buffer of it lands on the card. Measured per model (T-048, 2026-10-05,
`runs/T-048-vision/`): VRAM equal to the MiB, idle and after a request, with and without the
projector. It costs RAM instead, the file plus a 248 MiB compute buffer, ~0.7-1.1 GB, which
`preflight` adds to what the model holds (`MMPROJ_RAM_MB`). That matters for Qwen3.8-Flash only,
whose experts need every GB of page cache ([qwen38-flash.md](qwen38-flash.md#vision)).

**`IMAGE_MAX_TOKENS` 512.** A 1280x800 screenshot is 1 000 image tokens uncapped, and the encoder's
time on the CPU grows faster than its tokens. Qwen3.6, F16 projector, 8 threads, the B2 game
mid-round and its game-over screen, described with thinking off:

| Cap | Image tokens | Encode, CPU | Read |
| --- | --- | --- | --- |
| 256 | 240 | 3.2 s | the game-over screen; the game screen not: `GO!` as `00`, the trails as paddles and a ball |
| **512** | **476** | **10.0 s** | both screens, every name and state; the 10-pixel footer line half right |
| 768 | 735 | 22.4 s | everything |
| 1024, none | 1 000 | 43.1 s | everything |

512 is the smallest cap that reads a game screen; a screen whose small print matters reads at
`IMAGE_MAX_TOKENS=768` for twice the time. On top comes the model's own pass over the image
tokens: 1.2-1.7 s for Qwen3.6, 0.6 s for Bonsai, 6-9 s for Flash, which reads prompts on the CPU.
llama-server caches an image with the prompt, so a repeated request does not encode it again.

**What it costs the window.** An image stays in the history like a file read, until a compaction:
~480 tokens at 512 plus pi's line around it, so ten screenshots take ~5k of the budget's working
room ([Context budget](#context-budget)). The cap is the lever, not the budget values.

Through pi: a `pi -p` session against a stand-in server recorded the request pi builds for a
`read` of the game screenshot, and replayed to llama-server with the shipped flags, Qwen3.6
answered from the picture: a Tron light-cycle game, both names, `GO!`, two trails heading for the
centre (`runs/T-048-vision/mock.py`).

**Under Strata the engine brings it.** `strata launch` writes `--vision` and its own projector into
the run config, served by a `strata-vision` process on the CPU; nothing of ours is loaded, and
`IMAGE_MAX_TOKENS` does not reach it. `VISION` left empty follows that run config, so a Strata
configuration has the harness configs send images whenever Strata serves them, with or without
our projector in `LAS_HOME`; `VISION=0` only keeps the harness text-only. Measured for Qwen3.8-Flash
in [qwen38-flash.md](qwen38-flash.md#vision).

## Server lifecycle

`las serve` runs the engine in the foreground and owns nothing else: it starts no second process,
keeps no pid files and stops with Ctrl+C or SIGTERM. Run it in a terminal or under your own
supervisor (a user unit, tmux); a harness is pointed at it with `las harness`. The bench starts
and stops its own server per configuration. `las check CONFIG` asks the running server for a tool
call and its answer, so a model whose chat template mangles tool calls shows up before an agent
session does.

- **Own process group.** The bench starts the server in a session of its own, so a Ctrl+C that
  cancels a generation in a harness never reaches llama-server, which installs its own SIGINT
  handler and would quit.
- **Load time.** The first request waits for the load: `model loaded` after 7.7-7.9 s with Qwen3.6
  on this machine, the same with the model file evicted from the page cache
  (`posix_fadvise DONTNEED`).
- **Stopping.** llama-server exits on SIGTERM within ~1 s, and VRAM goes from 7 275 MiB back to 0.
- **Cancel.** SIGINT to a harness's process group mid-generation: it aborts its request (the server
  logs `cancel task`), the server keeps running and answers the next one.

### A server on another machine

`LISTEN_HOST` is what the engine binds to, `SERVER_HOST` what the client side - `las check`,
`las harness`, the `baseUrl` in the harness config - connects to. Both default to `127.0.0.1`,
which is the whole setup on one machine; the machine with the GPU and the machine you work on need
not be the same one.

To serve one GPU box to another host: `LISTEN_HOST=0.0.0.0 las serve` there, then
`SERVER_HOST=<box> las harness pi CONFIG` here. The harness config has to be written again because
it keeps a copy of the URL - the same drift as `CTX` and `PORT`.

- **There is no authentication.** The provider sends `apiKey: "none"` and llama-server asks for
  nothing, so `LISTEN_HOST=0.0.0.0` offers the model to everyone who can reach the port. On a
  network that is not yours, forward it instead - `ssh -N -L 8080:127.0.0.1:8080 <box>` - and
  leave `SERVER_HOST` at `127.0.0.1`; the tunnel needs no setting at all.
- **Latency is not the problem, bandwidth is not either.** A turn is one HTTP request and a
  token stream; on a LAN the round trip disappears next to a 27B model's generation time.

Verified: the URL that `config.env` derives for local, remote and remote-with-port, and the
config written from it. Not yet run against a real remote server - the machine this was written on
has no GPU.

## Unsloth Studio

`ENGINE=studio las serve CONFIG` opens the model the configuration names in [Unsloth Studio](https://github.com/unslothai/unsloth)
instead of a bare llama-server: Studio's chat UI and API, this repo's build and flags. It is
`unsloth studio run` with three things changed.

- **The build.** `LLAMA_SERVER_PATH` points Studio at `LLAMA_SERVER`, the tree the model file
  pins. That is the first place Studio looks, ahead of its own `~/.unsloth/llama.cpp`, so Bonsai
  runs on the fork and both Qwen models on the Unsloth tree this repo built, at the pinned source.
- **The flags.** `scripts/server-flags.sh` holds what the llama engine passes, and the studio engine
  hands the same list to Studio, which appends it after its own flags: llama.cpp's last value
  wins, so the configuration's placement, cache types, reasoning budget and `SERVER_ARGS` are what runs.
  The window goes as `--context-length`, MTP as `--speculative-type mtp` or `off`, one slot as
  `--parallel 1` (Studio's default of 4 splits `CTX`), sampling as Studio's pinning options,
  because Studio owns those flags and refuses or rewrites them as raw arguments.
- **Studio's own picks undone.** `--no-mmproj`: Studio picks a vision projector from beside the
  GGUF on its own, where `$LAS_HOME/models/` keeps every model's, and refuses `--mmproj` as a raw
  argument, so [Vision](#vision) stays with the llama engine and Studio serves text; `--load-mode auto`, because Studio
  reads a model into memory (`none`) when it estimates it fits, and the experts in RAM are
  measured mmapped.

Two details of Studio's parser decide how the flags are written. Its **manual** memory mode
strips every offload flag from the pass-through and has no command line option for the expert
count, so the studio engine stays in **auto**, which keeps an explicitly requested window ("no
silent shrink") and passes the flags through untouched. And its command line reads a short
cluster as its own options: `-ctxcp 4` ends in `-p`, its port. `server-flags.sh` and the model
files therefore use long spellings only (`--n-gpu-layers`, `--ctx-checkpoints`, ...), and so must
extra arguments after `--`.

Studio adds flags of its own that are left alone: `--metrics`, `--slot-save-path` (it saves a
slot's KV cache to disk when it unloads an idle model), `--chat-template-kwargs` with the same
`preserve_thinking: false` as `PRESERVE_THINKING`, `--video-fps`, and for Bonsai
`--ctx-checkpoints 21` against llama.cpp's 32, sized from host RAM. It also sends a system prompt and
tool definitions of its own, ~1.3k tokens on a one-line question. Its port is 8888, it has its own
login and API keys, and the harness configs point at the llama engine, not at it.

**One model per start.** `LLAMA_SERVER_PATH` holds for the whole Studio process, so a model picked
in Studio's model list afterwards runs on the tree of the configuration Studio was started
with, under Studio's own flags (window 8192, none of the configuration's). Seen on 2026-10-04: started as
Bonsai, Qwen3.6 then loaded on Bonsai's fork at 45.5 tok/s, and Qwen3.8-Flash failed with
`unknown model architecture: 'qwen4exp'`, which only Unsloth's tree knows. Another model means
quitting Studio and `ENGINE=studio las serve` with the other configuration.

Verified on 2026-10-02 with Studio 2026.9.12 (`unsloth` package), headless and without the GPU,
which the agent sandbox does not have: for all three models Studio started our build with every
flag of the configuration last on its command line and loaded at the configuration's window. Qwen3.6 and
Qwen3.8-Flash answered a chat request through its API on the CPU (21 tok/s with MTP accepting
55 %, and 6.2); Bonsai's ternary weights read a prompt on the CPU too slowly to wait for.

**On the card Studio costs nothing** (T-043, 2026-10-04, headless, from the user's shell, each
model started with its own configuration): VRAM and decode speed equal those of the llama engine.

| Model | VRAM under Studio | llama engine | tg under Studio | llama engine |
| --- | --- | --- | --- | --- |
| Bonsai, 64k | 7 748 MiB loaded, 7 758 after an answer | 7 747 / 7 758 | 36.1 tok/s | 36.6 |
| Qwen3.6, 131k, MTP | 7 260 MiB | 7 278 | 62.8 | 52-65 |
| Qwen3.8-Flash, 131k | 7 580 MiB | 7 566 | 17.0 | 18.6-18.9 warm |

Flash's 17.0 tok/s (and 27 tok/s on the prompt) was a first pass right after another model, with
experts still coming from the SSD: the level of a cold pass under the llama engine (17.8). Studio's
extra flags and its ~1.3k-token system prompt leave Bonsai's 441 MiB of margin where it was.

## localagent workflow

A multi-agent build pipeline for this model, run on pi. **Decided 2026-09-23: frozen and not
recommended**, and its code is no longer in this repo. On a small CLI it finished in the time the
model takes alone; on the study's Tron prompt it was stopped after 2:50 with its first unit
unfinished, where the model alone built the game in 1:30. What stopped it was the model -
compactions inside a worker, whole-file rewrites, broken tests of its own - not the harness.
[`localagent.md`](localagent.md) has the runs and the shape. What it constrains here is only the
window: a dispatched agent that ends on `length` comes back as `BLOCKED`, see
[Context budget](#context-budget).
