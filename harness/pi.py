# SPDX-License-Identifier: MIT
# The config of the pi coding agent for a configuration, written into a directory pi takes as its
# PI_CODING_AGENT_DIR: models.json (provider "local" at SERVER_URL), settings.json (that provider as
# the default and the compaction budget), AGENTS.md (harness/pi/AGENTS.md with the vision line of
# VISION) and the pi-bg-bash extension from npm, pinned. Used by `las harness pi` and by the bench,
# for the config its container mounts. Installs no pi, touches nothing outside `dir`; files already
# there keep every key this does not set. Settings are config.env's, read from `cfg` (a dict) or, on
# the command line, from the environment: python3 harness/pi.py DIR [--no-bg-bash]
# pi-bg-bash comes from PI_BG_BASH_URL (default: the npm registry), checked against PI_BG_BASH_SHA256,
# and is kept in $LAS_HOME/cache for the next configuration.
import json, os, pathlib, re, shutil, sys, tarfile, tempfile, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
REGISTRY = "https://registry.npmjs.org/pi-bg-bash/-/pi-bg-bash-{version}.tgz"


def _load(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}


def _save(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def write_models(cfg, d):
    models = _load(d / "models.json")
    # With the projector loaded, pi's read tool hands an image file to the model instead of a note
    # that the model cannot see it. See docs/agent.md#vision.
    inputs = ["text", "image"] if cfg["VISION"] == "1" else ["text"]
    models.setdefault("providers", {})["local"] = {
        "api": "openai-completions",
        "baseUrl": cfg["SERVER_URL"] + "/v1",
        "apiKey": "none",
        "models": [{
            "id": cfg["MODEL_ALIAS"],
            "input": inputs,
            "contextWindow": int(cfg["CTX"]),
            "maxTokens": int(cfg["MAX_TOKENS"]),
        }],
    }
    _save(d / "models.json", models)


def write_settings(cfg, d):
    settings = _load(d / "settings.json")
    settings.update(defaultProvider="local", defaultModel=cfg["MODEL_ALIAS"])
    # pi's defaults (reserve 16384, keepRecent 20000) assume a 200k window. At 48k they leave ~8k of
    # working room and the post-compaction context stays above the trigger, so pi compacts on every
    # turn. See docs/agent.md#context-budget.
    settings.setdefault("compaction", {}).update(
        reserveTokens=int(cfg["RESERVE_TOKENS"]),
        keepRecentTokens=int(cfg["KEEP_RECENT_TOKENS"]),
    )
    _save(d / "settings.json", settings)


def write_agents(cfg, d):
    """Of the two vision lines the one for VISION, without its tag: the model knows before it takes
    a screenshot whether it can look at it. See docs/agent.md#vision."""
    out, keep = [], True
    for line in (ROOT / "harness" / "pi" / "AGENTS.md").read_text().splitlines():
        m = re.match(r"- \[vision=([01])\] (.*)", line)
        if m:
            keep = m.group(1) == cfg["VISION"]
            if keep:
                out.append("- " + m.group(2))
        elif line.startswith("  ") and out and not keep:
            continue
        else:
            keep = True
            out.append(line)
    (d / "AGENTS.md").write_text("\n".join(out) + "\n")


def _bg_bash_package(cfg, tmp):
    """The pinned pi-bg-bash tarball, checked against PI_BG_BASH_SHA256: from $LAS_HOME/cache once one
    configuration fetched it, so a new configuration needs no network (the npm registry can hang on
    IPv6); without LAS_HOME downloaded into `tmp`."""
    import hashlib
    version, sha = cfg["PI_BG_BASH_VERSION"], cfg["PI_BG_BASH_SHA256"]
    home = cfg.get("LAS_HOME")
    pkg = pathlib.Path(home) / "cache" / f"pi-bg-bash-{version}.tgz" if home else pathlib.Path(tmp) / "pkg.tgz"
    if pkg.is_file() and hashlib.sha256(pkg.read_bytes()).hexdigest() == sha:
        return pkg
    url = cfg.get("PI_BG_BASH_URL") or REGISTRY.format(version=version)
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
    except (OSError, ValueError) as e:
        sys.exit(f"xx could not download {url} ({e}) - or put the package at {pkg}")
    if hashlib.sha256(data).hexdigest() != sha:
        sys.exit(f"xx pi-bg-bash {version} does not match PI_BG_BASH_SHA256 - check the pin in config.env")
    pkg.parent.mkdir(parents=True, exist_ok=True)
    pkg.write_bytes(data)
    return pkg


def write_bg_bash(cfg, d):
    """pi-bg-bash into extensions/, replaced whole; its sources sit flat there, since pi discovers a
    subdirectory by its index.ts. Skipped when the pinned version is already in place."""
    ext, version = d / "extensions" / "pi-bg-bash", cfg["PI_BG_BASH_VERSION"]
    try:
        if (ext / "VERSION").read_text().strip() == version:
            return
    except FileNotFoundError:
        pass
    with tempfile.TemporaryDirectory() as tmp:
        pkg = _bg_bash_package(cfg, tmp)
        with tarfile.open(pkg) as t:
            t.extractall(tmp, filter="data")
        shutil.rmtree(ext, ignore_errors=True)
        ext.mkdir(parents=True)
        src = pathlib.Path(tmp) / "package"
        for f in [*src.glob("src/*.ts"), src / "LICENSE"]:
            shutil.copy2(f, ext)
    (ext / "VERSION").write_text(version + "\n")


def write(cfg, dir, bg_bash=True):
    """pi's config for `cfg` into `dir`, which is created. Returns the directory."""
    d = pathlib.Path(dir)
    d.mkdir(parents=True, exist_ok=True)
    write_models(cfg, d)
    write_settings(cfg, d)
    write_agents(cfg, d)
    if bg_bash:
        write_bg_bash(cfg, d)
    return d


if __name__ == "__main__":
    args = sys.argv[1:]
    bg = "--no-bg-bash" not in args
    args = [a for a in args if a != "--no-bg-bash"]
    if len(args) != 1:
        sys.exit("usage: pi.py DIR [--no-bg-bash]")
    print(write(os.environ, args[0], bg_bash=bg))
