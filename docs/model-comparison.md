# Local models as coding agents: the baseline this repo was built against

Eight local models, one real software task, one 8 GB consumer GPU. None of them is Bonsai.

This is a translated and lightly reorganised version of the evaluation from the project thesis
*Evaluation lokaler Open-Source Coding-Agenten* (Natural Language Processing, Technische
Hochschule Mittelhessen, September 2026). It was written one week before Ternary Bonsai 2 27B was
released, so it measures the field as it stood immediately before this repo existed. It is kept
here because it is the only place that states, with data, what "good enough to be an agent on
8 GB" actually cost before.

The raw protocols, the artifacts each model left behind and the paper itself live in the study's
own repository and are not reproduced here.

> **Read this first.** Every cell below is **a single run**. Repeating the series was too
> expensive in wall-clock time. The results are exploratory, not statistically representative
> (n = 1 per cell). Individual outliers are far more likely to be luck than model strength - the
> GPT-OSS single-shot success below is the clearest example. Treat everything as a tendency, not
> a ranking.

## Setup

| | Desktop | Laptop |
| --- | --- | --- |
| GPU | RTX 4060, 8 GB | iGPU only, pure CPU inference |
| CPU / RAM | Ryzen 7 7800X3D, 64 GB DDR5 | Ryzen 5 5500U, ~14 GB |
| OS | WSL2 (Linux, no PowerShell friction) | - |
| Carried | all coding tests, plus reasoning and throughput | reasoning and throughput only |

Coding ran in the **OpenCode harness** - a real agent, tool and execution harness - with no
`claude.md` in the working directory, so no foreign project rules polluted the context. Reasoning
and throughput were measured in the Unsloth sandbox, which is a chat environment: no model
produces meaningful agentic results there, and none of the coding results come from it.

Per-run parameters: GGUF in UD-Q4_K_XL, KV cache `q8_0`, MTP where supported, vision off, 64,000
token context, reasoning effort `low`, offloading auto. Exceptions: Qwen-3.8-27B in IQ4_XS,
GPT-OSS-20B in Q6_K.

**The task**, given verbatim to every model in both modes:

```text
Implement a simple online "Tron" browser game. The two players log in from
different locations with a user name and can host or join a game from a home
screen. Visual style: 8-Bit retro arcade, neon dark theme. You are free to use
any framework. This is a test environment: Work in this directory, do not read
outside code, ignore the parenting git repository.
```

Followed, once the model declared itself finished, by `Test it and get it to work.` In workflow
mode the `localagent-e2e` agent does that step instead.

Two modes were run: **single-shot** (one autonomous task in the harness) and **workflow** (the
seven-agent orchestration that this repo now ships as [the localagent workflow](localagent.md);
only the final iteration of each model counts, since the workflow itself was being improved
between runs).

## Two axes, not pass/fail

A plain "does the game run?" is too harsh. Some runs were aborted by hand; others carried the
whole process through and only produced an imperfect artifact. So: **process** (did the model get
through autonomously?) and **result** (quality of what it left behind).

### Single-shot

| Model | Process | Result | Time |
| --- | --- | --- | --- |
| Qwen-3.8-27B (dense) | complete; kept hunting bugs at the end, aborted there | **near perfect**, very good UI | ~6 h |
| GPT-OSS-20B | complete, self-fixed | works (**probably luck**, see below), ugly UI | ~20 min |
| Qwen3.6-35B-A3B | complete, 3 compactions | builds, broken (canvas does not load) | >60 min |
| Gemma-4-26B-A4B | complete, does not test | runs, no player sync, ugly | ~6 min |
| Devstral-Small-2-24B | complete, tests heavily | broken, local multiplayer only | ~80 min |
| Nemotron-3.5-35B | complete, fixes nothing | boots, broken | ~13 min |
| GLM-4.7-30B | **gives up** after ~60 min | broken | - |
| Ornith-1.5-35B-A3B | **aborted** (endless test loops) | - | - |

### Workflow, final iteration only

| Model | Process | Result |
| --- | --- | --- |
| Qwen3.6-35B-A3B | **full workflow including e2e, self-commit** | game does not start (broken) |
| GLM-4.7-30B | bugfix loops for hours, no escalation, **aborted** | - |
| GPT-OSS-20B | test author fails, restart fails | no frontend |
| Nemotron-3.5-35B | role confusion, **aborted** | - |
| Gemma-4-26B-A4B | tool-call collapse, **aborted** | - |

**No workflow run produced a working artifact.** One model held the process.

## What the code metrics show

