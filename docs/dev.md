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

## pi

pi reads providers from `~/.pi/agent/models.json` (`PI_CODING_AGENT_DIR` overrides the location). `contextWindow` decides when pi compacts. `maxTokens` is the per-turn output cap, and pi reserves that much of the window for the answer. Unsloth's `unsloth start pi` hard-codes `maxTokens = min(context / 4, 8192)`, which cuts a single long reasoning turn off at 8k. That is why this setup uses its own config.

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
