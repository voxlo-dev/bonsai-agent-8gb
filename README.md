# bonsai-local

Runs [Ternary-Bonsai-2-27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) fully on an 8 GB NVIDIA GPU under WSL2, serves it with llama.cpp, and wires it into the [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) coding agent.

Stock llama.cpp cannot load this model: its `PTQ1_0` ternary quant needs the [PrismML llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp). This repo builds that fork, fetches the model, starts a tuned server and configures pi.

## Requirements

- Windows 11 with WSL2 (Ubuntu), NVIDIA driver installed on the Windows side (`nvidia-smi` works in WSL)
- NVIDIA GPU with 8 GB VRAM or more; tested on an RTX 4060 Ti 8 GB
- ~7 GB disk for the model, ~2 GB for the build; Node.js for pi
- The GPU should drive no display, see [VRAM budget](docs/dev.md#vram-budget)

## Install

```bash
./install.sh
```

The default runs every step in order. Name one or more steps to run just those:

| Step | Does |
| --- | --- |
| `deps` | apt toolchain: build tools, cmake, gcc-13, CUDA toolkit (asks for sudo, so run it in a real terminal) |
| `build` | clones the fork at the pinned commit and builds `llama-server` (`FORCE=1` rebuilds) |
| `model` | links the GGUF from the Hugging Face cache, or downloads and checksums it |
| `pi` | installs pi if missing, adds provider `local` and makes it the default |
| `link` | puts `bonsai-server` into `~/.local/bin` |

Everything lands in `~/.local/share/bonsai-local` (`BONSAI_HOME`).

## Use

```bash
bonsai-server        # terminal 1, ready at "listening on http://127.0.0.1:8080"; Ctrl+C stops it
pi                   # terminal 2, in your project directory
```

The server is also a plain OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1`, model `bonsai-27b`.

## Configure

All settings live in [`config.env`](config.env). A variable set in the environment wins, and extra arguments go straight to llama-server:

```bash
CTX=64000 bonsai-server
BUDGET=4096 EFFORT=low bonsai-server
bonsai-server --port 9000
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `CTX` | `48000` | context window in tokens |
| `KV_K` / `KV_V` | `q8_0` / `q4_0` | KV cache types for keys and values |
| `EFFORT` | `medium` | chat-template reasoning effort: `low`, `medium`, `xhigh` |
| `BUDGET` | `8192` | thinking tokens per turn, `-1` for unlimited |
| `MAX_TOKENS` | `24000` | pi's output cap per turn |
| `PORT` | `8080` | server port |

After changing `CTX`, `PORT` or `MAX_TOKENS`, run `./install.sh pi` again so pi's `contextWindow` matches the server.

## Performance

RTX 4060 Ti 8 GB, 48k context, K `q8_0` / V `q4_0`:

| Context filled | Prompt processing | Generation |
| --- | --- | --- |
| short | - | 36 tok/s |
| ~18k | 451 tok/s | 31 tok/s |
| ~39k | 399 tok/s | 27 tok/s |

VRAM stays at ~7.3 GB: the KV cache is allocated in full at start.

## More

[docs/dev.md](docs/dev.md) explains every non-default choice, with the measurements behind it, plus troubleshooting.

## Uninstall

```bash
rm -rf ~/.local/share/bonsai-local ~/.local/bin/bonsai-server
```

Then remove the `local` provider from `~/.pi/agent/models.json`.
