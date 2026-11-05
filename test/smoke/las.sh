#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Smoke test of the launcher and the configurations behind it, in the Claude sandbox (no GPU, no
# server started): `las list` names every configs/*.env; `las serve --print` shows the engine
# command of each engine with the configuration's window - llama-server, Strata on a prepared run
# config, Unsloth Studio - and starts nothing; the settings precedence holds (environment over
# configuration over model file over defaults, and the recorded default configuration over the
# built-in one); an unknown configuration is refused. Writes only to a temp dir.
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

# The recorded default configuration is what `las` runs without a name; a name wins over it.
mkdir -p "$LAS_HOME"
printf 'CONFIG=qwen36-35b-display\n' > "$LAS_HOME/default.env"
[[ "$("$las" serve --print)" == *" -c $(setting qwen36-35b-display CTX) "* ]] || fail "default.env was not used"
[[ "$("$las" serve --print qwen36-35b)" == *" -c $ctx "* ]] || fail "a named configuration did not win over default.env"

"$las" serve --print no-such-config >/dev/null 2>&1 && fail "an unknown configuration was accepted"
"$las" bogus >/dev/null 2>&1 && fail "an unknown command was accepted"

log "las smoke: ok"