Source and test code counted separately per test folder over `*.js/.mjs/.cjs/.ts/.tsx/.jsx/.html/.css`,
excluding `node_modules`, `dist`/`build`/`.next`/`coverage`, `*.d.ts`, `*.map`, lockfiles and
compiled `.js` sitting next to a same-named `.ts`/`.tsx`. Test classification by path and filename
(`test`, `spec`, `probe`, `e2e`, driver and simulation scripts). Raw counts, to be read as orders
of magnitude.

### Single-shot

| Model | Src files | Src LOC | Test files | Test LOC | Test/Src |
| --- | --- | --- | --- | --- | --- |
| Qwen-3.8-27B | 4 | 926 | 1 | 180 | 0.19 |
| GPT-OSS-20B | 4 | 536 | 1 | 147 | 0.27 |
| Qwen3.6-35B-A3B | 4 | 1323 | 1 | 226 | 0.17 |
| Gemma-4-26B-A4B | 9 | 641 | 0 | 0 | 0.00 |
| Nemotron-3.5-35B | 4 | 457 | 1 | 44 | 0.10 |
| GLM-4.7-30B | 8 | 435 | 8 | 175 | 0.40 |
| Devstral-Small-2-24B | 3 | 729 | 4 | 678 | 0.93 |
| Ornith-1.5-35B-A3B | 12 | 1395 | 7 | 166 | 0.12 |

### Workflow, final iteration

| Model | Src files | Src LOC | Test files | Test LOC | Test/Src |
| --- | --- | --- | --- | --- | --- |
| Qwen3.6-35B-A3B | 12 | 1476 | 7 | 694 | 0.47 |
| GLM-4.7-30B | 18 | 864 | 17 | 1568 | 1.81 |
| Nemotron-3.5-35B | 7 | 415 | 1 | 52 | 0.13 |
| GPT-OSS-20B | 5 | 173 | 3 | 120 | 0.69 |
| Gemma-4-26B-A4B | 3 | 66 | 3 | 105 | 1.59 |

- **Test volume does not predict success; here it anti-correlates.** The most test-heavy workflow
  run (GLM, 1568 test LOC, ratio 1.81) was aborted after hours of bugfix loops. The best result of
  the whole series (Qwen-3.8 single-shot) is among the leanest at 180 test LOC across 4 files.
  With a weak model, test boilerplate is a *symptom* of the debugging struggle, not a quality
  signal.
- **Devstral confirms "more bugs in the tests than in the code" quantitatively:** nearly 1:1 test
  to source LOC (678 : 729), and still broken.
- **Gemma barely tests at all** (0 test LOC single-shot), which matches its protocol note:
  verifies the build, does not test.
- **The workflow inflates.** GLM produces 18 source files in workflow mode against 8 single-shot:
  more structure, not more function. Ceremony without yield.

## Findings

**1. The GPT-OSS single-shot success was probably chance.** It is the only "it works!" in the
single-shot column, from a single run, from a model that public benchmarks do not rate as a strong
coding agent, and the same model failed in workflow mode (broken test author, no frontend). It must
not be read as "best model".

**2. Debugging and self-correction is the real discriminator, not writing code.** Almost every
model scaffolds quickly. The break comes at `Test it and get it to work.`:

- Qwen3.6 in workflow mode finds bugs through e2e, the orchestrator fixes them, it commits. The
  process works; only the last meter is missing.
- GLM, Nemotron and Devstral either do not recognise failures or pass them around in a circle and
  change nothing in the end.
- Ornith and Qwen-3.8 lose themselves *in testing*: they write more and more tests instead of
  fixing, for hours.

For a local coding agent, **self-correction is the most important selection criterion** - more
important than initial code quality or reasoning score.

**3. Reasoning score does not predict agent suitability.**

| Model | Puzzles (of 3) | As a coding agent |
| --- | --- | --- |
| GLM-4.7-30B | 3 correct, 37 s | fails (gives up / aborted) |
| Ornith-1.5-35B-A3B | 3 correct, 32 s | unusable (endless loops) |
| Qwen-3.8-27B | 3 correct | best result (but slow) |
| Qwen3.6-35B-A3B | 3 correct | best process |

Reasoning benchmarks measure one closed thinking step. Agentic coding demands long-running state
management, tool use and self-correction across many turns. **Select an agent model with an
end-to-end task that includes a debugging step, not with a reasoning benchmark.**

**4. "MoE means shallow" does not hold.** The obvious hypothesis - few active parameters means
fast but agentically weak - is contradicted: Qwen3.6-35B-A3B (MoE) is the best workflow agent of
the series, while Gemma-4-26B-A4B (also MoE) stays shallow. Active parameter count is not the
discriminator here; training and alignment for agentic behaviour is.

**5. Multi-agent workflows are marginal for local ~30B models, but not hopeless.** No workflow run
produced a working result, yet the spread is wide. The weak models break on role confusion
(Nemotron's chaos, GPT-OSS starting itself as a subagent), unescalated test failures (GLM's
implementer looping) and tool-call collapse (Gemma). The final Qwen3.6 run, by contrast, followed
the process precisely, had tests green immediately, ran e2e and committed. The orchestrator
architecture is still expensive for local models, but workable with the right one.

