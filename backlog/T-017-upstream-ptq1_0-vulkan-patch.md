# T-017 — Hand the PTQ1_0 Vulkan decode to the fork's issue #185

- **Summary:** Post the T-016 result and patch link as a comment on PrismML-Eng/llama.cpp#185, and drop `patches/vulkan/` once a pinned commit carries an equivalent decode, from whoever lands it
- **Category:** chore
- **Importance:** medium
- **Effort:** S
- **Depends on:** none (T-016 closed; patch in `patches/vulkan/0001-ptq1_0-table-decode.patch`)

## Why

T-016 rewrote the fork's PTQ1_0 Vulkan decode: 633 → 143 ms/token generation and 36 → 54 tok/s
prompt on an RX 570, bit-exact against the CPU backend. Issue
[#185](https://github.com/PrismML-Eng/llama.cpp/issues/185) is where that belongs.

**Decided 2026-09-21: a comment, not a PR.** Two PRs were already open on 2026-09-18:
[#188](https://github.com/PrismML-Eng/llama.cpp/pull/188) (integer-dot mat-vec kernel, mergeable,
does not run on cards without `VK_KHR_shader_integer_dot_product` such as gfx803) and
[#187](https://github.com/PrismML-Eng/llama.cpp/pull/187) (same table idea in a weaker form, ~1.2x
on the generic path per the BC-250 numbers in #188, bundled into a conflicting +23k-line PR).
The fork's `CONTRIBUTING.md` closes duplicates and requires the author to explain and maintain
every line without AI help; the patch was written with Claude and that bar is not met. A
comment hands the measurement and the patch to the people who can, at no cost.

## What

1. **Done 2026-09-21:** posted as https://github.com/PrismML-Eng/llama.cpp/issues/185#issuecomment-5759986235 (text in `runs/T-016-ptq1_0-vulkan-decode/issue-185-comment.md`,
   under `voxlo-dev`). The patch link points at
   `main` of the public repo, so the file must stay at that path.
2. Watch #185, #187, #188 occasionally. Answer questions with measurements, not code.
   **2026-09-24:** the maintainer answered on #185: #238 (integer-dot mat-vec, in release
   `842b188`) does not reach gfx803, and pointed at #252 (dedicated PTQ1_0 `mul_mat_vec`) for
   cards without integer dot. Tested on the RX 570 (`runs/T-017-pr252-rx570/`, numbers in
   `docs/dev.md#other-gpu-backends`): #252 matches the T-016 generation speed, so only the
   patch's `mul_mm` half (+50 % on prompts) is still unique. The same run showed T-016's
   prompt "before" of 3.8 tok/s was wrong (36). Comment texts for #252 and the correction on
   #185 are in the run folder.
3. When a pinned commit carries a decode that makes the patch unnecessary (from any of the
   three): move `LLAMA_COMMIT`, re-run the CUDA build and the RX 570 measurement
   (`runs/T-016-ptq1_0-vulkan-decode/measure.sh`), delete `patches/vulkan/`, and drop the patch
   mentions from `README.md`, `AGENTS.md` and `docs/dev.md#other-gpu-backends`. If the new
   decode is slower than 143 ms/token on the RX 570, keep the patch and rebase it instead.
   If the pin carries #252 but not a faster `mul_mm` loader, decide whether +50 % on prompts is
   worth keeping a patch for; if yes, cut it down to the `mul_mm` half.

Not in scope: the dedicated PTQ1_0 mat-vec kernel (ceiling ~22 tok/s on the RX 570).
`upstream-pr-body.md` and `upstream-commands.sh` in the run folder are the PR path, kept in
case the decision is revisited.
