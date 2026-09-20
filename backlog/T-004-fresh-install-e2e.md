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

## Checked so far, on a machine without an NVIDIA GPU

The run itself needs the target machine, but the early checks do not. On a Debian 13 host with
no GPU, no CUDA, no pi config and a cold Hugging Face cache, all three stop with an actionable
message and a non-zero exit:

```text
./install.sh deps    xx nvidia-smi not found - install the NVIDIA driver (under WSL2: on the Windows side)
./install.sh build   xx nvcc not found - run ./install.sh deps
./install.sh pi      xx pi needs Node.js >= 22.19, found v20.19.2
```

So the gates hold on a machine that has none of the context they were written on. `bash -n`
is clean on all eight scripts.

Still open, and needing the real run: the install path itself, the ~14 GB disk figure, and
where Node >= 22.19 comes from on Ubuntu 26.04. The Node question is per release — Debian 13
ships 20.19.2 and has nothing newer in `main`, so there it has to come from outside apt.
