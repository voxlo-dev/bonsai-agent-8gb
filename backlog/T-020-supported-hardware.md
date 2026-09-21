# T-020 — Decide which hardware the README promises

- **Summary:** Draw the line between "measured", "should work" and "not supported" for 8 GB cards, and put that table in the README instead of generalising the scripts
- **Category:** decision
- **Importance:** high
- **Effort:** M
- **Depends on:** T-008 (VRAM scaling) for the 12/16 GB profiles; otherwise incoming hardware reports

## Why

Two cards were measured: RTX 4060 Ti (CUDA) and RX 570 (Vulkan, gfx803). The scripts already
generalise further than the docs admit: `build.sh` takes the CUDA arch from `nvidia-smi`, so any
RTX 20xx to 40xx builds; Vulkan builds for any RADV card and Intel Arc. What is unknown is whether
the *profile* holds: `dedicated` is 64k at 7 747 MiB of 8 188, which is 441 MiB of headroom on one
specific driver. A 4060 non-Ti under a different driver, an RX 6600 with a different allocator, or
a 3070 on native Linux may sit on either side of that margin. Promising "all 8 GB cards" in public
buys a stream of issues that are really T-008.

## Done

The three tiers are in `README.md#requirements`, with the rule that a card enters "measured" only
with a logged run, and a link to the hardware-report issue template. The preflight (T-021) prints
GPU, VRAM, driver and free VRAM before building, and warns when a display is on the card.

## What is left

1. Bigger cards: 12 and 16 GB run this fine but waste the window. Decide whether `profiles/` gets a
   `12g`/`16g` entry now (needs T-008's numbers) or the README says "use `dedicated`, raise `CTX`
   yourself, see the budget arithmetic".
3. AMD: RDNA2/3 are expected to beat the RX 570 by a lot but nobody measured; the fork's #185
   reporter has a 9070 XT and a 860M. Ask for numbers through the hardware-report issue template
   (T-024) rather than buying cards.

Out of scope: ROCm/HIP, Intel oneAPI, Apple. Vulkan is the one AMD path, stated as such.
