# Local Agent Suite

**Docs and a bench for running coding-agent models on an ordinary 8 GB graphics card.** The card
was never the limit: the RAM next to it decides how large a model it runs. This repo holds what
was measured about that, the bench that measures it, and a launcher that starts any measured
setup.

- **Configurations**: `configs/NAME.env` is a model plus its window, budget, KV cache and engine.
  The launcher serves one, the bench measures one.
- **`las`**: starts a configuration on llama-server, [Strata](https://github.com/Niko1221/Strata)
  or [Unsloth Studio](https://github.com/unslothai/unsloth), checks its tool calls, and writes a
  ready-made config for the coding agents [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
  and [opencode](https://opencode.ai). It installs neither.
- **The bench** ([`bench/`](bench/README.md)): agent tasks (pi in a container, a hidden checker),
  chat tasks and a speed test, over configurations x tasks x repeats, with an HTML dashboard.
  Results: [docs/bench.md](docs/bench.md).
- **The reasons**: every non-default setting answers a failure seen on real hardware, and the
  measurement behind it is in [`docs/`](docs/dev.md).

## Which model

Mixture-of-experts models only use a few billion parameters per token, so their experts can live
in system RAM while the card holds the rest. More RAM, a bigger model. Each step below is a
configuration the bench measured on an RTX 4060 Ti 8 GB with a Ryzen 7 7800X3D, native Linux, no
display on the card ([docs/bench.md](docs/bench.md), tier 1, one repeat each):

| RAM next to the card | Configuration | Engine | tok/s at 512 · 64k | Window | Agent · chat tasks |
| --- | --- | --- | --- | --- | --- |
| **16 GB** | [LFM2.5-24B-A2B](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B) UD-Q4_K_XL (`lfm25-24b`) | llama.cpp | 62 · 49 | 131k | 9/14 · 32/36 |
| **32 GB** | [Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) UD-Q4_K_XL (`qwen36-35b`) | llama.cpp | 51 · 50 | 131k | 12/14 · 35/38 |
| **64 GB** | [Qwen3.8-Flash-Next](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF) 125B, ISTA-DASLab's [GSQ-RCO IQ3_XXS](docs/bench.md#qwen38-flash-gsq-rco-iq3_xxs-optimized) (`qwen38-flash-gsq-iq3xxs-strata`) | Strata | 42 · 38 | 262k | 13/14 · 33/36 |

**When quality counts more than speed**:

- **32 GB, agent work:** [Flint](https://huggingface.co/RecursiveSI/flint) 40B-A2.5B UD-Q4_K_XL
  (`flint`, llama.cpp, 51 · 36 tok/s, 131k, [14/14 · 23/36](docs/bench.md#flint-in-tier-2)): every
  agent task at Qwen3.6's speed, but weak at chat, worst in German - not a multilingual chat assistant.
- **32 GB, lean agent:** [Ornith-1.5-35B-A3B](https://huggingface.co/ornith-ai/Ornith-1.5-35B-A3B)
  Q4_K_M (`ornith-35b`, llama.cpp, 56 · 48 tok/s, 131k, [13/14 · 26/36](docs/bench.md#ornith-15-35b-in-tier-2)):
  a Qwen3.6 fine-tune that passes one agent task more with a third less thinking, and the only
  model here to pass the hallucination tasks; the weaker chat assistant, in German especially.
  Qwen3.6 or Ornith is a matter of taste.
- **64 GB:** Qwen3.8-Flash on UD-IQ4_XS (`qwen38-flash-strata-dflash2`, Strata, 30 · 26 tok/s, 131k,
  14/14 · 35/39). It also runs without Strata, on this repo's llama.cpp (`qwen38-flash`, ~19 tok/s,
  not benched in tier 1).

`./install.sh` reads your RAM, offers these seven and recommends the largest step that fits; the
two Strata configurations need [Strata](#strata) first. Other models run and bench like any
configuration but are not offered until a bench run has measured them: Ternary-Bonsai-2-27B
([details](docs/bonsai.md)) and Kolibri-1 ([details](docs/kolibri1.md)). A new model or
architecture: the [`bench-add-model` skill](.agents/skills/bench-add-model/SKILL.md) and
[docs/dev.md](docs/dev.md).

## Install

You need an **8 GB NVIDIA or AMD card**, **Linux or WSL2**, and the RAM from the table above.

```bash
git clone https://github.com/voxlo-dev/qwen-agent-8gb.git
cd qwen-agent-8gb
./install.sh                    # NVIDIA
BACKEND=vulkan ./install.sh     # AMD
```

It checks your machine first and stops with a list of anything missing, before it downloads or
compiles. Then a 10-30 minute build and the download; re-running is safe. On Windows, set up WSL2
first: [Windows](docs/setup.md#windows). Disk and the rest: [Requirements](#requirements).

## Use

```bash
las launch pi                   # the default configuration's server if none runs, then pi on it
las launch opencode qwen36-35b -- --continue   # another one; arguments after -- go to the harness
las list                        # every configuration: model, engine, window, supported or not
las serve                       # the default configuration, in the foreground
las serve qwen38-flash          # another one
las serve qwen36-35b -- --port 9000   # arguments after -- go to the engine
las serve --print qwen36-35b    # the command, not started
las check qwen36-35b            # tool-call round-trip against the running server
las harness pi qwen36-35b       # pi's config for it, then: PI_CODING_AGENT_DIR=... pi
las harness opencode qwen36-35b # opencode's, then: OPENCODE_CONFIG=... opencode
```

The default configuration is the one `./install.sh` recorded in `$LAS_HOME/default.env`, picked by
your RAM; `CONFIG` or a name overrides it, and without the file `las` takes the same RAM pick.

The server is a plain OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1` for any tool.
`las serve` starts nothing but what it is asked to. `las launch` is the short way: it writes the
harness config, starts the server in the background unless that configuration already serves
(log in `$LAS_HOME/server.log`), runs pi or opencode from your `PATH`, and stops the server it
started once the last launched session ends ([details](docs/agent.md#server-lifecycle)).
`las harness` only writes: into `$LAS_HOME/harness/HARNESS/CONFIG` unless `--dir` says otherwise,
and prints the environment variable its harness reads. Neither installs a harness or touches
`~/.pi` or an opencode config of yours. Unsloth Studio runs the same model with the same settings:
[details](docs/agent.md#unsloth-studio).

## Speed

Generation and prompt reading in tok/s as the context fills, same machine as above:

| Configuration | tg 512 | tg 32k | tg 64k | pp 8k · 32k · 64k |
| --- | --- | --- | --- | --- |
| `lfm25-24b` | 62.0 | 54.8 | 49.0 | 1118 · 1150 · 985 |
| `qwen36-35b` | 50.8 | 56.2 | 49.8 | 938 · 899 · 796 |
| `qwen38-flash-gsq-iq3xxs-strata` | 42.2 | 37.0 | 38.3 | 811 · 999 · 975 |
| `qwen38-flash-strata-dflash2` | 29.5 | 26.6 | 25.7 | 574 · 716 · 689 |

**Do not let this GPU drive your monitor.** A desktop takes 0.5-1.2 GB of VRAM and GPU time, both
out of the model; plug the monitor into the mainboard's iGPU. If you cannot, the `-display`
configuration of a model (`las serve qwen36-35b-display`) makes room. Where each setting comes
from: [docs/performance.md](docs/performance.md) and the pages per model.

## Strata

[Strata](https://github.com/Niko1221/Strata) is an engine written for Qwen3.8-Flash, and the only
one that runs ISTA-DASLab's GSQ quants as meant. It is not installed by this repo: install Strata
`0.2.10` (`STRATA_VERSION`) yourself, then run `strata launch` once and pick the preset the
configuration names (`IQ3_XXS 256K` or `UD-IQ4_XS 128K Flash2`); its GGUF and engine are Strata's
own. Preflight says what is missing. `las serve` then runs the preset with this repo's window,
alias and port, with the approximations Strata ships with on
([bench/README.md#strata](bench/README.md#strata)). Without Strata, `qwen38-flash` runs the same
model on llama.cpp.

## Configure

A configuration is one file in [`configs/`](configs/), named for what it is: `qwen36-35b` is the
model on a card that drives no display, `qwen36-35b-display` the same for one that does,
`qwen36-35b-vulkan` the AMD path. `las list` shows them all. Each sets `MODEL=` (a file in
[`models/`](models/): the GGUF pin, the llama.cpp tree, KV types, sampling) and the window and
budget values that constrain each other ([Context budget](docs/agent.md#context-budget)), and
may set `ENGINE=llama|strata|studio`. Settings and their defaults are in [`config.env`](config.env),
each with a comment. Precedence: environment, then the configuration, then the model file, then
the defaults:

```bash
CONFIG=qwen38-flash las serve
CTX=65536 las serve qwen36-35b
```

After changing the window, the port or the budget, run `las harness pi CONFIG` again so the
harness config matches the server.

**Vision**, off by default: the model reads images, e.g. the screenshots of its own browser tests.
The projector runs on the CPU, so it costs no VRAM, ~1 GB of RAM and ~10 s per screenshot; it stays
on once installed, `VISION=0` turns it off. Strata brings its own projector, so a Strata
configuration sees images whenever its preset does: [details](docs/agent.md#vision).

```bash
VISION=1 ./install.sh model
```

## Requirements

Measured: every configuration above on an RTX 4060 Ti 8 GB under Linux Mint 22.3, natively. Qwen3.6
also runs on an AMD RX 570 8 GB under Debian 13 with Vulkan, ~25 tok/s on UD-Q4_K_M
(`qwen36-35b-vulkan`), and under Windows 11 through WSL2 ([Windows](docs/setup.md#windows)).

Expected to work, unmeasured: RTX 20xx to 40xx and RDNA2/3 cards with 8 GB or more; RTX 50xx needs
CUDA >= 12.8. If you run one, a [hardware report](../../issues/new?template=hardware-report.yml) is
the most useful thing you can send. Not supported: less than 8 GB of VRAM, ROCm, Metal, CPU-only.

Disk: 15 GB for LFM2.5, 22 GB for Qwen3.6, 88 GB for Qwen3.8-Flash on llama.cpp, plus ~10 GB for
the build and the CUDA toolkit; Strata keeps its own files. Drivers, toolkit versions, Node for the
bench's pi image and what `deps` installs per distro: [docs/setup.md](docs/setup.md#toolchain).

## Install in detail

`./install.sh` runs `deps build model link` in order; name steps to run only those.

| Step | Does |
| --- | --- |
| `deps` | the apt toolchain: CUDA or Vulkan, cmake, gcc (asks for sudo) |
| `build` | the model's llama.cpp tree at its pinned version (`FORCE=1` rebuilds) |
| `model` | the GGUF, from the Hugging Face cache or downloaded, checksummed |
| `link` | `las` into `~/.local/bin` |

The configuration you pick is recorded in `$LAS_HOME/default.env` and is what `las` runs without
a name; a Strata one runs `link` only, since Strata brings its engine and files. Another one
installs next to it with `CONFIG=bonsai ./install.sh` and runs with `las serve bonsai`. Everything lands in `~/.local/share/local-agent-suite`
(`LAS_HOME`); moving an existing data dir: [docs/setup.md](docs/setup.md#moving-an-existing-data-dir).

## How it was measured

Every non-default setting in this repo answers a failure seen on real hardware, and the
measurement behind it is in [`docs/`](docs/dev.md). Speed, VRAM and windows are reproducible.
Agent quality is measured by [the bench](bench/README.md); the early sessions were single runs on
one prompt ([docs/agent-sessions.md](docs/agent-sessions.md)). The starting point was a study of
eight local models as coding agents on an 8 GB card:
[docs/model-comparison.md](docs/model-comparison.md).

## Uninstall

```bash
rm -rf ~/.local/share/local-agent-suite ~/.local/bin/las
rm -rf ~/.local/state/pi-bg   # pi-bg-bash's task logs, if a pi session ran with it
```

That includes the models and the harness configs. The apt packages from `deps` stay.

## Contributing

Issues, pull requests and hardware reports welcome. [CONTRIBUTING.md](CONTRIBUTING.md) has the one
rule: a non-default choice arrives with the measurement that justifies it. Working on the code:
[AGENTS.md](AGENTS.md).

## Your hardware

This fills an 8 GB card to within a few hundred megabytes and keeps the GPU, and for the Qwen
models tens of gigabytes of RAM, busy for as long as a session runs. Nothing here overclocks,
raises a power limit or touches a fan curve. Your cooling, power supply and driver are yours.
Provided as is, no warranty: see [LICENSE](LICENSE).

## Credits

- The [Qwen team](https://huggingface.co/Qwen) for Qwen3.6-35B-A3B and Qwen3.8-Flash-Next
- [Liquid AI](https://huggingface.co/LiquidAI) for LFM2.5-24B-A2B, and
  [ISTA-DASLab](https://huggingface.co/ISTA-DASLab) for the GSQ quants of Qwen3.8-Flash, which
  [Strata](https://github.com/Niko1221/Strata) runs
- [Unsloth](https://github.com/unslothai/unsloth) for the GGUFs, the llama.cpp tree both Qwen
  models run on, and Unsloth Studio
- [PrismML](https://prismml.com) for Ternary Bonsai 2 27B and the
  [llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) that loads it
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp), including whoever wrote the IQ-grid
  Vulkan shaders the patch follows, and the reporter of
  [PrismML-Eng/llama.cpp#185](https://github.com/PrismML-Eng/llama.cpp/issues/185), who made that
  work findable
- Mesa and RADV, and [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) by earendil-works

The weights are their authors', under the licenses on their model cards, downloaded at install
time and never redistributed here. The model comparison and the localagent record come from a
project thesis at Technische Hochschule Mittelhessen by this repo's author.

**License: [MIT](LICENSE)**, including the `PTQ1_0` Vulkan loader in [`patches/vulkan`](patches/vulkan/),
which is offered upstream under the same terms.
