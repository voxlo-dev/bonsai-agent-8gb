# AGENTS.md

Agent-agnostic project guide — the single source for domain, structure and code style. `README.md` is for users, this file for contributors and AI agents.

## Project outline

This repo is **not an application**. It is a reproducible setup: bash scripts that build a patched llama.cpp, fetch a pinned GGUF, and configure the [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) coding agent against it. There is no source code to compile here — the thing being assembled lives in `~/.local/share/bonsai-local` (`BONSAI_HOME`).

| Path | Role |
| --- | --- |
| `config.env` | **Single source of truth.** Every setting, with `: "${VAR:=default}"` so an environment variable always wins. Sources the profile first |
| `profiles/{dedicated,display}.env` | `CTX` and the four budget values, per GPU situation (`PROFILE`, default `dedicated`). They constrain each other, so they move together |
| `install.sh` | Step runner: `deps build model pi link`, all of them by default |
| `scripts/lib.sh` | Sourced first by every step; sources `config.env` and defines `log`/`warn`/`die`/`has` |
| `scripts/{deps,build,model,pi}.sh` | One install step each, individually re-runnable and idempotent |
| `bin/bonsai-server` | The launcher. Sources `config.env` **directly**, not through `lib.sh` |
| `bin/bonsai-pi` | Starts the pinned pi with `PI_CODING_AGENT_DIR` set to `PI_AGENT_DIR`, and starts/stops `bonsai-server` around it when none runs. State in `$BONSAI_HOME/run/`. Same sourcing as `bonsai-server` |
| `pi/pi-agents.md` | Runtime artifact, copied to `$PI_AGENT_DIR/AGENTS.md`. **Not this file** |
| `pi/extensions/localagent/` | pi extension behind `bonsai-pi --localagent`: the `dispatch` tool and the test wall. Copied with the workflow into `$PI_AGENT_DIR/extensions/localagent/` |
| `pi/localagent-workflow/` | The workflow it runs (skill, seven agent prompts, templates). Written for OpenCode, its setup and dispatch parts adapted to pi |

**Two consumers, one config.** `config.env` feeds both the llama-server command line and, through `scripts/pi.sh`, a JSON config written into `PI_AGENT_DIR` (`$BONSAI_HOME/pi-agent`), a private pi instance that never touches `~/.pi`. They drift silently: the server takes its values at start, pi keeps a written copy. After changing `CTX`, `PORT`, `MAX_TOKENS`, `RESERVE_TOKENS` or `KEEP_RECENT_TOKENS`, `./install.sh pi` must run again.

**The context budget is arithmetic, not taste.** `CTX`, `BUDGET`, `MAX_TOKENS`, `RESERVE_TOKENS` and `KEEP_RECENT_TOKENS` constrain each other, which is why they live in a profile and move together; getting them wrong makes pi compact on every single turn or lets it request more tokens than the window holds. The constraints and the measurements behind them are in [`docs/dev.md`](docs/dev.md#context-budget). Do not change one of them alone.

## Build / test / run

- Build: `./install.sh` (or a single step: `./install.sh build`; `FORCE=1 ./install.sh build` rebuilds)
- Test:  **none** — there is no test framework; see Conventions
- Run:   `bonsai-pi` (starts the server itself), or `bonsai-server` first to keep it running
- Version: unversioned; the repo pins what matters instead (`LLAMA_COMMIT`, `MODEL_REV`, `MODEL_SHA256`, `PI_VERSION` in `config.env`)

## Conventions

- **Every non-default choice is justified in `docs/dev.md`, with the measurement behind it.** That is the repo's actual product — the scripts are short, the reasons are not. A new flag or setting without a `docs/dev.md` entry is incomplete.
- **Pins are deliberate.** `LLAMA_COMMIT`, `MODEL_REV` and `MODEL_SHA256` exist because the model needs a fork that mainline llama.cpp has not absorbed. Moving a pin means re-testing load and speed. `PI_VERSION` pins the compaction code the context budget was measured against; moving it means re-checking [`docs/dev.md`](docs/dev.md#context-budget).
- **Steps stay idempotent.** Each script checks whether its work is already done and exits early.
- **Nothing is installed into the repo.** Build output, the model and pi's config all live outside it.
- **Nothing is installed into the user's own tools.** No global npm package, nothing under `~/.pi`: a user's existing pi keeps its providers, defaults and compaction settings.

### Verifying a change

There is no test suite, and adding one was considered and declined (bash, no framework, one user). Verify by observation instead:

- Server flags: start it and query `http://127.0.0.1:8080/props`, or render a conversation through `/apply-template` to see what the chat template actually produces
- pi's config: read back `$BONSAI_HOME/pi-agent/{models,settings}.json`
- pi's behaviour: its session logs are JSONL at `$BONSAI_HOME/pi-agent/sessions/{cwd-slug}/` (sessions before the private instance: `~/.pi/agent/sessions/`), one entry per message, with `usage` token counts and `compaction` records — that is where a context problem is visible
- `bash -n` on any script touched

### Code style

- POSIX-ish bash, `set -euo pipefail` via `lib.sh`; `bin/bonsai-server` sets it itself
- A comment block at the top of every script saying what it does and what it needs
- Settings are declared in `config.env` only (the window and budget values in `profiles/*.env`), never hard-coded in a consumer

## Doc map

Docs are split by **lifespan**, and every fact has exactly one home:

- **durable** — `docs/`, truth about the shipped system, versioned with the code
- **living** — `backlog/`, open work, carried across sprints, dissolved once shipped
- **ephemeral** — `artefacts/`, process memory: live for the running sprint, frozen when `close-sprint` closes it

| Doc | Tier | Content |
| --- | --- | --- |
| `README.md` | — | user-facing entry point: install, use, configure |
| `AGENTS.md` | — | this file: structure, code style, conventions |
| `docs/dev.md` | durable | why each non-default choice is what it is, with the measurement behind it; plus troubleshooting. Doubles as this project's decisions log |
| `backlog/` | living | one file per ticket (`T-NNN-{slug}.md`), indexed in `backlog.md`, which carries the `Next ticket` counter |
| `artefacts/{sprint}/` | ephemeral | workflow run artifacts, bound to their sprint, frozen at `close-sprint`. Absent until the first sprint opens |
| `.temp/` | ephemeral | gitignored scratch root, safe to delete at any time |
| `runs/` | ephemeral | gitignored, but **kept**: one folder per long test run (`{ticket}-{slug}/`) with its `run.sh` and log, so a result stays readable after the chat that produced it |

## Current sprint

`none`

<!-- The only living pointer that belongs in AGENTS.md. Other living state has a lifespan-correct
     home: goals → the sprint file; open work & open decisions → `backlog/`;
     gotchas/learnings → project memory (`maintain-memory`). -->