Remaining friction that is **model-inherent, not setup**: compaction cascades in ~30B models
(Qwen3.6 hit three) caused by the limited effective context window against a large task. The
countermeasure is smaller task units.

## Reasoning and throughput

The logs give generation speed, total tokens and pure reasoning time, from which the actual
reasoning effort can be reconstructed: reasoning tokens ≈ reasoning time × tok/s, and the
reasoning share is reasoning time ÷ generation time.

| Model | Score | tok/s | Reason time | Total tok | Reason tok (≈) | Reason share |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen-3.8-27B (IQ4_XS) | 3/3 | 3.9 | 170 s | 1021 | ~665 | 65 % |
| GLM-4.7-30B | 3/3 | 27.3 | 37 s | 1342 | ~1010 | 75 % |
| Ornith-1.5-35B-A3B | 3/3 | 36.4 | 32 s | 1754 | ~1165 | 66 % |
| Gemma-4-26B-A4B | 3/3 | 42.8 | 57 s | 3146 | ~2440 | 78 % |
| GPT-OSS-20B | 3/3 | 33.0 | 143 s | 5076 | ~4725 | 93 % |
| Qwen3.6-35B-A3B | 3/3 | 25.9 | 192 s | 5452 | ~4980 | 91 % |
| Muse-Glimmer-30B | 3/3 | 4.6 | 484 s | 2777 | ~2220 | 80 % |
| Ornith-1.5-9B | 3/3 * | 24.7 | 317 s | 8558 | ~7845 | 92 % |
| Gemma-4-E4B | 2/3 | 116.0 | 14 s | 2939 | ~1625 | 55 % |
| Gemma-4-12B | 2/3 | 24.2 | 108 s | 3351 | ~2615 | 78 % |
| Nemotron-3.5-35B | 2/3 | 28.6 | 207 s | 6385 | ~5925 | 93 % |
| Qwen-3.5-9B | 2/3 | 26.2 | 296 s | 8823 | ~7765 | 88 % |
| Qwen3.5-2B | 2/3 | 100.3 | 145 s | 15825 | ~14540 | 92 % |
| Devstral-Small-2-24B | 1/3 | 4.1 | - | 548 | no reasoning mode | - |

<sub>* task 3 correct but guessed. The three puzzles were German-language logic problems; the
third one (walk or drive to the car wash) was the consistent stumbling block.</sub>

Reasoning effort does not predict correctness, and overthinking is its own failure mode.
Qwen-3.8-27B solves 3/3 with ~665 reasoning tokens, by far the lowest cognitive cost at full
correctness; GLM (~1010) and Ornith-35B-A3B (~1165) are also efficient. At the other end,
Nemotron thinks ~5900 tokens for 2/3, and Qwen3.5-2B burns ~14,500 tokens and still scores 2/3.
The reasoning share runs 55 to 93 %: most of the output is thinking, not answer, and the highest
shares belong to the models that overthink.

### Throughput on 8 GB VRAM

Generation speed splits sharply by size and architecture:

| Class | tok/s | Why |
| --- | --- | --- |
| MoE models and everything ≤ 12B | 24-116 | fit (largely) into 8 GB VRAM |
| large **dense** models: Qwen-3.8-27B (3.9), Devstral-24B (4.1), Muse-30B (4.6) | ~4-5 | must spill from VRAM into RAM |

**This is the actual reason for Qwen-3.8's six-hour runs** - not verbosity, since its token cost
is the lowest in the table, but the throughput limit of dense 27B weights on an 8 GB card. For an
interactive agent on this hardware, large dense models are effectively disqualified, however good
their output.

**Configuration sensitivity:** GLM ran at 2.7 tok/s with MTP (and answered wrong) and at 25.8
tok/s with KV cache `q8_0` and no MTP - a factor of ~10 from quantisation and cache setup alone.
The optimum found: everything on auto, KV cache `q8_0`.

## The laptop: pure CPU inference

The same puzzles on a Ryzen 5 5500U laptop (iGPU, ~14 GB RAM), no dedicated VRAM. Coding was not
tested here, and the numbers say why.

