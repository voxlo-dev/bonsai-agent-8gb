# SPDX-License-Identifier: MIT
# The config of the opencode coding agent for a configuration: opencode.json in a directory, with
# one OpenAI-compatible provider "local" at SERVER_URL, the model under its alias with the window
# (CTX) and the output limit (MAX_TOKENS), reasoning on, and that model as the default. The format
# is opencode's `provider` section (https://opencode.ai/config.json); point opencode at the file
# with OPENCODE_CONFIG. Installs no opencode, touches nothing outside `dir`; keys of an existing
# file that this does not set stay. Settings are config.env's, read from `cfg` (a dict) or, on the
# command line, from the environment: python3 harness/opencode.py DIR
import json, os, pathlib, sys

SCHEMA = "https://opencode.ai/config.json"


def write(cfg, dir):
    """opencode.json for `cfg` into `dir`, which is created. Returns the file."""
    d = pathlib.Path(dir)
    d.mkdir(parents=True, exist_ok=True)
    path = d / "opencode.json"
    try:
        conf = json.loads(path.read_text())
    except FileNotFoundError:
        conf = {}
    alias = cfg["MODEL_ALIAS"]
    conf["$schema"] = SCHEMA
    conf.setdefault("provider", {})["local"] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": "local-agent-suite",
        "options": {"baseURL": cfg["SERVER_URL"] + "/v1"},
        "models": {
            alias: {
                "name": alias,
                "reasoning": True,
                "tool_call": True,
                "limit": {"context": int(cfg["CTX"]), "output": int(cfg["MAX_TOKENS"])},
                "modalities": {"input": ["text", "image"] if cfg["VISION"] == "1" else ["text"],
                               "output": ["text"]},
            },
        },
    }
    conf["model"] = f"local/{alias}"
    path.write_text(json.dumps(conf, indent=2) + "\n")
    return path


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: opencode.py DIR")
    print(write(os.environ, sys.argv[1]))
