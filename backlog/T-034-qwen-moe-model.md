# T-034 — A second model: Qwen3.6-35B-A3B with the experts in RAM, as the slot Qwen 4 drops into

- **Summary:** `MODEL=qwen36-35b` serves Qwen3.6-35B-A3B (MoE, 3B active) with its experts in system RAM, a 131k window and MTP drafting on mainline llama.cpp, next to Bonsai as the default. Measured and built; what is left is one agent session, the `display` profile checked once, and the decision whether it ships as supported. Qwen 4 35B-A3B, if it ships, becomes a model file and one re-run
- **Category:** feature
- **Importance:** medium
- **Effort:** S left (phase 3 and 4)
- **Depends on:** the 4060 Ti machine with >= 28 GB RAM in WSL2. Phase 3 runs on the same day as T-035's, which holds the plan for both

## Done

- **Phase 1, speed, window, offload, fork or mainline, and 1b, the KV types**, measured on
  2026-09-24 to 26. The results are in [`docs/qwen.md`](../docs/qwen.md) and
  [`docs/context-window.md`](../docs/context-window.md). The outcome: mainline `8212c78` with MTP,
  131 072 at `q8_0`/`q8_0`, `CPU_MOE` 38, `UB` 2048, ~24 GB RAM resident.
- **Phase 2, the config split**, on this branch, one commit per change:
  - a `MODEL` axis in `config.env`, `models/{bonsai,qwen36-35b}.env`, `profiles/{model}/`;
  - `bonsai-server` builds its flags from them. Bonsai's command line is byte-identical in four
    variants (default, `display`, `vulkan`, overrides), checked against the previous version with
    a stub `llama-server`;
  - `build.sh` takes the model's tree and `PATCH_DIR`, and builds it into its own `LLAMA_DIR`;
  - `preflight` checks disk, RAM (`MemTotal` with a `.wslconfig` hint) and backend from the model
    file;
  - pi gets a config dir per model;
  - `bonsai-pi` names the model a foreign server on `PORT` serves.

  Differences from the plan: the patches stay at `patches/$BACKEND`, and Bonsai's model file names
  them in `PATCH_DIR`, instead of a move to `patches/prism/`. There is no `OFFLOAD` variable:
  `CPU_MOE` and `UB` are passed when set. Sampling stays shared (Bonsai's 1.0/0.95/20/0), which is
  also what Qwen used for its own agent benchmarks.

## Before phase 3, on the 4060 Ti

1. `git pull` on this branch, then `MODEL=qwen36-35b ./install.sh`. `build` compiles mainline into
   `$BONSAI_HOME/llama.cpp-mainline` (10-30 minutes). `model` finds the GGUF in the Hugging Face
   cache if it came from there. The phase 1 link under the name `Qwen3.6-35B-A3B-MTP-UD-Q4_K_M.gguf`
   does not match `MODEL_FILE`, so re-link it first or `model` downloads 22 GB:
   `ln -s "$(readlink -f ~/.local/share/bonsai-local/models/Qwen3.6-35B-A3B-MTP-UD-Q4_K_M.gguf)" ~/.local/share/bonsai-local/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`
2. Run `./install.sh` for Bonsai too, and check that it says "already built" and does not rebuild.
   Then compare `bonsai-server`'s `/props` with a copy taken before the pull: this is the
   on-hardware half of the identity check above.
3. `MODEL=qwen36-35b bonsai-server` once, and check `/props`: `n_ctx` 131072, and the log shows the
   MTP draft context and `--n-cpu-moe 38`. `nvidia-smi` should read ~7 374 MiB.

## Phase 3 — one agent session

Session B of the behaviour day in [T-035](T-035-bonsai-measured.md#phase-3--the-behaviour-day-4060-ti-one-day-mostly-unattended),
which holds the prompt, the order, the evaluation script and the decision rules for both models.

## Phase 4 — after the session

- **Ships as supported** if its game works. The README's section loses "experimental",
  `docs/qwen.md` gets the session, and its budget moves if the session says so.
- **Stays experimental** if the result is broken again, as in the study. That is then the answer for
  this model, with the window no longer the excuse, and the slot waits for Qwen 4.
- **`display` profile**: one start with a desktop on the card and one 43k prompt, pp and VRAM
  read. It is built by arithmetic only (~6 430 MiB).
- **Qwen 4 35B-A3B**: `models/qwen4-35b.env` with its pin and a mainline commit that knows its
  architecture (mainline has `qwen4exp` already, the fork does not), `profiles/qwen4-35b/` copied
  from this one, then the phase 1 grid, the KV test and one session. See
  [qwen.md](../docs/qwen.md#when-qwen-4-lands).
