# AGENTS.md

Where a contributor or an AI agent starts. `README.md` is for people using this;
`CONTRIBUTING.md` is the short human version of this file.

## What this repo is

**Not an application.** The docs for running coding-agent models on an 8 GB card - a curated
selection, each measured on real hardware - and the bash that starts them: it builds a patched llama.cpp, fetches a pinned GGUF,
serves a **configuration** (`configs/NAME.env`) with `las` on llama-server, Strata or Unsloth
Studio, and writes ready-made configs for the harnesses pi and opencode. Nothing here compiles into
a product; the thing being assembled lives in `~/.local/share/local-agent-suite` (`LAS_HOME`). No
harness is installed by it.

Which means the code is short and the **reasons are the product**. Every non-default choice - a
flag, a cache type, a token count - answers a failure observed on real hardware, and that reason
lives in `docs/` with the measurement behind it ([`docs/dev.md`](docs/dev.md) says where). A change without one is
incomplete, and a change that contradicts one needs a new measurement, not an argument.

## Map

| Path | Role |
| --- | --- |
| `config.env` | **Single source of truth.** Every setting, with `: "${VAR:=default}"` so an environment variable always wins. Resolves `CONFIG` (environment, else `$LAS_HOME/default.env`, else `qwen36-35b`), sources `configs/$CONFIG.env` (or `$CONFIG_FILE`), then `models/$MODEL.env`, then its defaults |
| `configs/*.env` | One **configuration** each: `MODEL=`, the window and budget (`CTX`, `BUDGET`, `MAX_TOKENS`, `RESERVE_TOKENS`, `KEEP_RECENT_TOKENS`; for the MoE `CPU_MOE`, `UB`), `ENGINE=llama\|strata\|studio`, anything else a variant changes. Self-contained: a variant repeats the base values. `{model}` is the card driving no display, `{model}-display` one that does, `-vulkan` the AMD path. `las` and the harness writers resolve a name here |
| `models/{bonsai,qwen36-35b,qwen38-flash,lfm25-24b}.env` | Per `MODEL`: `MODEL_SUPPORT` (`supported` or `unsupported`, only a supported one's configurations join the ramp), the GGUF pin, the llama.cpp tree that runs it (`LLAMA_*`, `PATCH_DIR`), `CHAT_TEMPLATE` (a file under `templates/`), KV types, sampling, `EFFORT`, `SPEC_TYPE`, the vision projector (`MMPROJ_*`), a drafter shipped as its own GGUF (`DRAFT_*`), what preflight checks (`MODEL_DISK_MB`, `MODEL_RAM_MB`, backends) and how the ramp shows it (`MODEL_TITLE`, `MODEL_ROLE`, a configuration may set its own); `SERVER_ARGS` for flags no setting covers. No window or budget |
| `models/trees/unsloth.env` | Unsloth's llama.cpp pin, sourced by both Qwen model files on CUDA since they share its build dir. Not a model: nothing reads `models/trees/` as one |
| `templates/` | Chat template files a model file names with `CHAT_TEMPLATE`, passed as `--chat-template-file` and part of the fit and setup keys. Empty until a model's own template fails `las check` |
| `install.sh` | Step runner: `deps build model link`, all of them by default. Without `CONFIG` and `default.env` it asks for a configuration of the ramp by the RAM (on a terminal) and records it in `$LAS_HOME/default.env`; then runs `preflight`. A Strata configuration runs `link` only: Strata is the user's install. `link` links only `las` and removes the old `qwen-*`/`kolibri*` links that point into the clone |
| `scripts/preflight.sh` | Gates a run before it spends time: disk, RAM and the configurations of the ramp it allows, Strata for a Strata configuration, driver, VRAM, Node, port. Reports every item, exits once. `SKIP_PREFLIGHT=1` bypasses it |
| `scripts/lib.sh` | Sourced first by every step; sources `config.env` and defines `log`/`warn`/`die`/`has`, and the ramp by RAM that `install.sh` and preflight share (`print_ramp`, `recommended_config`), the configurations `RAMP` and `RAMP_ALSO` in `config.env` name |
| `scripts/{deps,build,model}.sh` | One install step each, individually re-runnable and idempotent. `deps` and `build` branch on `BACKEND` (`cuda`, `vulkan`); `build` fetches a git commit, or a checksummed release tarball (`LLAMA_TARBALL`) where the commit is not fetchable (Unsloth's tree) |
| `bin/las` | The launcher, the only command. `serve [--print] [CONFIG] [-- args]` starts the configuration in the foreground on its `ENGINE`; `list`; `check CONFIG` (the tool-call round-trip, `scripts/check_tools.py`); `harness pi\|opencode CONFIG [--dir DIR]`; `launch pi\|opencode [CONFIG] [-- args]` (that config, the server in the background unless it runs, the harness from `PATH`, the server stopped by the last session). Without a configuration named or recorded, `serve` and `launch` take the ramp's pick for the RAM. Starts nothing it was not asked to start and installs no harness |
| `scripts/server-flags.sh` | The llama-server flags and environment of the selected configuration, sourced by `las serve`. Long spellings only: Unsloth Studio's parser misreads short clusters |
| `scripts/strata_config.py` | Prepares a Strata run config (`prepare(cfg, out, exact)`, `overrides(cfg)`) for `las serve` (approximations on, as Strata ships them) and for a measurement (`exact=True`, approximations off) |
| `scripts/check_tools.py` | The `las check` round-trip against `SERVER_URL`, stdlib only; a failure names the step (request, tool_calls, arguments, result, answer) |
| `harness/{pi,opencode}.py` | Write a harness's config for a configuration: pi's `models.json`, `settings.json` with the compaction budget, `AGENTS.md`, pi-bg-bash; opencode's `opencode.json`. Used by `las harness`. Neither installs the harness |
| `harness/pi/AGENTS.md` | The agent prompt `harness/pi.py` copies into pi's config dir. **Not this file** |
| `patches/{backend}/*.patch` | Applied by `build` to the fork at `LLAMA_COMMIT`, in name order, for that backend only, and only for a model whose `PATCH_DIR` names them (Bonsai). Today: the PTQ1_0 Vulkan `mul_mm` loader, +35 % on prompts, until upstream takes it |
| `patches/unsloth/*.patch` | Applied the same way to Unsloth's tree (`models/trees/unsloth.env`), so both Qwen models build with it: Qwen3.8-Flash's sparse attention at decode attends over the selected cells instead of the whole cache |
| `test/smoke/las.sh` | `las list`, `las serve --print` for each engine, an environment value beating the configuration, both harness writers into a temp dir. Runs in the sandbox |

## Four things that bite

**Two consumers, one config.** `config.env` feeds both the engine's command line and, through
`harness/*.py`, a config file written for a harness. They drift silently: the server takes its
values at start, the harness keeps a written copy. After changing `CTX`, `SERVER_HOST`, `PORT`,
`MAX_TOKENS`, `RESERVE_TOKENS`, `KEEP_RECENT_TOKENS` or `VISION`, `las harness pi CONFIG` (or
`opencode`) must run again, with the same configuration.

**The context budget is arithmetic, not taste.** `CTX`, `BUDGET`, `MAX_TOKENS`, `RESERVE_TOKENS`
and `KEEP_RECENT_TOKENS` constrain each other, which is why they live in one configuration and move
together. Getting them wrong makes pi compact on every single turn, or lets it ask for more tokens
than the window holds. Never change one alone; the constraints are in
[`docs/agent.md`](docs/agent.md#context-budget).

**Pins are deliberate.** `LLAMA_COMMIT`, `MODEL_REV` and `MODEL_SHA256` exist per model: Bonsai
needs a fork mainline llama.cpp has not absorbed, Qwen Unsloth's tree (a source tarball, checksummed) whose MTP drafting and sparse attention were measured, mainline on Vulkan. `PI_VERSION` pins the compaction code the budget
was measured against. Moving any of them means re-testing load and speed, checking that `patches/`
still applies (`build` refuses when it does not), and for `PI_VERSION` re-checking the budget.

**Nothing is installed into the repo, and nothing into the user's own tools.** Build output, the
model and the harness configs live outside it. No global npm package, no harness installed by us,
nothing under `~/.pi` or in a user's opencode config unless `--dir` points there.

## Working on it

```bash
./install.sh                       # everything; FORCE=1 ./install.sh build rebuilds
BACKEND=vulkan ./install.sh build  # the AMD path, patches and all
CONFIG=bonsai ./install.sh         # another configuration next to it: its tree, its GGUF
las serve                          # the default configuration, in the foreground
las list                           # what there is, and what is supported
```

Unversioned: the repo pins what matters instead. Each step checks whether its work is done and
exits early, so a second run is cheap and says so.

**There is no test suite** for the install scripts: it is bash, there is no framework, and what
breaks is behaviour under a real model on a real card. Verify by observation. The launcher is the
exception, with `test/smoke/las.sh`: it has a deterministic happy path.

| Change | How to see it worked |
| --- | --- |
| Any script | `bash -n`, and run the step twice to confirm it is still idempotent |
| `las`, `config.env`, a configuration | `test/smoke/las.sh` (sandbox): `list`, `serve --print` per engine, precedence, both harness writers |
| Preflight | run it where it should fail (no GPU, wrong `BACKEND`, too little disk): one screen, nothing touched |
| Server flags | `las serve --print CONFIG`, then start it, query `http://127.0.0.1:8080/props`, or render a conversation through `/apply-template` |
| A window, a configuration, a tree or a build flag | one prompt filling `CTX - RESERVE_TOKENS`, `nvidia-smi` alongside, and the server still up afterwards. A window that loads is not a window that holds: the CUDA pool grows outside the reserved buffers. Its speed: generation and prompt tok/s at a stated depth, against the number in `docs/` |
| Vulkan kernels | generation and an ~850-token prompt at a stated window, judged by tok/s. VRAM is misleading: RADV only reports it meaningfully after the first request |
| A harness config | `las harness pi CONFIG --dir $TMPDIR/x`, read back `models.json` and `settings.json` (opencode: `opencode.json`) |
| A new architecture | `las check CONFIG` against the running server: it names the failing step |
| pi's behaviour | its session logs, JSONL under `sessions/{cwd-slug}/` in the config dir `las harness pi` wrote (default `$LAS_HOME/harness/pi/{config}/`), one entry per message with `usage` counts and `compaction` records. That is where a context problem is visible |

A long measurement gets a folder under `runs/{slug}/` with its script and log. `runs/` is
gitignored but kept, so a result stays readable after the session that produced it; the conclusion
belongs in `docs/`.

## Code style

- POSIX-ish bash, `set -euo pipefail` via `lib.sh`; `bin/las` sets it
  itself
- A comment block at the top of every script saying what it does and what it needs
- `SPDX-License-Identifier: MIT` on the second line, or the first in a file with no shebang
- Settings are declared in `config.env` only, `models/*.env` for what differs per model, or
  `configs/*.env` for the window, the budget and what a candidate varies. A configuration repeats
  its base's values rather than sourcing it. Never hard-code one in a consumer
- Messages go through `log`/`warn`/`die`. A `die` says what to do next, and names a
  `docs/` anchor when there is one

## Where facts live

Every fact has one home, chosen by how long it stays true.

| | Lifespan | Holds |
| --- | --- | --- |
| `README.md` | — | the user-facing entry point: what it is, install, use, configure |
| `AGENTS.md` | — | this file |
| `CONTRIBUTING.md` | — | the short human form of this file: the measurement rule, what gets declined |
| `docs/dev.md` | durable | the index: which file holds which reason, and where each pre-split anchor went |
| `docs/setup.md` | durable | build, toolchain, platforms, RAM and build memory, preflight, troubleshooting |
| `docs/agent.md` | durable | the harness configs (pi, opencode), the context budget and its arithmetic, the agent prompt, vision, the server lifecycle, Unsloth Studio |
| `docs/agent-sessions.md` | durable | every Tron session, all models, one table plus each day's write-up. A new session is a row here |
| `docs/{bonsai,qwen36,qwen38-flash,lfm25}.md` | durable | one per `MODEL`: its pin and tree, why each of its settings, its speed, window and configurations. A new model gets its own |
| `docs/performance.md` | durable | what limits generation speed: the bandwidth roofline, and the optimizations tried and rejected |
| `docs/context-window.md` | durable | the window and the KV cache for both models: what fits on 8 GB, the silent WSL2 spill, KV quality against f16 |
| `docs/localagent.md` | durable | **Frozen**: the localagent workflow, whose code is no longer in this repo: why it was not recommended, its shape, the measured runs |
| `docs/model-comparison.md` | durable | eight local models as coding agents on 8 GB, from the study predating this repo. **Frozen**: a record of finished work. New measurements go to the file that holds the topic |
| `runs/` | ephemeral | gitignored but kept: one folder per long measurement |
| `.temp/` | ephemeral | gitignored scratch, safe to delete at any time |
