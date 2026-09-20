# Development notes

Why the setup looks the way it does. Each choice below answers a failure seen on an RTX 4060 Ti 8 GB under WSL2.

## Model format

The GGUF stores its weights as `PTQ1_0` (ggml type 143), a Prism-specific ternary format: 1.75 bits per weight, with one fp16 scale per 128 weights. Mainline llama.cpp rejects the file at load time:

```
tensor 'output.weight' has invalid ggml type 143. should be in [0, 67)
```

Only the [PrismML fork](https://github.com/PrismML-Eng/llama.cpp) (branch `prism`) has the kernels. `config.env` pins the tested commit. Mainline support is tracked in [ggml-org/llama.cpp#29058](https://github.com/ggml-org/llama.cpp/issues/29058).

Architecture (`qwen35`): 64 blocks, every 4th is full attention (16 layers, 4 KV heads × 256 dims), and the rest are Gated DeltaNet with fixed-size recurrent state. Native context is 262,144 tokens.

## Build

- **Static** (`BUILD_SHARED_LIBS=OFF`): the binary carries its own ggml/llama code, so it cannot pick up another llama.cpp's shared libraries from the same directory.
- **`GGML_CUDA_FA_ALL_QUANTS=ON`**: without it, CUDA flash attention only handles K and V of the *same* type. A mixed cache such as `q8_0`/`q4_0` then falls back to the CPU. Generation speed dropped from 34 to 20 tok/s at 2k context and down to 8 tok/s at 10k, with the GPU at 39 % load.
- **gcc-13 as CUDA host compiler**: Ubuntu's CUDA 12.4 `nvcc` refuses gcc newer than 13, and newer Ubuntu releases default to gcc 15.
- **`CMAKE_CUDA_ARCHITECTURES`** comes from `nvidia-smi` (`89` for Ada). Compiling for one architecture is much faster than for the default set.
- **ccache** speeds up rebuilds and is used when present; the build works without it.
- OpenSSL is not needed: it only enables HTTPS model downloads inside llama-server, and `bonsai-server` passes a local path.

## Toolchain

`./install.sh deps` takes everything from apt and is tested on Ubuntu 26.04 only, where
`nvidia-cuda-toolkit` is CUDA 12.4. Known limits beyond that, not yet tested on a machine
(see the backlog):

- **Other Ubuntu releases:** 24.04 ships CUDA 12.0, whose `nvcc` accepts gcc up to 12, not the
  gcc-13 the build picks. 22.04 ships CUDA 11.5, which does not know `sm_89` (Ada), and has no
  `gcc-13` package.
- **RTX 50xx** (`sm_120`) needs CUDA >= 12.8, i.e. NVIDIA's own repository. `build.sh` stops
  early when the GPU is newer than the installed `nvcc`.
- **Native Linux:** apt's toolkit pulls in `libnvidia-compute-*` of its own version. Under WSL2
  that is harmless - `ldd llama-server` resolves `libcuda.so.1` to `/usr/lib/wsl/lib`, which
  comes first in the loader path. Next to a native driver of another version it can cause a
  driver/library version mismatch.
- **Other GPUs:** the fork also carries `PTQ1_0` kernels for Vulkan, ROCm/HIP, Metal and the
  CPU. This setup builds CUDA only.

Disk, measured: model 5.6 GB, `llama.cpp` checkout and build 1.9 GB, ccache ~0.25 GB, apt's
CUDA toolkit with its dependencies ~5.4 GB. The binary links `libcudart` and `libcublas`
dynamically, so the toolkit stays after the build. pi needs Node.js >= 22.19 (`engines` in its
`package.json`) and takes 440 MB in `$BONSAI_HOME/pi`.

## VRAM budget

| Item | MiB |
| --- | --- |
| Model weights on GPU | 5,395 |
| Compute buffer | ~250 |
| KV cache, per 1k tokens, `q8_0`/`q8_0` | 34 |
| KV cache, per 1k tokens, `q8_0`/`q4_0` | 26 |

At 48k context with `q8_0`/`q4_0` the process holds ~7.3 GB of 8 GB. **64k is the default**: measured at 7 747 MiB of 8 188, 36 tok/s at short context and no layer on the CPU - 441 MiB to spare, which is why the GPU must drive no display. 80k does not fit.

**Display on the iGPU.** When the RTX also drives the Windows desktop, the desktop takes 0.5 to 1.2 GB and competes for GPU time. With the monitor on the mainboard (iGPU enabled in BIOS, browsers set to "Power saving" under Windows *Settings → System → Display → Graphics*), generation went from 21 to 34 tok/s in the same browser-based session.

**No `--fit`, forced `-ngl 99`.** llama.cpp's auto-fit keeps a safety margin. On 8 GB that margin pushes 10 to 12 layers to the CPU, and partial offload costs this architecture about 10× decode speed (3–4 tok/s). The fork's memory estimate is accurate. The margin is the problem.

## KV cache

Keys are more sensitive to quantization than values, so K stays at `q8_0` and V drops to `q4_0`. This saves ~25 % of the KV cache compared with `q8_0`/`q8_0`. llama.cpp has no `q6` cache type. The options are `f16`, `bf16`, `q8_0`, `q5_1`, `q5_0`, `q4_1`, `q4_0` and `iq4_nl`. A quantized V cache requires flash attention (`-fa on`).

## Reasoning

The chat template reads `reasoning_effort` (`low`, `medium`, `xhigh`) and **defaults to `xhigh`**. At `xhigh` it tells the model to "think carefully, validate key assumptions, consider plausible alternatives". At `medium` it adds nothing, and at `low` it asks for brief thinking.

On coding tasks the model drafts entire implementations inside its thinking block before calling any tool. Measured on a full-stack game prompt:

| Setting | Thinking | Answer |
| --- | --- | --- |
| `xhigh`, no budget (in pi) | 24k tokens, hit the output cap | none |
| `low`, no budget | 12k tokens, hit the cap | none |
| `medium`, no budget | 12k tokens, hit the cap | none |
| `medium`, budget 3k | ~2.7k tokens | plan + code |

Budget size shows up in the result, not just in the token count. At 4096 the model produced
a single-file game and claimed test runs it never performed; at 8192, with the same prompt
and the 64k window, it built a server-authoritative game with two integration tests that
work. See the table under [Context budget](#context-budget).

The effort level barely matters. The hard budget is what works: `--reasoning-budget` cuts thinking after N tokens, and `--reasoning-budget-message` is injected before the end-of-thinking tag to push the model into acting. Each agent turn gets a fresh budget.

Do not enable pi's thinking levels for this model (`"reasoning": true` in `models.json`). pi would send levels such as `high` or `minimal`, which the template rejects with an exception. The server sets the level.

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
worst case inside the window. `install.sh pi` writes the two compaction keys into
`$BONSAI_HOME/pi-agent/settings.json`.

Because these five constrain each other, they live in `profiles/*.env` and move together.
`PROFILE=dedicated` (default) is the 64k window below. `PROFILE=display` is the 48k set the
measurements above were taken with - `CTX` 48000, `BUDGET` 4096, `MAX_TOKENS` 12000,
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
[Reasoning](#reasoning)). The other lever, `RESERVE_TOKENS` 16000, would keep 8 192 of
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

The middle run is the `display` profile, the right one is `dedicated`. Fewer, larger steps
beat many small ones here: half the steps of the 4096 run, in the same time, for a result
that holds up. The 64k run's closest approach to pi's clamp left 5 372 tokens of margin, so
the trigger was never the limit.

The 4096 re-run (session `2026-09-19T19-16-01`): 168 steps in
112 minutes, and the run ended on its own (`stopReason: stop`) with no step cut off on
`length`. 7 compactions, 8-33 steps apart, back at 14.5-19.4k each time. 6 steps hit the
budget. The largest output was 11 441 tokens, 4k thinking plus a ~7k `write`, at 7.6k
context where the clamp still allowed the full 12 000. The same step just below the trigger
would be cut off, so the tool-call allowance above is a typical case, not a bound.

## Thinking in the prompt

The chat template renders every earlier thinking block back into the prompt:

```jinja
{%- if preserve_thinking is undefined or preserve_thinking is true or loop.index0 > ns.last_query_index %}
    {{- '<|im_start|>' + message.role + '\n<think>\n' + reasoning_content + '\n</think>\n\n' + content }}
```

pi sends them: its thinking blocks carry `thinkingSignature: "reasoning_content"`, and the
openai-completions provider writes that field back onto each assistant message. In the
session above, the 29 745-character thinking block from the first turn (~7.4k tokens) rode
along in every later prompt.

`PRESERVE_THINKING=false` passes `--no-reasoning-preserve` (the fork's switch for the
template's `preserve_thinking`), which keeps thinking only for messages after the last user message - the current turn.
Note what that does **not** cover: inside one long agent turn there is no later user
message, so that turn's own thinking is all preserved. It pays off across turns, and after
a compaction, since pi feeds the summary back as a `user` message (`dist/core/messages.js`)
which resets `last_query_index`.

## Telling the model to think less

`$BONSAI_HOME/pi-agent/AGENTS.md`, installed from [`pi/pi-agents.md`](../pi/pi-agents.md), asks the model to
decide one action and call the tool rather than drafting code inside the thinking block.
pi loads it into the system prompt at startup; `--append-system-prompt` and
`--system-prompt` are the per-run equivalents. Treat it as a nudge, not a control: the
measurements under [Reasoning](#reasoning) show this model ignores instructions about
thinking length, including the template's own effort levels. `BUDGET` remains the only
thing that reliably stops it.

## pi

`bonsai-pi` runs a private pi: `install.sh pi` puts version `PI_VERSION` into `$BONSAI_HOME/pi`
(`npm install --prefix`, no `-g`, no sudo), and the wrapper sets `PI_CODING_AGENT_DIR` to
`$BONSAI_HOME/pi-agent`. pi resolves every user path through that variable (`getAgentDir()`
in `dist/config.js`): providers, settings, `AGENTS.md`, auth, sessions.

The first version wrote into the global `~/.pi/agent` instead, and collided with any pi
already in use there:

- `defaultProvider`/`defaultModel` were overwritten, so a plain `pi` started on Bonsai.
- The compaction keys are global or per project, not per model (`settings-manager.js`).
  A 200k model then kept 8k of recent history per compaction instead of 20k.
- `AGENTS.md`, telling the model to think briefly on a small window, went into every
  model's system prompt - or, when the user had their own, ours was skipped.
- Whatever pi version was installed ran, while the budget arithmetic under
  [Context budget](#context-budget) reads pi 0.85.1's compaction code.

A project directory's own `.pi/settings.json` still applies to both instances; that is
pi's per-project override and intended.

pi reads providers from `models.json`. `contextWindow` decides when pi compacts, together with the settings under [Context budget](#context-budget) - not `maxTokens`, which is only the per-turn output cap. Unsloth's `unsloth start pi` hard-codes `maxTokens = min(context / 4, 8192)`, which cuts a single long reasoning turn off at 8k. That is why this setup uses its own config.

## Server lifecycle

`bonsai-pi` owns the server only when it started it. On start it checks `/health` on `PORT`;
with no answer it launches `bonsai-server` in the background and waits until `/health`
returns 200 (the model is loaded), at most `SERVER_START_TIMEOUT` seconds. Every run then
checks `/v1/models` for `MODEL_ALIAS`, so pi never talks to some other server on that port.

- **Shared server.** Each session registers its PID in `$BONSAI_HOME/run/sessions/` under a
  `flock`. The last session to leave stops the server; sessions that died without cleaning
  up are pruned by PID. `run/server.pid` exists only for a server `bonsai-pi` started, so a
  server started by hand is never stopped.
- **Own session (`setsid`).** The server runs outside the terminal's process group: Ctrl+C
  in pi - which cancels a generation - must not reach llama-server, which installs its own
  SIGINT handler and would quit.
- **Orphans.** A session killed with SIGKILL, or a terminal window closed hard, runs no trap:
  its server stays up with its pid still in `run/server.pid`. The next `bonsai-pi` prunes the
  dead session entries and adopts that server, so it stops when that session leaves. Verified.
- **Traps.** Closing the terminal (HUP), TERM or QUIT runs the cleanup. While pi runs, the wrapper
  catches SIGINT with a no-op: uncaught, bash would die with pi when pi exits on SIGINT and skip
  the cleanup. While waiting for the model, Ctrl+C aborts and stops the server.

Verified with a stand-in server and pi: one session, two overlapping ones, Ctrl+C caught by
pi, pi killed by SIGINT, Ctrl+C during load, HUP, a hand-started server, and a server that
dies during start. With the real model:

- The first session waits for the load: `model loaded` after 7.7-7.9 s, the same with the
  model file evicted from the page cache (`posix_fadvise DONTNEED`). A one-line `bonsai-pi -p`
  takes 14 s end to end. `SERVER_START_TIMEOUT` 300 has ample margin on this machine.
- llama-server exits on SIGTERM within ~1 s, and VRAM goes from 7 275 MiB back to 0.
- Two overlapping sessions share one server; the last to end stops it.
- SIGINT to one session's process group mid-generation: pi aborts its request (the server
  logs `cancel task`), the server keeps running and answers the other session.
- `run/` holds no session and no `server.pid` after each run.

## localagent workflow

`pi/localagent-workflow/` is a multi-agent build (plan gate, per-unit TDD loop behind a
test/implementation wall, e2e and docs) written for OpenCode. Its skill and the orchestrator prompt
describe pi now: no agent registration, `dispatch({ agent, brief })` as the only way to start an
agent, template paths passed absolute, the wall drop as naming test paths in the brief. The protocol
itself - phases, gates, who fixes what - is unchanged; `codegraph`, which this setup does not have,
is gone from the agent prompts. The agent frontmatter keeps the OpenCode dialect. `bonsai-pi --localagent`
runs it on pi through the extension in `pi/extensions/localagent/`, which `install.sh pi` copies
with the workflow into `$PI_AGENT_DIR/extensions/localagent/`. Without the flag the extension
registers nothing.

**Own extension, not pi-subagents.** [pi-subagents](https://pi.dev/packages/pi-subagents) 0.69.0
was tried first, installed into a scratch agent dir against a stand-in endpoint:

- Parent prompt with it: 31.3k chars (system prompt + tool schemas), without it 5.8k. The
  `subagent` tool alone is 18.9k chars, of which 13.8k is a parameter schema that none of its
  `toolDescriptionMode`s shortens; a minimal custom description still left 29.1k. The
  orchestrator needs `{agent, brief}`.
- It checks `permission:` per tool only (`read: deny`), no path globs, so it rejects the
  implementer's OpenCode block as an invalid agent definition.
- Its builtin `worker` answers to the alias `implementer`: a small model that drops the
  `localagent-` prefix would reach an agent without the wall.

With this extension the parent prompt is 12.3k chars against 6.8k without the flag: 764 for
the `dispatch` tool, the rest the orchestrator prompt and the skill entry - the workflow itself.

**Each agent is a separate `pi -p` process** (the pattern of pi's own
`examples/extensions/subagent`), started from pi's own entry point so it runs the pinned version:

- `--no-extensions --no-skills --no-prompt-templates --no-context-files`: nothing the orchestrator
  loaded reaches it, not `AGENTS.md`, not `dispatch` (no nested dispatch). The brief is its
  whole context, as the workflow demands. pi's base prompt stays: the agent prompt is appended
  (`--append-system-prompt`), since the base prompt explains the tools to a small model.
- Dispatches are queued, one at a time: the server has one slot (`--parallel 1`), and the
  workflow requires the sequential shape anyway.
- The result is the agent's status line (`DONE`, `ESCALATE`, `BLOCKED`, `PASS`,
  `FIXES_REQUIRED`, `NO_SURFACE`), the last one in its final message, so a chatty reply does not
  fill the orchestrator's window. A child that ends on anything but `stop` - `length` included,
  see [Context budget](#context-budget) - or exits non-zero comes back as a tool error, which
  the workflow treats as `BLOCKED`.
- Its session goes to `sessions/{cwd-slug}/dispatch/{orchestrator-session-id}/`, beside the
  orchestrator's own log.

**The wall** is `wall.ts`, loaded only into agents whose definition carries an OpenCode
`permission.read` block with `deny` entries - the implementer. Those globs are the wall, read
from the agent file, so the list has one home. It blocks `read` (and `grep`/`find`/`ls`, when
active) on matching paths relative to the project; a directory counts when its contents would.
`bash` stays open, as in OpenCode: running the tests is the point, and the workflow says so
("one restriction is enforced; everything else is prompt"). The wall drop needs no switch: a
test path the brief names explicitly stays readable (relative or absolute, sentence punctuation
stripped), and the workflow puts test paths in the brief exactly when it drops the wall.

**Flag order.** pi hands an unknown flag the next argument as its value when that argument does
not start with `-`. Extension flags count as unknown there, so `bonsai-pi --localagent "task"`
swallows the task. `--` ends option parsing and makes the rest the prompt:
`bonsai-pi --localagent -- "task"`, with or without `-p`.

Verified against a scripted stand-in endpoint that plays orchestrator and implementer: without
the flag no `dispatch` and no skill; with it the orchestrator prompt and the skill are in the
system prompt, the child has no `dispatch` and no `AGENTS.md`, its `read` of a test file is
blocked with the wall's message, the same read passes when the brief names the file, and the
orchestrator gets `DONE src/foo.ts` from a reply that wraps it in prose. Not yet run against
the model: [T-013](../backlog/T-013-localagent-first-run.md).

## Sampling

`--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0` is the model card's **thinking-mode** preset,
which is the mode this setup runs (`--reasoning on`, and the whole budget arithmetic depends on
it). The card's second preset - `temperature=0.7, top_p=0.80, presence_penalty=1.5` - belongs to
instruct/non-thinking mode. It is a mode, not a temperature dial: taking the 0.7 alone into
thinking mode mixes two presets and is not what the card recommends.

`--min-p 0.0` has to be passed explicitly. llama.cpp defaults it to 0.05, so leaving it out
silently deviates from the preset; the flag's own help reads `0.0 = disabled`. This was the only
deviation from the model card in the shipped command line.

A temperature change buys no speed: 35.92 tok/s at 1.0 against 35.89 at 0.7, identical within
noise.

Speculative decoding is off. The fork offers draft-model-free n-gram modes via `--spec-type`,
and they were measured in three ways - no configuration beat the baseline on a real agent
workload, and loosening their triggers made it worse. Acceptance runs at 6-20 % where
break-even is above 50 %. The full result, including why a synthetic benchmark showed a
misleading 1.59x, is in [Performance](performance.md#speculative-decoding-tried-rejected).

## Troubleshooting

| Symptom | Cause · fix |
| --- | --- |
| `invalid ggml type 143` | Stock llama.cpp is running. Start through `bonsai-server`. |
| Generation slows sharply as context grows, GPU load low | Mixed K/V cache types on a build without `FA_ALL_QUANTS`: `FORCE=1 ./install.sh build` |
| `offloaded N/65 layers` with N < 65 | `--fit` is active or VRAM is taken. Check `nvidia-smi` and move the display to the iGPU. |
| Slower while a browser is visible | The browser renders on the RTX. Switch it to the iGPU in Windows graphics settings. |
| `sudo: a terminal is required` | Run `./install.sh deps` in a real terminal, not through an agent's shell. |
| `pi -p` hangs in scripts | pi waits on stdin without a TTY: add `< /dev/null`. |
| `pi` talks to another model, or ignores the budget | Plain `pi` is your global instance. Start `bonsai-pi`. |
| `bonsai-server exited during start` | Read `$BONSAI_HOME/server.log`; usually VRAM taken by another process, see `nvidia-smi`. |
| `no bonsai-server with model ... on port` | Something else listens on `PORT`. Stop it or set another `PORT`, then `./install.sh pi`. |
| Answer ends after exactly `MAX_TOKENS` | The output cap was hit. Raise `MAX_TOKENS` or lower `BUDGET`. |
| `stopReason: length` well below `MAX_TOKENS`, near a compaction | pi's output clamp: `BUDGET` too large for `RESERVE_TOKENS - 4096`. See [Context budget](#context-budget). |
| pi compacts every turn, most of the time goes into summarizing | `RESERVE_TOKENS`/`KEEP_RECENT_TOKENS` are unset or too large for `CTX`: `./install.sh pi`. See [Context budget](#context-budget). |
