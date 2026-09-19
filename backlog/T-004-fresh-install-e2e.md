# T-004 — Verify a fresh install end to end

- **Summary:** Run the README from a clean WSL2 Ubuntu 26.04 instance to a working pi session
- **Category:** chore
- **Importance:** high
- **Effort:** S
- **Depends on:** none

## Why

Every step has only ever run on the machine it was developed on, with a warm Hugging Face
cache, an existing Node.js and a pi config already in place. The README's install path, the
~14 GB disk figure and the new early checks (Node version, apt, CUDA/GPU arch) have never met
a machine without that context.

## What

`wsl --import` a clean Ubuntu 26.04, follow `README.md` literally (clone, `./install.sh`,
`bonsai-server`, `bonsai-pi`), and note every step that needs knowledge the README does not give.
Record peak disk use (`df` before/after) and correct the figure in `README.md` and
`docs/dev.md#toolchain`. Check where Node.js >= 22.19 comes from on that system and document it.