| Model (quant) | Score | tok/s | Reason time | Total tok | Reason tok (≈) | RAM |
| --- | --- | --- | --- | --- | --- | --- |
| GPT-OSS-20B (Q4_K_S) | 3/3 * | 10.5 | 70 s | 1423 | ~735 | **98 %** |
| Qwen-3.5-9B (IQ4_XS) | 3/3 | 4.1 | 1548 s | 7145 | ~6345 | 72 % |
| Qwen3.5-4B (Q4_K_XL) | 3/3 * | 5.1 | 1124 s | 6735 | ~5730 | 69 % |
| Gemma-4-12B (Q4_K_XL) | 2/3 | 4.1 | 1292 s | 6027 | ~5300 | 86 % |
| Gemma-4-E4B (Q4_K_XL) | 2/3 | 11.8 | 142 s | 2904 | ~1675 | 79 % |
| LFM2.5-8B-A1B (IQ4_XS) | 2/3 | 15.5 | 70 s | 1263 | ~1085 | 70 % |
| Qwen3.5-2B (Q6_K_XL) | aborted | - | ~3000 s | - | - | 52 % |

Throughput loss, CPU against GPU, same model:

| Model | Laptop (CPU) | Desktop (GPU) | Factor |
| --- | --- | --- | --- |
| Gemma-4-E4B | 11.8 | 116.0 | ~10x |
| Gemma-4-12B | 4.1 | 24.2 | ~6x |
| Qwen-3.5-9B | 4.1 | 26.2 | ~6x |
| GPT-OSS-20B | 10.5 | 33.0 | ~3x (different quant) |

CPU inference is 3 to 10 times slower, and the small models lose the most, which erases their size
advantage. Reasoning times explode: 9B and 12B models think 20 to 26 minutes about a *single*
puzzle, so an agent running hundreds of turns is out of the question. RAM is the hard wall -
GPT-OSS-20B fills 98 % of it and is the largest model that still fits, while the ~30B models that
delivered the code on the desktop do not fit at all. Thermal throttling (3.4 to 1.4 GHz) hits
precisely the small compute-bound models that should be fastest; Qwen3.5-2B was aborted after
~3000 s of reasoning despite its size.

Correctness stays largely platform-stable. The one exception, Qwen-3.5-9B at 3/3 here against 2/3
on the desktop, is a different quantisation and n = 1.

**Verdict for the laptop:** usable for local reasoning and chat with small models (≤ 8B for
tolerable latency), unusable for local coding agents. The good coding results of this series hang
on the desktop GPU.

## Recommendations, as the study left them

For a local coding agent on an RTX 4060 8 GB, before Bonsai existed:

1. **Highest result quality: Qwen-3.8-27B (dense).** The only model that delivered near-perfect
   code. Batch or overnight use only, because of the ~6 h runtime. Pick it when correctness beats
   speed.
2. **Best interactive agent and workflow driver: Qwen3.6-35B-A3B.** Fast (MoE), holds the process,
   runs the full pipeline including e2e, commits on its own. The result still needs a human last
   meter, but the agentic base is there.
3. **Fast scaffolding: Gemma-4-26B-A4B.** A skeleton in minutes, then plan for human debugging; it
   does not test itself.

Handle with care: GPT-OSS-20B, whose single-shot success is not robust. Poorly suited to autonomous
coding despite partly excellent reasoning scores: GLM-4.7, Nemotron-3.5, Devstral, Ornith-1.5 -
they lack agentic robustness, meaning self-correction, escalation and reliable tool calls.

On architecture: run a multi-agent workflow only with an agentically strong model; for the rest the
simple single-shot loop is more robust. A clean agent harness is a precondition. Invest in a robust
self-correction loop and in avoiding compaction through smaller task units. With 8 GB of VRAM,
prefer MoE and smaller models, because large dense models are barely usable interactively whatever
their quality; KV cache `q8_0`, MTP off.

On methodology for follow-up work: run **several passes per model** - the GPT-OSS case shows how
misleading n = 1 is - and score along the two axes separately.

## What this means for this repo

The study's central tension is that on 8 GB you could have result quality or interactive speed,
not both. Qwen-3.8-27B dense delivered the quality at 3.9 tok/s and six hours per task.
Qwen3.6-35B-A3B delivered the speed and the process discipline, and a broken game.

Ternary Bonsai 2 27B was published on 17 September 2026, one week after these runs. It is a dense
27B that fits into 8 GB at 5.95 GB, which is the combination the table above has no row for. This
repo exists to make that combination usable and to find out whether it actually closes the gap.

**That question is open.** Nothing in this document was measured with Bonsai. The comparison run -
Bonsai through the same harness, with the same prompt, on the same card class, more than once - is
ticket T-035 (formerly T-027) and has not been done. Until it is, the honest claim is that the repo puts a dense
27B into interactive speed on 8 GB, not that it beats the table.

## Citation

> L. F. Müller, *Evaluation lokaler Open-Source Coding-Agenten*, project thesis, Natural Language
> Processing, Technische Hochschule Mittelhessen, September 2026.

The seven-agent workflow evaluated here is the ancestor of
[the localagent workflow](localagent.md) in this repository; both are the same author's work.
