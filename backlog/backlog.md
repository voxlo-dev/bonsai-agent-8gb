# Backlog — bonsai-local

Ticket index · template: `~/.agents/skills/plan/templates/TICKET_TEMPLATE.md`

**Next ticket: `T-030`**

## Draft

## Backlog

- [`T-004`](T-004-fresh-install-e2e.md) Verify a fresh install end to end — run the README from a clean WSL2 Ubuntu 26.04 instance to a working pi session · chore · high · S
- [`T-005`](T-005-other-distros.md) Settle which Linux systems `deps` supports — test Ubuntu 24.04, 22.04 and Debian 13, then support or reject them early · decision · medium · M
- [`T-006`](T-006-native-linux-driver.md) Verify apt's CUDA toolkit next to a native NVIDIA driver — check for a driver/library version mismatch · chore · medium · S
- [`T-007`](T-007-blackwell.md) Verify the build on an RTX 50xx — Blackwell with CUDA >= 12.8 from NVIDIA · chore · low · S
- [`T-008`](T-008-vram-scaling.md) Measure context per VRAM size and with a shared display — derive CTX and the pi budget from free VRAM · decision · medium · M
- [`T-013`](T-013-localagent-first-run.md) Run the localagent workflow on Bonsai — one small feature through `bonsai-pi --localagent`, where does a 27B model break the pipeline · spike · medium · M
- [`T-015`](T-015-context-safety-tokens.md) Decide whether to shrink pi's 4096-token safety margin — patch, upstream or leave · decision · low · S
- [`T-017`](T-017-upstream-ptq1_0-vulkan-patch.md) Upstream the PTQ1_0 Vulkan decode to the fork — PR against #185 with the T-016 patch, then drop `patches/vulkan/` once the pin carries it · chore · medium · S
- [`T-019`](T-019-workflow-cost.md) Cut what the localagent workflow still costs per unit — implementer self-verification, orchestrator bookkeeping, and a reviewer whose findings path has never run · spike · medium · M

## Open source (release checklist)

Closed on 2026-09-21: the history audit (clean, no rewrite needed), the MIT license and
disclaimer, acknowledgements, the experimental label on the localagent workflow, and the terminal
UX with `scripts/preflight.sh`.

Remaining order: T-027 → T-017 opened → T-024 → T-028. T-020 and T-029 follow the reports and the
upstream merge.

- [`T-020`](T-020-supported-hardware.md) Finish the hardware table — 12/16 GB profiles and the rows that hardware reports bring in; the three tiers are already in the README · decision · medium · M
- [`T-024`](T-024-public-repo-setup.md) Public repo setup — rename to `bonsai-agent-8gb`, visibility, topics, `v0.1.0`; the files are in the tree · chore · high · S
- [`T-027`](T-027-quality-evidence.md) Put the quality claim on the record — one Bonsai run through OpenCode with the study's prompt, twice, so it joins the comparison table · spike · high · M
- [`T-028`](T-028-launch.md) Launch — r/LocalLLaMA, llama.cpp discussion #22019, fork issue #185, after T-017 is open · chore · medium · S
- [`T-029`](T-029-upstream-watch.md) Watch mainline — move off the fork when ggml-org takes PTQ1_0 (#29077), keep the Vulkan patch alive · decision · medium · M
