# AGENTS.md

Where a contributor or an AI agent starts. `README.md` is for people using this;
`CONTRIBUTING.md` is the short human version of this file.

## What this repo is

**Not an application.** The docs and the bench for running coding-agent models on an 8 GB card,
and the bash that starts what they measure: it builds a patched llama.cpp, fetches a pinned GGUF,
serves a **configuration** (`configs/NAME.env`) with `las` on llama-server, Strata or Unsloth
Studio, and writes ready-made configs for the harnesses pi and opencode. Nothing here compiles into
a product; the thing being assembled lives in `~/.local/share/local-agent-suite` (`LAS_HOME`). pi
exists here only as the harness the bench measures, pinned in its image.

Which means the code is short and the **reasons are the product**. Every non-default choice - a
flag, a cache type, a token count - answers a failure observed on real hardware, and that reason
lives in `docs/` with the measurement behind it ([`docs/dev.md`](docs/dev.md) says where). A change without one is
incomplete, and a change that contradicts one needs a new measurement, not an argument.

## Current sprint

None. The bench campaign runs without one, model by model: [`backlog/bench-campaign.md`](backlog/bench-campaign.md),
each model tuned first by `bench-optimize`. This clone is the private fork (`origin` is its
`bench.privateRemote`), so the campaign works on `main`.

## Map

