# Development notes

Why the setup looks the way it does. Every non-default choice answers a failure seen on real
hardware, and its reason lives with its measurement in one of these files (split from this one
on 2026-10-03, T-047):

| File | Holds |
| --- | --- |
| [setup.md](setup.md) | build flags, toolchain and CUDA per distro, Secure Boot, Windows, RAM and build memory, preflight, troubleshooting |
| [agent.md](agent.md) | the harness configs (pi, opencode) and the context budget, the agent prompt, vision, the server lifecycle, Unsloth Studio |
| [localagent.md](localagent.md) | the frozen localagent workflow: its shape, why it is not recommended, the measured runs |
| [agent-sessions.md](agent-sessions.md) | every Tron session across all models: the evidence for what each model is good for |
| [bonsai.md](bonsai.md) | Bonsai: model format, VRAM budget, KV cache, reasoning, Swift-Bonsai-2, sampling, vision, Vulkan |
| [qwen36.md](qwen36.md) | Qwen3.6-35B-A3B: why a MoE, the offload/MTP grid, profiles, RX 570, native Linux, the Unsloth tree, vision |
| [qwen38-flash.md](qwen38-flash.md) | Qwen3.8-Flash-Next: every expert in RAM, flags, window, native Linux, decode at depth and its patches, Strata, vision |
| [lfm25.md](lfm25.md) | LFM2.5-24B-A2B: the first new architecture, its tree, settings and window |
| [context-window.md](context-window.md) | windows and KV quality for both models side by side |
| [performance.md](performance.md) | Bonsai's bandwidth roofline, the optimizations tried and rejected; Qwen3.8-Flash's CPU experts |
| `bench.md` | private fork only: bench results by question, with run ids, the campaign's tier tables |
| `../bench/README.md` | private fork only: the agent bench: task kinds and layout, generated tasks, attempts and verdicts, configurations and the fit check, runs, budgets, result reuse |

## New architectures

A model no shipped tree runs gets its own `models/NAME.env` (the tree: `LLAMA_REPO`, `LLAMA_COMMIT`,
`LLAMA_DIR`, `PATCH_DIR`, mainline by default), a configuration in `configs/`, and no installer
entry: `MODEL_SUPPORT` defaults to `unsupported`, so `install.sh` and preflight leave it out, and
`las list` marks it. The procedure is the private fork's `bench-add-model` skill.

**The chat template.** The GGUF's own template is the default. `las check CONFIG` sends a request
with one tool and checks for a well-formed `tool_calls` entry, then sends the result back and checks
that a final answer comes; it exits 1 naming the step (request, tool_calls, arguments, result,
answer). When it fails on `tool_calls` or `arguments` and the template is the cause, a corrected
template goes in `templates/` and the model file names it with `CHAT_TEMPLATE=templates/FILE.jinja`.
`server-flags.sh` passes it as `--chat-template-file`, and its bytes are part of the bench's fit and
setup keys, so a changed template measures again. The model file's comment says why the template is
there.

Support is earned by a bench run: a model measured with results in `bench.md` can be set
to `supported`, which puts it in the installer's RAM list.

## Old anchors

Links into this file from before the split, and where each section went. `qwen.md` became
[qwen36.md](qwen36.md) and [qwen38-flash.md](qwen38-flash.md), its agent sessions moved to
[agent-sessions.md](agent-sessions.md).

| Old anchor | Now |
| --- | --- |
| `#a-server-on-another-machine` | [agent.md#a-server-on-another-machine](agent.md#a-server-on-another-machine) |
| `#build` | [setup.md#build](setup.md#build) |
| `#context-budget` | [agent.md#context-budget](agent.md#context-budget) |
| `#cuda-from-nvidias-repository` | [setup.md#cuda-from-nvidias-repository](setup.md#cuda-from-nvidias-repository) |
| `#kv-cache` | [bonsai.md#kv-cache](bonsai.md#kv-cache) |
| `#localagent-workflow` | [agent.md#localagent-workflow](agent.md#localagent-workflow) |
| `#model-format` | [bonsai.md#model-format](bonsai.md#model-format) |
| `#other-gpu-backends` | [bonsai.md#other-gpu-backends](bonsai.md#other-gpu-backends) |
| `#pi` | [agent.md#pi](agent.md#pi) |
| `#preflight` | [setup.md#preflight](setup.md#preflight) |
| `#ram-and-build-memory` | [setup.md#ram-and-build-memory](setup.md#ram-and-build-memory) |
| `#reasoning` | [bonsai.md#reasoning](bonsai.md#reasoning) |
| `#sampling` | [bonsai.md#sampling](bonsai.md#sampling) |
| `#secure-boot` | [setup.md#secure-boot](setup.md#secure-boot) |
| `#server-lifecycle` | [agent.md#server-lifecycle](agent.md#server-lifecycle) |
| `#swift-bonsai-2` | [bonsai.md#swift-bonsai-2](bonsai.md#swift-bonsai-2) |
| `#the-agent-prompt` | [agent.md#the-agent-prompt](agent.md#the-agent-prompt) |
| `#thinking-in-the-prompt` | [bonsai.md#thinking-in-the-prompt](bonsai.md#thinking-in-the-prompt) |
| `#toolchain` | [setup.md#toolchain](setup.md#toolchain) |
| `#troubleshooting` | [setup.md#troubleshooting](setup.md#troubleshooting) |
| `#unsloth-studio` | [agent.md#unsloth-studio](agent.md#unsloth-studio) |
| `#vram-budget` | [bonsai.md#vram-budget](bonsai.md#vram-budget) |
| `#windows` | [setup.md#windows](setup.md#windows) |
