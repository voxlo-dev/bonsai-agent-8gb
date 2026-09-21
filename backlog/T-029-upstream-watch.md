# T-029 — Watch mainline: move off the fork when ggml-org takes PTQ1_0

- **Summary:** When ggml-org/llama.cpp#29077 (PQ2_0/PTQ1_0 types) merges, re-evaluate the pin: mainline instead of the fork, and what happens to `patches/vulkan/`
- **Category:** decision
- **Importance:** medium
- **Effort:** M
- **Depends on:** T-017 (the Vulkan decode has to land somewhere mainline can take it)

## Why

The repo's reason to build its own llama.cpp is that mainline refuses ggml type 143. That is
being fixed upstream. When it lands, the fork pin becomes a liability: users with a stock
`llama-server`, Ollama or LM Studio will not need `build.sh`, and the README's promise changes
from "makes it run" to "makes it fast and gives it a harness". The Vulkan decode may or may not
be part of the mainline PR; if not, the patch must be rebased onto mainline's shader layout.

## What

1. Subscribe to #29077 and #22019. Record the merge commit here when it happens.
2. Test: mainline at that commit, `PTQ1_0` load, CUDA speed on the 4060 Ti against 36 tok/s,
   `patches/vulkan/` apply, RX 570 speed against 143 ms/token. If the mainline Vulkan path is
   slower than the patched fork, the patch stays and gets a mainline version.
3. Decide `LLAMA_COMMIT`: fork or mainline. Either way `build.sh` must stop applying a patch
   the tree already contains (`git apply --check` before `git am`, or a stamp).
4. README: a "stock llama.cpp / Ollama / LM Studio" paragraph for people who only want the
   server, keeping `bonsai-pi` and the profile as the value that remains.
