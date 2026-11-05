#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Smoke test of the launcher and the configurations behind it, in the Claude sandbox (no GPU, no
# server started): `las list` names every configs/*.env; `las serve --print` shows the engine
# command of each engine with the configuration's window - llama-server, Strata on a prepared run
# config, Unsloth Studio - and starts nothing; the settings precedence holds (environment over
# configuration over model file over defaults, and the recorded default configuration over the
# built-in one); `las harness pi|opencode` write their configs with the configuration's window and
# URL; an unknown configuration is refused. Writes only to a temp dir.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
unset CONFIG CONFIG_FILE ENGINE CTX MODEL SERVER_ARGS CHAT_TEMPLATE
export LAS_HOME="$work/home"
las="$ROOT/bin/las"
fail() { die "las smoke: $*"; }

# A setting as config.env resolves it for configuration $1.
setting() { CONFIG="$1" bash -c 'source "$1/config.env"; eval "echo \$$2"' - "$ROOT" "$2"; }

out="$("$las" list)" || fail "list failed"
for f in "$ROOT"/configs/*.env; do
  n="$(basename "$f" .env)"
  grep -q "^$n " <<<"$out" || fail "list does not name $n"
done
grep -Eq '^qwen36-35b +qwen36-35b +llama +[0-9]+k +supported$' <<<"$out" || fail "list row of qwen36-35b is wrong"
grep -Eq '^bonsai +bonsai +llama +[0-9]+k +unsupported$' <<<"$out" || fail "list does not mark bonsai unsupported"

# llama: the window, the server's address and alias, the model under LAS_HOME.
ctx="$(setting qwen36-35b CTX)"
out="$("$las" serve --print qwen36-35b)" || fail "serve --print qwen36-35b failed"
[[ "$out" == *"/llama-server "* && "$out" == *" -c $ctx "* && "$out" == *"-m $LAS_HOME/models/"* ]] \
  || fail "llama command lacks the server, the window $ctx or the model path: $out"
[[ "$out" == *"--alias $(setting qwen36-35b MODEL_ALIAS)"* ]] || fail "llama command lacks the alias"
[[ "$("$las" serve --print qwen36-35b -- --foo bar)" == *" --foo bar" ]] || fail "arguments after -- are not appended"
[[ ! -e "$LAS_HOME/llama.cpp-unsloth" ]] || fail "--print built or fetched something"

# The environment wins over the configuration, a chat template file reaches the flags.
out="$(CTX=4096 "$las" serve --print qwen36-35b)" || fail "serve --print with CTX failed"
[[ "$out" == *" -c 4096 "* ]] || fail "an environment CTX did not win over the configuration"
out="$(CHAT_TEMPLATE=models/qwen36-35b.env "$las" serve --print qwen36-35b)" || fail "serve --print with CHAT_TEMPLATE failed"
[[ "$out" == *"--chat-template-file $ROOT/models/qwen36-35b.env "* ]] || fail "CHAT_TEMPLATE did not become --chat-template-file"
[[ "$("$las" serve --print qwen36-35b)" != *--chat-template-file* ]] || fail "--chat-template-file without CHAT_TEMPLATE"

# The configuration decides over the model file, here MODEL_RAM_MB; MODEL_SUPPORT comes from the model.
[[ "$(setting qwen36-35b-xl MODEL_RAM_MB)" != "$(setting qwen36-35b MODEL_RAM_MB)" ]] \
  || fail "a configuration's MODEL_RAM_MB did not win over its model file"
[[ "$(setting qwen36-35b-xl MODEL_SUPPORT)" == supported ]] || fail "MODEL_SUPPORT is not the model's"

# Studio: the same flags through Unsloth Studio, the window as its own option.
out="$(ENGINE=studio "$las" serve --print qwen36-35b)" || fail "serve --print with ENGINE=studio failed"
[[ "$out" == "LLAMA_SERVER_PATH="*" studio run --model "*" --context-length $ctx "* ]] \
  || fail "studio command is wrong: $out"

# Strata: its run config prepared under LAS_HOME, served with --profile on the configuration's port.
sc=qwen38-flash-gsq-iq3xxs-strata
if [[ -f "$(setting $sc STRATA_CONFIG)" ]] && has "$(setting $sc STRATA_BIN)"; then
  out="$("$las" serve --print $sc)" || fail "serve --print $sc failed"
  run="$LAS_HOME/strata/$sc.json"
  [[ "$out" == "$(setting $sc STRATA_BIN) serve --profile $run --host "* ]] || fail "strata command is wrong: $out"
  python3 -I - "$run" "$(setting $sc CTX)" "$(setting $sc PORT)" <<'PY' || fail "the prepared run config is wrong"
import json, sys
run = json.load(open(sys.argv[1]))
assert run["port"] == int(sys.argv[3]) and run["fit_max_tokens"] is True, run
assert "answer_room" not in run, "las serve left Strata's approximations alone"
args = run["args"]
assert int(args[args.index("--max-context") + 1]) == int(sys.argv[2]), args
PY
else
  warn "las smoke: no Strata or no run config for $sc here, strata skipped"
fi

# Harness configs: pi and opencode get the configuration's provider, window and output limit. The
# pi-bg-bash download is served from a local tarball (file://) under a pin made for it, so the
# download, the checksum and the unpacking run without the network.
mkdir -p "$work/bg/package/src"
echo '// stub' > "$work/bg/package/src/index.ts"; echo MIT > "$work/bg/package/LICENSE"
tar -czf "$work/bg.tgz" -C "$work/bg" package
export PI_BG_BASH_URL="file://$work/bg.tgz" PI_BG_BASH_SHA256="$(sha256sum "$work/bg.tgz" | cut -d' ' -f1)"
sc=qwen36-35b
url="$(setting $sc SERVER_URL)"; alias="$(setting $sc MODEL_ALIAS)"
mkdir -p "$work/pi"; echo '{"theme":"dark","compaction":{"enabled":true}}' > "$work/pi/settings.json"
"$las" harness pi $sc --dir "$work/pi" >/dev/null 2>&1 || fail "harness pi failed"
python3 -I - "$work/pi" "$url" "$alias" "$(setting $sc CTX)" "$(setting $sc MAX_TOKENS)" \
  "$(setting $sc RESERVE_TOKENS)" "$(setting $sc KEEP_RECENT_TOKENS)" "$(setting $sc PI_BG_BASH_VERSION)" <<'PY' || fail "the pi config is wrong"
import json, os, sys
d, url, alias, ctx, maxtok, reserve, keep, bg = sys.argv[1:]
local = json.load(open(f"{d}/models.json"))["providers"]["local"]
assert local["baseUrl"] == url + "/v1" and local["api"] == "openai-completions", local
m = local["models"][0]
assert m["id"] == alias and m["contextWindow"] == int(ctx) and m["maxTokens"] == int(maxtok), m
s = json.load(open(f"{d}/settings.json"))
assert s["defaultProvider"] == "local" and s["defaultModel"] == alias, s
assert s["compaction"] == {"enabled": True, "reserveTokens": int(reserve), "keepRecentTokens": int(keep)}, s
assert s["theme"] == "dark", "a key of the existing settings was dropped"
agents = open(f"{d}/AGENTS.md").read()
assert "[vision=" not in agents and "## Working here" in agents, "AGENTS.md was not rendered"
assert open(f"{d}/extensions/pi-bg-bash/VERSION").read().strip() == bg
assert os.path.isfile(f"{d}/extensions/pi-bg-bash/index.ts")
assert not os.path.exists(f"{d}/extensions/localagent"), "a localagent extension was written"
PY
PI_BG_BASH_SHA256=0000 "$las" harness pi $sc --dir "$work/pi-bad" >/dev/null 2>&1 && fail "a pi-bg-bash with a wrong checksum was accepted"

"$las" harness opencode $sc --dir "$work/oc" >/dev/null 2>&1 || fail "harness opencode failed"
python3 -I - "$work/oc/opencode.json" "$url" "$alias" "$(setting $sc CTX)" "$(setting $sc MAX_TOKENS)" <<'PY' || fail "the opencode config is wrong"
import json, sys
f, url, alias, ctx, maxtok = sys.argv[1:]
c = json.load(open(f))
p = c["provider"]["local"]
assert p["npm"] == "@ai-sdk/openai-compatible" and p["options"]["baseURL"] == url + "/v1", p
m = p["models"][alias]
assert m["limit"] == {"context": int(ctx), "output": int(maxtok)} and m["reasoning"] is True, m
assert c["model"] == f"local/{alias}", c
PY
# Where opencode is installed, it validates the file against its own schema (it exits with
# "Configuration is invalid" otherwise); its data dirs go to the temp dir.
if has opencode; then
  HOME="$work/ochome" XDG_CONFIG_HOME="$work/ochome/c" XDG_DATA_HOME="$work/ochome/d" XDG_CACHE_HOME="$work/ochome/k" \
    OPENCODE_CONFIG="$work/oc/opencode.json" timeout 60 opencode debug config >"$work/oc.out" 2>&1 \
    || fail "opencode rejected the config: $(head -3 "$work/oc.out")"
else
  warn "las smoke: opencode not installed, its schema check skipped"
fi
"$las" harness bogus $sc >/dev/null 2>&1 && fail "an unknown harness was accepted"
"$las" harness pi no-such-config --dir "$work/x" >/dev/null 2>&1 && fail "harness pi accepted an unknown configuration"

# The recorded default configuration is what `las` runs without a name; a name wins over it.
mkdir -p "$LAS_HOME"
printf 'CONFIG=qwen36-35b-display\n' > "$LAS_HOME/default.env"
[[ "$("$las" serve --print)" == *" -c $(setting qwen36-35b-display CTX) "* ]] || fail "default.env was not used"
[[ "$("$las" serve --print qwen36-35b)" == *" -c $ctx "* ]] || fail "a named configuration did not win over default.env"

"$las" serve --print no-such-config >/dev/null 2>&1 && fail "an unknown configuration was accepted"
"$las" bogus >/dev/null 2>&1 && fail "an unknown command was accepted"

log "las smoke: ok"
