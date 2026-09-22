# T-024 — Public repo setup: visibility, issues, PRs, contributing rules, first release

- **Summary:** The GitHub-side half of going public: rename, visibility, tag, topics. The files are in the tree already
- **Category:** chore
- **Importance:** high
- **Effort:** S
- **Depends on:** T-017 comment posted on #185. License and history audit are closed

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

## Done on 2026-09-21

Renamed to `bonsai-agent-8gb`, description and eight topics set, issues on, wiki, projects and
discussions off, visibility public, local remote updated. Tag `v0.1.0` pushed and released, with
the notes rewritten as markdown because a git tag message is plain text and its column alignment
collapses on the release page.

Two gh 2.46 quirks worth remembering: it has no `--accept-visibility-change-consequences` flag and
prompts instead, and `--notes-from-tag` cannot be combined with `--repo`.

## Still open

- **Nobody has seen the two issue templates render.** A YAML form only parses server-side; the
  files are in the repo but the fields are unverified. Open
  <https://github.com/voxlo-dev/bonsai-agent-8gb/issues/new/choose> once and check both.
- The `runs/` folders are gitignored, so the logs behind the measured numbers are not public. If a
  hardware report or a reviewer asks for one, decide then whether to publish a subset.
