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
- OpenSSL is not needed: it only enables HTTPS model downloads inside llama-server, and `bonsai-server` passes a local path.

## VRAM budget

| Item | MiB |
| --- | --- |
| Model weights on GPU | 5,395 |
| Compute buffer | ~250 |
| KV cache, per 1k tokens, `q8_0`/`q8_0` | 34 |
| KV cache, per 1k tokens, `q8_0`/`q4_0` | 26 |

At 48k context with `q8_0`/`q4_0` the process holds ~7.3 GB of 8 GB. 64k should fit at ~7.75 GB but is untested. 80k does not fit.

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
`~/.pi/agent/settings.json`.

| | Value | Constraint |
| --- | --- | --- |
| `RESERVE_TOKENS` | 12000 | >= the largest single turn's output (11 227 measured) |
| `MAX_TOKENS` | 12000 | `CTX - RESERVE + MAX_TOKENS <= CTX`, so exactly 48000 |
| `KEEP_RECENT_TOKENS` | 8000 | real cost ~1.4x, so ~16k in use against a 36 000 trigger |

That leaves ~20k of working room, two to four agent steps per compaction instead of one.

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

`PRESERVE_THINKING=false` passes `--chat-template-kwargs '{"preserve_thinking": false}'`,
which keeps thinking only for messages after the last user message - the current turn.
Note what that does **not** cover: inside one long agent turn there is no later user
message, so that turn's own thinking is all preserved. It pays off across turns, and after
a compaction, since pi feeds the summary back as a `user` message (`dist/core/messages.js`)
which resets `last_query_index`.

## Telling the model to think less

`~/.pi/agent/AGENTS.md`, installed from [`pi/pi-agents.md`](../pi/pi-agents.md), asks the model to
decide one action and call the tool rather than drafting code inside the thinking block.
pi loads it into the system prompt at startup; `--append-system-prompt` and
`--system-prompt` are the per-run equivalents. Treat it as a nudge, not a control: the
measurements under [Reasoning](#reasoning) show this model ignores instructions about
thinking length, including the template's own effort levels. `BUDGET` remains the only
thing that reliably stops it.

## pi

pi reads providers from `~/.pi/agent/models.json` (`PI_CODING_AGENT_DIR` overrides the location). `contextWindow` decides when pi compacts, together with the settings under [Context budget](#context-budget) - not `maxTokens`, which is only the per-turn output cap. Unsloth's `unsloth start pi` hard-codes `maxTokens = min(context / 4, 8192)`, which cuts a single long reasoning turn off at 8k. That is why this setup uses its own config.

## Sampling

`--temp 1.0 --top-p 0.95 --top-k 20` follows the model card. Speculative decoding (`--spec-default`) is off: it accepted 3–10 % of drafted tokens on this model.

## Troubleshooting

| Symptom | Cause · fix |
| --- | --- |
| `invalid ggml type 143` | Stock llama.cpp is running. Start through `bonsai-server`. |
| Generation slows sharply as context grows, GPU load low | Mixed K/V cache types on a build without `FA_ALL_QUANTS`: `FORCE=1 ./install.sh build` |
| `offloaded N/65 layers` with N < 65 | `--fit` is active or VRAM is taken. Check `nvidia-smi` and move the display to the iGPU. |
| Slower while a browser is visible | The browser renders on the RTX. Switch it to the iGPU in Windows graphics settings. |
| `sudo: a terminal is required` | Run `./install.sh deps` in a real terminal, not through an agent's shell. |
| `pi -p` hangs in scripts | pi waits on stdin without a TTY: add `< /dev/null`. |
| Answer ends after exactly `MAX_TOKENS` | The output cap was hit. Raise `MAX_TOKENS` or lower `BUDGET`. |
| pi compacts every turn, most of the time goes into summarizing | `RESERVE_TOKENS`/`KEEP_RECENT_TOKENS` are unset or too large for `CTX`: `./install.sh pi`. See [Context budget](#context-budget). |
