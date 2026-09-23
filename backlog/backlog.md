# Backlog — bonsai-local

Ticket index. A ticket is a file: summary, category, importance, effort, what depends on it,
then **Why** and **What**. Copy the shape of any open one.

Numbers have gaps: a closed ticket's file is deleted, and a ticket that is nobody else's business
is named `T-NNN-{slug}.local.md`, which `.gitignore` keeps out of the repo. The counter below never
reuses a number either way.

**Next ticket: `T-034`**

## Draft

## Backlog

- [`T-004`](T-004-fresh-install-e2e.md) Verify a fresh install end to end — run the README from a clean WSL2 Ubuntu 26.04 instance to a working pi session · chore · high · S
- [`T-005`](T-005-other-distros.md) Settle which Linux systems `deps` supports — test Ubuntu 24.04, 22.04 and Debian 13, then support or reject them early · decision · medium · M
- [`T-006`](T-006-native-linux-driver.md) Verify apt's CUDA toolkit next to a native NVIDIA driver — check for a driver/library version mismatch · chore · medium · S
- [`T-007`](T-007-blackwell.md) Verify the build on an RTX 50xx — Blackwell with CUDA >= 12.8 from NVIDIA · chore · low · S
- [`T-008`](T-008-vram-scaling.md) Measure context per VRAM size and with a shared display — derive CTX and the pi budget from free VRAM · decision · medium · M
- [`T-013`](T-013-localagent-first-run.md) Run the localagent workflow on Bonsai — one small feature through `bonsai-pi --localagent`, where does a 27B model break the pipeline · spike · medium · M
- [`T-015`](T-015-context-safety-tokens.md) Decide whether to shrink pi's 4096-token safety margin — patch, upstream or leave · decision · low · S
- [`T-017`](T-017-upstream-ptq1_0-vulkan-patch.md) Hand the PTQ1_0 Vulkan decode to the fork’s #185 — a comment with the measurement and the patch link, not a PR (two PRs were ahead, and the fork’s rules need an author who can defend every line); drop `patches/vulkan/` once a pin carries an equivalent · chore · medium · S
- [`T-019`](T-019-workflow-cost.md) **Frozen** until a stronger local model: the localagent workflow finishes the todo CLI at the cost of working alone, and fails Tron on the model's capabilities. Report in the ticket · spike · medium · M
- [`T-033`](T-033-kv-cache-q8-q8.md) Measure the KV cache at q8_0/q8_0 against q8_0/q4_0 — KL divergence against f16, speed at ~40k, the window it leaves on 8 GB · spike · medium · S
- [`T-031`](T-031-sharp-chat-template.md) Measure the Qwen Sharp chat template — one plain session with `--chat-template-file`, thinking per turn and turns to result; expectation small, the delta is one terseness block · spike · low · S
- [`T-032`](T-032-docker-server-image.md) A Dockerfile for the server, not for pi — `llama-server` in a container, pi stays on the host through `SERVER_HOST`; answers the apt-toolchain problem (T-005) and nothing about drivers, VRAM or the profile · feature · medium · M

## Open source (release checklist)

Closed on 2026-09-21: the history audit (clean, no rewrite needed), the MIT license and
disclaimer, acknowledgements, the experimental label on the localagent workflow, and the terminal
UX with `scripts/preflight.sh`.

Public since 2026-09-21 at <https://github.com/voxlo-dev/bonsai-agent-8gb>, tagged `v0.1.0`.
Remaining order: T-027 → T-017 comment posted. T-020 and T-029 follow the reports and the upstream merge.

- [`T-020`](T-020-supported-hardware.md) Finish the hardware table — 12/16 GB profiles and the rows that hardware reports bring in; the three tiers are already in the README · decision · medium · M
- [`T-024`](T-024-public-repo-setup.md) Public repo setup — done except confirming the two issue templates render · chore · low · S
- [`T-027`](T-027-quality-evidence.md) Put the quality claim on the record — one Bonsai run through OpenCode with the study's prompt, twice, so it joins the comparison table · spike · high · M
- [`T-029`](T-029-upstream-watch.md) Watch mainline — move off the fork when ggml-org takes PTQ1_0 (#29077), keep the Vulkan patch alive · decision · medium · M
