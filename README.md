# bonsai-local

Runs [Ternary-Bonsai-2-27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) fully on an 8 GB NVIDIA GPU, serves it with llama.cpp, and wires it into the [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) coding agent.

Stock llama.cpp cannot load this model: its `PTQ1_0` ternary quant needs the [PrismML llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp). This repo builds that fork, fetches the model, starts a tuned server and configures pi.

## Requirements

Tested on Windows 11 + WSL2 with Ubuntu 26.04 and an RTX 4060 Ti 8 GB. [Toolchain](docs/dev.md#toolchain) says what is known beyond that.

- Linux, native or WSL2, with a working NVIDIA driver (`nvidia-smi` runs; under WSL2 the driver is installed on the Windows side)
- NVIDIA GPU with 8 GB VRAM, of which ~7.3 GB must be **free**: the GPU should drive no display, see [VRAM budget](docs/dev.md#vram-budget). Less does not work, the model does not run partially offloaded at usable speed
- CUDA toolkit >= 12.4 with a host gcc it accepts; >= 12.8 for RTX 50xx. `./install.sh deps` installs it via apt, which yields 12.4 on Ubuntu 26.04 only
- Node.js >= 22.19 for pi
- ~14 GB free disk: 5.6 GB model, 1.9 GB build, ~5.4 GB for the CUDA toolkit from apt. ~9 GB when a CUDA toolkit is already installed

Without apt, install the toolchain yourself (CUDA, gcc, cmake, git, python3) and skip `deps`: `./install.sh build model pi link`.

## Install

```bash
git clone https://github.com/voxlo-dev/bonsai-local.git   # private: needs GitHub access
cd bonsai-local
./install.sh
```

The default runs every step in order. Name one or more steps to run just those:

| Step | Does |
| --- | --- |
| `deps` | apt toolchain: build tools, cmake, gcc-13, CUDA toolkit (asks for sudo, so run it in a real terminal) |
| `build` | clones the fork at the pinned commit and builds `llama-server` (`FORCE=1` rebuilds) |
| `model` | links the GGUF from the Hugging Face cache, or downloads and checksums it |
| `pi` | installs its own pinned pi and writes its config: provider `local` as default, the context budget, `AGENTS.md`. A pi you already have and `~/.pi` stay untouched |
| `link` | puts `bonsai-server` and `bonsai-pi` into `~/.local/bin` |

Everything lands in `~/.local/share/bonsai-local` (`BONSAI_HOME`), pi's config and sessions in `pi-agent/` there.

## Use

```bash
bonsai-pi            # in your project directory; arguments go to pi
```

`bonsai-pi` starts the server in the background when none is running, waits for the model to load, and stops the server again when the last `bonsai-pi` session ends. Its output goes to `~/.local/share/bonsai-local/server.log`. A server you started yourself is used and left running:

```bash
bonsai-server        # terminal 1, ready at "listening on http://127.0.0.1:8080"; Ctrl+C stops it
bonsai-pi            # terminal 2
```

`bonsai-pi` is a separate pi instance, so a pi you use with other models keeps its own settings. The server is also a plain OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1`, model `bonsai-27b`.

## Configure

All settings live in [`config.env`](config.env). A variable set in the environment wins, and extra arguments go straight to llama-server:

```bash
CTX=64000 bonsai-server
BUDGET=3072 EFFORT=low bonsai-server
bonsai-server --port 9000
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `CTX` | `48000` | context window in tokens |
| `KV_K` / `KV_V` | `q8_0` / `q4_0` | KV cache types for keys and values |
| `EFFORT` | `medium` | chat-template reasoning effort: `low`, `medium`, `xhigh` |
| `BUDGET` | `4096` | thinking tokens per turn; with `RESERVE_TOKENS` 12000 at most ~5k, see [Context budget](docs/dev.md#context-budget) |
| `PRESERVE_THINKING` | `false` | keep earlier turns' thinking in the prompt |
| `MAX_TOKENS` | `12000` | pi's output cap per turn |
| `RESERVE_TOKENS` | `12000` | window pi holds back for the answer; it compacts above `CTX - RESERVE_TOKENS` |
| `KEEP_RECENT_TOKENS` | `8000` | recent history a compaction keeps |
| `PORT` | `8080` | server port |
| `PI_VERSION` | `0.85.1` | pi version the context budget was measured with |
| `SERVER_AUTOSTART` | `true` | let `bonsai-pi` start and stop the server |
| `SERVER_START_TIMEOUT` | `300` | seconds `bonsai-pi` waits for the model to load |

After changing `CTX`, `PORT`, `MAX_TOKENS`, `RESERVE_TOKENS` or `KEEP_RECENT_TOKENS`, run `./install.sh pi` again so pi's config matches the server.

The last three carry each other: pi's own defaults assume a 200k window and make it compact on every single turn at 48k. [Context budget](docs/dev.md#context-budget) has the measurements and the constraints between them.

## Performance

RTX 4060 Ti 8 GB, 48k context, K `q8_0` / V `q4_0`:

| Context filled | Prompt processing | Generation |
| --- | --- | --- |
| short | - | 36 tok/s |
| ~18k | 451 tok/s | 31 tok/s |
| ~39k | 399 tok/s | 27 tok/s |

VRAM stays at ~7.3 GB: the KV cache is allocated in full at start.

## More

[docs/dev.md](docs/dev.md) explains every non-default choice, with the measurements behind it, plus troubleshooting. Contributors and AI agents start at [AGENTS.md](AGENTS.md).

## Uninstall

```bash
rm -rf ~/.local/share/bonsai-local ~/.local/bin/bonsai-server ~/.local/bin/bonsai-pi
```

This includes pi and its sessions. `~/.cache/ccache` holds the build cache, and the apt packages from `deps` stay installed.
