# T-024 — Public repo setup: visibility, issues, PRs, contributing rules, first release

- **Summary:** The GitHub-side half of going public: rename, visibility, tag, topics. The files are in the tree already
- **Category:** chore
- **Importance:** high
- **Effort:** S
- **Depends on:** T-017 opened (not merged). License and history audit are closed

## Why

Publishing is cheap; the decisions that cost later are what you accept. One maintainer, no test
suite, a repo whose product is measured reasons: a PR that changes a flag without a measurement
is worse than no PR. That rule exists in `AGENTS.md` for agents and needs to exist for humans.

## Done, in the tree

`CONTRIBUTING.md` with the measurement rule, the verification table and what will be declined.
`.github/ISSUE_TEMPLATE/` with a bug template (backend, card, driver, distro, step, log) and a
hardware-report template that feeds T-020's measured tier, plus a `config.yml` pointing model
questions at PrismML and mainline `PTQ1_0` support at ggml-org#29077. `README.md` no longer says
the repo is private, carries the tiers, the hardware disclaimer, acknowledgements and the license.

## What is left, all of it manual on github.com

1. **Rename** the repository to `bonsai-agent-8gb` and set the description to "A 27B coding agent
   that runs entirely on an 8 GB consumer GPU". `README.md`'s clone line already uses the new name,
   so it is wrong until the rename happens. GitHub redirects the old URL. Then
   `git remote set-url origin` here and on the copy on the GPU box.
2. **Topics:** `llama-cpp`, `ternary`, `bonsai`, `local-llm`, `coding-agent`, `8gb-vram`, `vulkan`,
   `quantization`.
3. **Visibility public.** Issues on, PRs on, Discussions off for now; questions go to issues and
   the volume decides later. Wiki and Projects off.
4. **Tag `v0.1.0`** on the commit whose `config.env` holds the current pins. Release notes are the
   two measured cards with their numbers and the four pins verbatim. Later tags move with pins and
   with nothing else.
5. Check that the two issue templates render, since nobody can test a `.yml` form locally.
