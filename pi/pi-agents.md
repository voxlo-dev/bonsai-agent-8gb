<!-- bonsai-local: global guidance for pi, installed to $BONSAI_HOME/pi-agent/AGENTS.md by scripts/pi.sh.
     Not this project's AGENTS.md - that one is in the repo root. -->

## Working style

You run on a small context window with a hard thinking budget per turn.

- **Think short, act early.** Do not draft full implementations inside one thinking block.
  Decide the single next action, then call the tool. The code belongs in the tool call, not in the reasoning.
- **One step per turn.** Write one file, or run one command, then look at the result.
  Do not plan three files ahead.
- **Do not restate the plan** before each tool call. A single short line is enough.
- Keep tool arguments minimal: no full-file rewrites when an edit will do.