| Path | Role |
| --- | --- |
| `config.env` | **Single source of truth.** Every setting, with `: "${VAR:=default}"` so an environment variable always wins. Resolves `CONFIG` (environment, else `$LAS_HOME/default.env`, else `qwen36-35b`), sources `configs/$CONFIG.env` (or `$CONFIG_FILE`, which the bench points at a run's snapshot), then `models/$MODEL.env`, then its defaults |
| `configs/*.env` | One **configuration** each: `MODEL=`, the window and budget (`CTX`, `BUDGET`, `MAX_TOKENS`, `RESERVE_TOKENS`, `KEEP_RECENT_TOKENS`; for the MoE `CPU_MOE`, `UB`), `ENGINE=llama\|strata\|studio`, anything else a campaign candidate varies. Self-contained: a variant repeats the base values. `{model}` is the card driving no display, `{model}-display` one that does, `-vulkan` the AMD path, the rest bench candidates. `las`, the bench (`--config`, `fit`) and the harness writers all resolve a name here |
| `models/{bonsai,qwen36-35b,qwen38-flash,kolibri1}.env` | Per `MODEL`: `MODEL_SUPPORT` (`supported` or `unsupported`, only supported ones are offered by `install.sh` and preflight), the GGUF pin, the llama.cpp tree that runs it (`LLAMA_*`, `PATCH_DIR`), `CHAT_TEMPLATE` (a file under `templates/`), KV types, sampling, `EFFORT`, `SPEC_TYPE`, the vision projector (`MMPROJ_*`), what preflight checks (`MODEL_DISK_MB`, `MODEL_RAM_MB`, backends) and how the model list shows it (`MODEL_TITLE`, `MODEL_ROLE`); `SERVER_ARGS` for flags no setting covers. No window or budget |
| `models/trees/unsloth.env` | Unsloth's llama.cpp pin, sourced by both Qwen model files on CUDA since they share its build dir. Not a model: the model list reads `models/*.env` only |
| `templates/` | Chat template files a model file names with `CHAT_TEMPLATE`, passed as `--chat-template-file` and part of the fit and setup keys. Empty until a model's own template fails `las check` |
| `install.sh` | Step runner: `deps build model link`, all of them by default. Without `CONFIG` and `default.env` it asks for a supported model's configuration by the RAM (on a terminal) and records it in `$LAS_HOME/default.env`; then runs `preflight`. `link` links only `las` and removes the old `qwen-*`/`kolibri*` links that point into the clone |
| `scripts/preflight.sh` | Gates a run before it spends time: disk, RAM and the supported models it allows, driver, VRAM, Node, port. Reports every item, exits once. `SKIP_PREFLIGHT=1` bypasses it |
| `scripts/lib.sh` | Sourced first by every step; sources `config.env` and defines `log`/`warn`/`die`/`has`, and the model list by RAM that `install.sh` and preflight share (`print_ramp`, `recommended_model`) |
| `scripts/{deps,build,model}.sh` | One install step each, individually re-runnable and idempotent. `deps` and `build` branch on `BACKEND` (`cuda`, `vulkan`); `build` fetches a git commit, or a checksummed release tarball (`LLAMA_TARBALL`) where the commit is not fetchable (Unsloth's tree) |
| `bin/las` | The launcher, the only command. `serve [--print] [CONFIG] [-- args]` starts the configuration in the foreground on its `ENGINE`; `list`; `check CONFIG` (the tool-call round-trip, `scripts/check_tools.py`); `harness pi\|opencode CONFIG [--dir DIR]`. Sources `config.env` **directly**, not through `lib.sh`. Starts nothing it was not asked to start and installs no harness |
| `scripts/server-flags.sh` | The llama-server flags and environment of the selected configuration, sourced by `las serve`. Long spellings only: Unsloth Studio's parser misreads short clusters |
| `scripts/strata_config.py` | Prepares a Strata run config (`prepare(cfg, out, exact)`, `overrides(cfg)`) for `las serve` (approximations on, as Strata ships them) and the bench (`exact=True`, approximations off) |
| `scripts/check_tools.py` | The `las check` round-trip against `SERVER_URL`, stdlib only; a failure names the step (request, tool_calls, arguments, result, answer) |
| `harness/{pi,opencode}.py` | Write a harness's config for a configuration: pi's `models.json`, `settings.json` with the compaction budget, `AGENTS.md`, pi-bg-bash; opencode's `opencode.json`. Used by `las harness` and, for pi, by the bench for its container. Neither installs the harness |
| `harness/pi/AGENTS.md` | The agent prompt `harness/pi.py` copies into pi's config dir. **Not this file** |
| `patches/{backend}/*.patch` | Applied by `build` to the fork at `LLAMA_COMMIT`, in name order, for that backend only, and only for a model whose `PATCH_DIR` names them (Bonsai). Today: the PTQ1_0 Vulkan `mul_mm` loader, +35 % on prompts, until upstream takes it (T-017) |
| `patches/kolibri1/` | Applied the same way to Kolibri-1's tree on both backends: the `kolibri1` architecture, from the GGUF's repository |
| `patches/unsloth/*.patch` | Applied the same way to Unsloth's tree (`models/trees/unsloth.env`), so both Qwen models build with it: Qwen3.8-Flash's sparse attention at decode attends over the selected cells instead of the whole cache (T-051, T-053) |
| `bench/` | The agent bench (T-055 to T-065): agent tasks (pi in a container, a hidden checker), chat tasks (one prompt to the server, graded by rules) and the speed test (`speed/`, tok/s and VRAM at depth), one module each in `lib/kinds/`. `templates/` holds a blank task per kind (`run.py new`), and `run.py generate` draws tasks from a family under `tasks/_gen/`, `run.py validate` proves a task before `plan` and `run` let it count. `image.sh` builds the image every agent attempt runs in (it pins pi with `PI_VERSION`, and pi-bg-bash with `PI_BG_BASH_*`), `run.py attempt` runs one task, `run.py plan`/`run` a resumable run of configurations x tasks x repeats with `report` and `compare`, reusing every result of an unchanged setup across runs and giving each task a token budget from `budget.toml`, `run.py dashboard` writes every run into one interactive HTML page (`lib/dashboard.html`), `run.py watch` follows it live in the author's terminal (it prints task content, so never an agent's call on `tasks/`). A run measures configurations from `configs/` (by name, `--config`); its server is `las serve`, or Strata prepared by `scripts/strata_config.py`, started, fit-checked and stopped by the runner. `bench/README.md` says how. `tasks/` is the private task set, the author's or generated: an agent writes generators and runs `generate`, but never reads an instance or its validation logs, nor a task but one handed over for formatting, never pushes to a public remote. `examples/` is public, format only. Runs outside the Claude sandbox |
| `.agents/skills/bench-*` | Claude's procedures for the bench (T-060): `bench-run`, `bench-report`, `bench-add-task`, `bench-add-model` (also the new-architecture path), `bench-optimize`, each calling `bench/run.py` (`bench-optimize` also `llama-perplexity` and Strata). Linked into `.claude/skills/` by the user, since the sandbox cannot write there; the bench's pi never sees them (`--no-skills`) |
| `test/smoke/las.sh` | `las list`, `las serve --print` for each engine, an environment value beating the configuration, both harness writers into a temp dir. Runs in the sandbox |
| `test/smoke/bench-{attempt,run,generate,score}.sh` | One attempt of `bench/examples/hello` against the running server must pass; a run of hello, the chat example and the speed test with its own server must record all three, resume and report each kind, a second run reuse them, a third stop at a tiny budget; `bench-generate` draws the example family and `bench-score` checks budgets, malformed tool calls, score and rating on synthetic data, both in the sandbox |
| `scripts/git-hooks/pre-push` | Refuses a push to any remote not in `bench.privateRemote` when a pushed commit touches `bench/tasks/`. Enabled per clone with `git config core.hooksPath scripts/git-hooks` |

## Four things that bite

**Two consumers, one config.** `config.env` feeds both the engine's command line and, through
`harness/*.py`, a config file written for a harness. They drift silently: the server takes its
values at start, the harness keeps a written copy. After changing `CTX`, `SERVER_HOST`, `PORT`,
`MAX_TOKENS`, `RESERVE_TOKENS`, `KEEP_RECENT_TOKENS` or `VISION`, `las harness pi CONFIG` (or
`opencode`) must run again, with the same configuration. The bench rewrites its own pi config per
run, so only a hand-written one goes stale.

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
breaks is behaviour under a real model on a real card. Verify by observation. The bench is the
exception, with smoke scripts in `test/smoke/`: it has a deterministic happy path.

| Change | How to see it worked |
| --- | --- |
| Any script | `bash -n`, and run the step twice to confirm it is still idempotent |
| `las`, `config.env`, a configuration | `test/smoke/las.sh` (sandbox): `list`, `serve --print` per engine, precedence, both harness writers |
| The bench | `test/smoke/bench-attempt.sh` with the server running, `test/smoke/bench-run.sh` without; both outside the sandbox. `bench-generate.sh` and `bench-score.sh` inside it |
| Preflight | run it where it should fail (no GPU, wrong `BACKEND`, too little disk): one screen, nothing touched |
| Server flags | `las serve --print CONFIG`, then start it, query `http://127.0.0.1:8080/props`, or render a conversation through `/apply-template` |
| A window, a configuration, a tree or a build flag | `run.py fit` on a bench configuration of it: one prompt to `CTX - RESERVE_TOKENS` in full ubatches, `nvidia-smi` alongside. A window that loads is not a window that holds: the CUDA pool grows outside the reserved buffers. Its speed: a run of `--tasks speed`, `compare`d with the one before (`bench/README.md#speed-test`); a number in `docs/` names its run |
| Vulkan kernels | generation and an ~850-token prompt at a stated window, judged by tok/s. VRAM is misleading: RADV only reports it meaningfully after the first request |
| A harness config | `las harness pi CONFIG --dir $TMPDIR/x`, read back `models.json` and `settings.json` (opencode: `opencode.json`) |
| A new architecture | `las check CONFIG` against the running server: it names the failing step |
| pi's behaviour | its session logs, JSONL under `$LAS_HOME/bench/pi-agent-{config}/sessions/{cwd-slug}/`, one entry per message with `usage` counts and `compaction` records. That is where a context problem is visible |

A long measurement gets a folder under `runs/{ticket}-{slug}/` with its script and log. `runs/` is
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
| `docs/{bonsai,qwen36,qwen38-flash,kolibri1}.md` | durable | one per `MODEL`: its pin and tree, why each of its settings, its speed, window and configurations. A new model gets its own |
| `docs/performance.md` | durable | what limits generation speed: the bandwidth roofline, and the optimizations tried and rejected |
| `docs/context-window.md` | durable | the window and the KV cache for both models: what fits on 8 GB, the silent WSL2 spill, KV quality against f16 |
| `docs/localagent.md` | durable | **Frozen**: the localagent workflow, whose code is no longer in this repo: why it was not recommended, its shape, the measured runs |
| `docs/model-comparison.md` | durable | eight local models as coding agents on 8 GB, from the study predating this repo. **Frozen**: a record of finished work. New measurements go to the file that holds the topic, or a ticket |
| `backlog/` | living | one file per ticket, `T-NNN-{slug}.md`, indexed in `backlog.md` with the `Next ticket` counter. A private one gets `.local.md` and stays out of the repo, so the numbers have gaps |
| `artefacts/{sprint}/` | living until the sprint closes | the sprint file: goal, non-goals, decisions, and the board indexing its tickets |
| `runs/` | ephemeral | gitignored but kept: one folder per long measurement |
| `.temp/` | ephemeral | gitignored scratch, safe to delete at any time |

Closing a ticket means its result is in `docs/` and its file is deleted. Nothing is left behind as
a note.
