# SPDX-License-Identifier: MIT
# The run config Strata serves for a configuration, shared by `las serve` and the bench: the
# STRATA_CONFIG file `strata launch` wrote, with the alias, host and port of the configuration
# and STRATA_OVERRIDES put back over it. `exact` also turns off every default of Strata that changes
# the computation or the answer against llama-server (bench/README.md#strata); `las serve` leaves
# them on, as Strata ships them. The setting names are config.env's, read from `cfg` (a dict) or, on
# the command line, from the environment. Needs the pinned Strata installed (STRATA_BIN).
import json, os, pathlib, subprocess, sys

# The keys and environment `exact` sets: the bench measures what llama-server would compute.
STRATA_EXACT = {"answer_room": False, "tool_call_recovery": False, "repeat_stop_tokens": 0,
                "reasoning_loop_recovery": False, "reasoning_close_retry": False}
STRATA_EXACT_ENV = {"STRATA_ROUTE_TAIL_SKIP": "0", "STRATA_PREFILL_CPU_SHARE": "0"}


class Refused(Exception):
    """A precondition the user has to fix; nothing was written."""


def overrides(cfg):
    """The keys STRATA_OVERRIDES puts back into the run config, {} without it."""
    raw = cfg.get("STRATA_OVERRIDES") or ""
    try:
        over = json.loads(raw) if raw.strip() else {}
    except ValueError as e:
        raise Refused(f"STRATA_OVERRIDES is not JSON ({e}) - see bench/README.md#strata") from e
    if not isinstance(over, dict):
        raise Refused("STRATA_OVERRIDES must be a JSON object - see bench/README.md#strata")
    return over


def prepare(cfg, out_path, exact):
    """Writes the run config for `cfg` to `out_path` and returns it. Refused when the installed
    Strata is not the pinned one or the run config's window is not CTX."""
    try:
        out = subprocess.run([cfg["STRATA_BIN"], "--version"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        raise Refused(f"{cfg['STRATA_BIN']} --version failed ({e}) - install Strata {cfg['STRATA_VERSION']}") from e
    have = out.split()[1] if len(out.split()) > 1 else out.strip()
    if have != cfg["STRATA_VERSION"]:
        raise Refused(f"Strata {have} is installed, the pin is {cfg['STRATA_VERSION']} (STRATA_VERSION):"
                      " move the pin only with a new measurement - see bench/README.md#strata")
    src = pathlib.Path(cfg.get("STRATA_CONFIG") or "")
    if not src.is_file():
        raise Refused(f"no Strata run config at STRATA_CONFIG={str(src)!r} - write one with `strata launch`"
                      " (bench-optimize stage 4)")
    run = json.loads(src.read_text())
    args = run.get("args", [])
    if "--max-context" in args:
        window = int(args[args.index("--max-context") + 1])
        if window != int(cfg["CTX"]):
            raise Refused(f"{src} serves a {window}-token window, the configuration's CTX is {cfg['CTX']}:"
                          " set CTX and its budget values in the configuration to match")
    over = overrides(cfg)
    # Served without a key; one a launch for remote access set is dropped.
    run.pop("api_key", None)
    if exact:
        run |= STRATA_EXACT
    # fit_max_tokens: a harness asks for more than the room left.
    run |= {"aliases": [cfg["MODEL_ALIAS"]], "fit_max_tokens": True,
            "host": cfg.get("LISTEN_HOST") or cfg["SERVER_HOST"], "port": int(cfg["PORT"])}
    run["env"] = run.get("env", {}) | (STRATA_EXACT_ENV if exact else {}) | over.pop("env", {})
    run |= over
    dest = pathlib.Path(out_path)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(run, indent=1) + "\n")
    return dest


if __name__ == "__main__":
    # prepare OUT [--exact]: the configuration comes from the environment, as config.env resolved it.
    argv = sys.argv[1:]
    if not argv or argv[0] != "prepare" or len(argv) not in (2, 3) or (len(argv) == 3 and argv[2] != "--exact"):
        sys.exit("usage: strata_config.py prepare OUT [--exact]")
    try:
        print(prepare(os.environ, argv[1], exact=len(argv) == 3))
    except Refused as e:
        sys.exit(f"xx {e}")
