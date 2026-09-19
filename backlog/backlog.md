# Backlog — bonsai-local

Ticket index · template: `~/.agents/skills/plan/templates/TICKET_TEMPLATE.md`

**Next ticket: `T-014`**

## Draft

## Backlog

- [`T-002`](T-002-verify-64k-context.md) Settle whether 64k context fits — measure 64k context on 8 GB or drop the claim from the docs · decision · medium · S
- [`T-004`](T-004-fresh-install-e2e.md) Verify a fresh install end to end — run the README from a clean WSL2 Ubuntu 26.04 instance to a working pi session · chore · high · S
- [`T-005`](T-005-other-distros.md) Settle which Linux systems `deps` supports — test Ubuntu 24.04 and 22.04, then support or reject them early · decision · medium · M
- [`T-006`](T-006-native-linux-driver.md) Verify apt's CUDA toolkit next to a native NVIDIA driver — check for a driver/library version mismatch · chore · medium · S
- [`T-007`](T-007-blackwell.md) Verify the build on an RTX 50xx — Blackwell with CUDA >= 12.8 from NVIDIA · chore · low · S
- [`T-008`](T-008-vram-scaling.md) Measure context per VRAM size and with a shared display — derive CTX and the pi budget from free VRAM · decision · medium · M
- [`T-009`](T-009-ram-and-build-memory.md) Measure system RAM needs — build and serve · chore · low · S
- [`T-010`](T-010-other-gpu-backends.md) Try the fork's non-CUDA backends — Vulkan/ROCm at usable speed? · spike · low · M
- [`T-012`](T-012-budget-vs-output-clamp.md) Fit the thinking budget under pi's output clamp — near the trigger pi allows 7 904 tokens, BUDGET is 8 192 · fix · high · S
- [`T-013`](T-013-localagent-first-run.md) Run the localagent workflow on Bonsai — one small feature through `bonsai-pi --localagent`, where does a 27B model break the pipeline · spike · medium · M
