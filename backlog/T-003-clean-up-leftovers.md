# T-003 — Clean up the pre-repo leftovers outside the repo

- **Summary:** Remove the old llama.cpp builds and revert the Unsloth Studio wrapper
- **Category:** chore
- **Importance:** low
- **Effort:** S
- **Depends on:** T-001

## Why

This setup was assembled by hand before it became a repo. The hand-made artifacts are still
on the machine, outside `BONSAI_HOME`, and they are confusing rather than harmful: a second
llama.cpp tree at `~/prism-llama.cpp` with old builds, and a wrapper that Unsloth Studio
installed over its own `llama-server`.

They are not removed yet because they are the fallback while the repo's own path is still
being verified.

## What

Once T-001 confirms the repo's install works end to end:

- delete `~/prism-llama.cpp`
- revert the Unsloth wrapper in `~/.unsloth/llama.cpp/build/bin/`:
  `mv llama-server.unsloth.bak llama-server`

Leave anything under `~/.local/share/bonsai-local` and the Hugging Face cache alone — the
repo owns the first and links the second.
