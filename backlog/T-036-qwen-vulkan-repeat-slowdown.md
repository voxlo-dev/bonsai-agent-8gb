# T-036 — Qwen3.6 on the RX 570: find the repeat slowdown, then give Vulkan its own profile

- **Summary:** On the RX 570, Qwen3.6-35B-A3B runs at 2.5-3.5x Bonsai's speed on a first request, but every further request on the same cache is slower: 20.7 → 16.0 tok/s at 32k, 18.8 → 7.8 at 131k, with buffers moving from VRAM to GTT. An agent session is only repeats. First diagnose it, with cheap isolation runs and an op breakdown, and only then decide whether a profile or kernel work follows
- **Category:** spike
- **Importance:** medium
- **Effort:** S for the diagnosis (~1.5 h on the box), M if a profile follows, open if a kernel does
- **Depends on:** the AMD box with 28 GB (see `CHECKPOINT.local.md`), where the GGUF and the mainline Vulkan build from T-034 are already installed under `~bro/bonsai-home/`. T-034's session decides whether Qwen is worth a supported Vulkan path at all; the diagnosis does not need to wait for it

## Why

The measurement is in [qwen.md](../docs/qwen.md#on-the-rx-570-vulkan). Three observations frame
it:

- **The first request is clean.** At 131k with MTP, a 32 781-token prompt is read at 120 tok/s,
  then generates at 18.8 tok/s. The next request on the same cache, with `prompt_n` 4, generates
  at 7.8. Across the two requests VRAM falls (5 971 → 5 531 MiB) and GTT grows (1 553 → 2 214 MiB).
  At 32k: 20.7 → 16.0, and ~250 MB move the same way after the first request, then it stays put.
- **The card has 256 MiB of CPU-visible VRAM** (`mem_info_vis_vram_total`, no Resizable BAR).
  Anything the host writes into on every request is a candidate for being moved to GTT and read
  across PCIe from then on. Two writers are new since Bonsai. One is mainline's context checkpoints
  for hybrid models, which save and restore the recurrent state around a reused prefix. The other is
  the MTP draft context.
- **Experts on the card do not help** (17.9 → 19.5 tok/s for nine layers, then nothing), so the
  first-request speed is bounded by the GPU-side kernels, not by the experts in RAM.

The Bonsai precedent is 0.94 → 7 tok/s through a missing PTQ1_0 decode (T-016) and 1.22x through
`nogttspill`. Neither repeats here: Qwen is not missing a kernel. Realistic upside: up to 2.4x
over a session at 131k if the repeat drop is a placement problem, and perhaps 1.3-2x on the first
request if one op dominates. That is enough to be worth 1.5 hours of diagnosis, and not enough to
start shader work on a hunch.

## What to run

On the box, `RADV_PERFTEST=nogttspill`, port 8083, one server at a time, **no `pgrep -f` on a
string that is in the waiting command's own line** (it matches itself; T-034 lost an hour to
that). Base config as in T-034: mainline `8212c78`,
`~bro/bonsai-home/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`, `-ngl 99 --fit off --n-cpu-moe 40
-b 2048 -ub 2048 -fa on -ctk q8_0 -ctv q8_0 --parallel 1 --no-context-shift --jinja`. The
repeat test is the one from T-034 (`runs/T-034-qwen-moe-rx570/`): a ~25k-token prompt
(`t034-p25k.txt`), `cache_prompt: true`, `n_predict` 128, three times, VRAM and GTT after each.

**1. Isolate the repeat drop**, at 32k (fast to fill), one variable per run:

| Run | Change against the base | If the drop goes away, the cause is |
| --- | --- | --- |
| a | the base, with `--spec-type draft-mtp` (reproduces 20.7 → 16.0) | – |
| b | without MTP | the draft context |
| c | `--ctx-checkpoints 0` | the hybrid-state checkpoints |
| d | `--cache-ram 0` | the host-side prompt cache |
| e | base at 131k, the winner of b-d applied | confirms it at the size where it costs 2.4x |

Record `tg` per repeat, and VRAM/GTT after each. A run that removes the drop but breaks prefix
reuse (`prompt_n` large on the repeat) trades one problem for another; say so and note the
reprocess time instead.

**2. An op breakdown** of one generation at 32k, first request and repeat, with
`GGML_VK_PERF_LOGGER=1`, the same way T-016 found the PTQ1_0 decode. The question is whether one
op (the candidates are the Gated DeltaNet kernel and `mul_mat_id` on Q4_K without integer dot
products) takes a large share, and whether the repeat changes which op is slow. That second
answer points at placement rather than at a kernel.

## Deciding

- **The drop is a flag or an environment variable**: it goes into the Qwen Vulkan profile, and the
  window can go back to 131k. Then:
  - `config.env` additionally sources `profiles/$MODEL/$PROFILE-$BACKEND.env` when it exists, as
    a small override on top of the profile;
  - `profiles/qwen36-35b/dedicated-vulkan.env` holds `CPU_MOE` 40 and the window;
  - one repeat run confirms it.

  Bonsai needs no such file. Its 64k fits both cards, as measured.
- **The drop is inherent** (the checkpoint mechanism on a card without Resizable BAR): the Vulkan
  profile gets a small window (32k, where the drop is 23 %), and `qwen.md` says why.
- **One op dominates in step 2**: a separate ticket for the kernel, with the op's share as the
  measurement it starts from. Polaris is a niche, and RDNA cards behave differently, so it needs
  that number before anyone writes a shader.
- Either way, the numbers go to `docs/qwen.md#on-the-rx-570-vulkan`, and this file is deleted.

Not in scope: the 4060 Ti (Bonsai is at ~80 % of its bandwidth, Qwen bounded by RAM), Bonsai's 96k
candidate on Vulkan (one check for T-035, not this ticket), and making Qwen the default.
