# T-028 — Launch: where to post, in what order, with what claim

- **Summary:** One post in r/LocalLLaMA, one comment in llama.cpp discussion #22019, one link from the PrismML fork issue #185, in that order, after T-017 is open and T-027 has numbers
- **Category:** chore
- **Importance:** medium
- **Effort:** S
- **Depends on:** T-024, T-027, T-017 (PR opened)

## Why

The window is the fork dependency: once ggml-org/llama.cpp#29077 merges and Ollama and LM Studio
load `PTQ1_0`, the build step stops being interesting and what remains is the Vulkan decode, the
budget arithmetic and the harness. The post has to land while "how do I even run this on 8 GB"
is the question people are asking.

## What

1. The claim, in one sentence, taken from T-027's result. Lead with the two numbers and the
   card prices; the RX 570 line is the one people will repeat.
2. r/LocalLLaMA post: numbers, the compatibility table, the one-command install, what is
   experimental, a request for hardware reports. No "first ever".
3. Comment in ggml-org discussion #22019 and PrismML-Eng/llama.cpp#185 linking the repo and
   T-017's PR: a Vulkan number and a patch, not an advert.
4. Watch the first 48 hours of issues; T-020's "measured" table is what they feed.
5. Portfolio: the repo README is the landing page; the PR (T-017) and `docs/dev.md` are what a
   reviewer of a CV actually reads. Keep the README's first screen about results, not setup.
