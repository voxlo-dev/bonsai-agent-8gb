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
in system RAM while the card holds the rest. More RAM, a bigger model. **Supported** models are
offered by `./install.sh` and recommended by preflight; **unsupported** ones run and bench like any
other, but are not offered until a bench run has measured them.

| RAM next to the card | Model | Speed | Window | Support |
| --- | --- | --- | --- | --- |
| **32 GB** | **[Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)** (`qwen36-35b`) | **52-65 tok/s** | **131k** | **supported, the default: fast, most work** |
| 64 GB | [Qwen3.8-Flash-Next](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF), 125B (`qwen38-flash`) | ~19 tok/s | 131k | supported, the strongest, for when it may take longer |
| any | [Ternary-Bonsai-2-27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf), all on the card (`bonsai`) | 40 tok/s | 64k | unsupported until benched ([details](docs/bonsai.md)) |
| 64 GB | [Kolibri-1](https://huggingface.co/Aleph-Alpha/Kolibri-1), 78B, on a patched llama.cpp (`kolibri1`) | ~44 tok/s | 131k | unsupported until benched; no valid agent session yet ([details](docs/kolibri1.md)) |

`./install.sh` reads your RAM, shows the supported ones and asks. How they did as agents on the
same task: [the agent sessions](docs/agent-sessions.md).

A model of another architecture gets its own llama.cpp tree, its chat template and a checked
tool-call round-trip, with no installer entry; LFM2.5-24B is the first candidate (hoped to replace
Bonsai): `configs/lfm25-24b.env`, unsupported until benched ([docs/lfm25.md](docs/lfm25.md)). The path is in the
[`bench-add-model` skill](.agents/skills/bench-add-model/SKILL.md) and [docs/dev.md](docs/dev.md).

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
las list                        # every configuration: model, engine, window, supported or not
las serve                       # the default configuration, in the foreground
las serve qwen38-flash          # another one
las serve qwen36-35b -- --port 9000   # arguments after -- go to the engine
las serve --print qwen36-35b    # the command, not started
las check qwen36-35b            # tool-call round-trip against the running server
las harness pi qwen36-35b       # pi's config for it, then: PI_CODING_AGENT_DIR=... pi
las harness opencode qwen36-35b # opencode's, then: OPENCODE_CONFIG=... opencode
```

The server is a plain OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1` for any tool.
`las serve` starts nothing but what it is asked to. `las harness` prints the environment variable
its harness reads and writes into `$LAS_HOME/harness/HARNESS/CONFIG` unless `--dir` says otherwise;
it never touches `~/.pi` or an opencode config of yours. Unsloth Studio runs the same model with
the same settings: [details](docs/agent.md#unsloth-studio).

## Speed

The same card and the same models, three levels of effort. Generation in tok/s, RTX 4060 Ti 8 GB,
Ryzen 7 7800X3D, 64 GB RAM:

| | Bonsai | Qwen3.6 | Qwen3.8-Flash |
| --- | --- | --- | --- |
| **Download and go**: the GGUF with default settings | ~4 | ~25 | ~4 |
| **This repo's configuration**: the right llama.cpp tree, expert placement, KV cache, multi-token prediction; under WSL2 | 36 | 39-45 | 9-10 |
| **Plus the system**: native Linux, no display on the card | 39.6 | **52-65** | **~19** |

The biggest single step after the configuration: **do not let this GPU drive your monitor.** A
desktop takes 0.5-1.2 GB of VRAM and GPU time, both out of the model; plug the monitor into the
mainboard's iGPU. If you cannot, the `-display` configuration of each model (`las serve qwen36-35b-display`) makes room. Bonsai's WSL2 figure predates its
current llama.cpp pin, which is 8 % faster on native Linux. Where each number comes from:
[docs/performance.md](docs/performance.md) and the pages per model.

Speed falls as the context fills. Qwen3.8-Flash held 16.4 tok/s at 64k and 14.3 at 110k, up from
12.9 and 10.5, once the model's sparse attention stopped running over the whole cache at decode:
a patch in [`patches/unsloth/`](patches/unsloth/) ([details](docs/qwen38-flash.md#decode-at-depth)).

## And Strata?

[Strata](https://github.com/Niko1221/Strata) is an engine written for Qwen3.8-Flash alone. **On a
card with 12 GB or more, it is the faster choice:** 53-94 tok/s on an RTX 5070 by its own numbers.
On an 8 GB card with the same GGUF, this repo is the better fit:

| Same file (UD-IQ4_XS), same 8 GB card | this repo | Strata |
| --- | --- | --- |
| Window | 131k | 4.6-8k, chosen by its setup on a card this size |
| Experts per token | all 10, exact | missed low-ranked experts skipped by default, about one quant step of accuracy by its own measurement |
| Decode | 19.0-19.6 tok/s short, 14.3 at 110k | 14.3 and 19.4 on two short requests at 8k |
| Coding agent | harness configs written for it, the context budget measured | pi's requests are refused at that window until `fit_max_tokens` is set |

Strata is faster on 8 GB in one setup: its own 3-bit quant, measured less accurate than this
repo's, ran an 8 GB laptop at ~29 tok/s with a 262k window. Nothing of Strata's transfers to
llama.cpp by a flag, but reading it found the dense attention above. The full comparison:
[docs/qwen38-flash.md](docs/qwen38-flash.md#strata-a-dedicated-engine).

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
on once installed, `VISION=0` turns it off: [details](docs/agent.md#vision).

```bash
VISION=1 ./install.sh model
```

## Requirements

Measured, each with a logged run:

| Card | System | Qwen3.6 | Qwen3.8-Flash | Bonsai |
| --- | --- | --- | --- | --- |
| RTX 4060 Ti 8 GB | Linux Mint 22.3, native | 52-65 tok/s | ~19 tok/s | 39.6 tok/s |
| RTX 4060 Ti 8 GB | Windows 11 + WSL2, Ubuntu 26.04 | 39-45 tok/s | 9-10 tok/s | 36 tok/s |
| AMD RX 570 8 GB | Debian 13, Vulkan (Mesa 26.1) | ~25 tok/s | - | 7 tok/s; this repo's Vulkan patch reads prompts 35 % faster |

Expected to work, unmeasured: RTX 20xx to 40xx and RDNA2/3 cards with 8 GB or more; RTX 50xx needs
CUDA >= 12.8. If you run one, a [hardware report](../../issues/new?template=hardware-report.yml) is
the most useful thing you can send. Not supported: less than 8 GB of VRAM, ROCm, Metal, CPU-only.

Disk: 22 GB for Qwen3.6, 88 GB for Qwen3.8-Flash, 6 GB for Bonsai, plus ~10 GB for the build and
the CUDA toolkit. Drivers, toolkit versions, Node for the bench's pi image and what `deps` installs per distro:
[docs/setup.md](docs/setup.md#toolchain).

## Install in detail

`./install.sh` runs `deps build model link` in order; name steps to run only those.

| Step | Does |
| --- | --- |
| `deps` | the apt toolchain: CUDA or Vulkan, cmake, gcc (asks for sudo) |
| `build` | the model's llama.cpp tree at its pinned version (`FORCE=1` rebuilds) |
| `model` | the GGUF, from the Hugging Face cache or downloaded, checksummed |
| `link` | `las` into `~/.local/bin` |

The configuration you pick (a supported model's) is recorded in `$LAS_HOME/default.env` and is what
`las` runs without a name. Another one installs next to it with `CONFIG=bonsai ./install.sh`
and runs with `las serve bonsai`. Everything lands in `~/.local/share/local-agent-suite`
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
