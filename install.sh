#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs the install steps in order, or only the ones named: deps build model link
# Without CONFIG, asks once which supported model's configuration to install, from the RAM next to
# the card, and writes the answer to $LAS_HOME/default.env, which config.env reads; not on a
# terminal it takes the recommendation. scripts/preflight.sh runs next and stops before any step
# spends time; SKIP_PREFLIGHT=1 skips it.
had_config="${CONFIG:-}"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

link() {
  mkdir -p "$HOME/.local/bin"
  local b
  # The links of the commands `las` replaced, only where they still point into this clone.
  for b in qwen-server qwen-studio kolibri-server kolibri-pi kolibri-studio kolibri; do
    if [[ -L "$HOME/.local/bin/$b" && "$(readlink "$HOME/.local/bin/$b")" == "$ROOT/bin/"* ]]; then
      rm "$HOME/.local/bin/$b"
    fi
  done
  ln -sf "$ROOT/bin/las" "$HOME/.local/bin/las"
  log "linked las into ~/.local/bin"
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "~/.local/bin is not on PATH"
}

# The configuration: CONFIG from the environment, else the one default.env records, else asked
# here. Only a supported model is offered, under its default configuration (the one of its name).
# The first answer, or the first CONFIG installed, becomes what `las` runs without CONFIG;
# installing a second one later leaves it. Changing it: edit default.env, or delete it and run
# ./install.sh again. See README.md#which-model.
choose_config() {
  local total rec answer m n; total="$(mem_total_mb)"; rec="$(recommended_model "${total:-0}")"
  [[ -n "$rec" ]] || rec="$CONFIG_DEFAULT"
  # The list and the question go to the terminal; only the answer is the function's output.
  { log "which model? Chosen by the RAM next to the 8 GB card: ${total:+$((total / 1024)) GB here}"
    print_ramp "${total:-0}"; } >&2
  read -r -p "   model (number or name) [$rec]: " answer </dev/tty || answer=""
  answer="${answer:-$rec}"
  n=0
  for m in $(ramp_models); do n=$((n + 1)); [[ "$answer" == "$n" ]] && answer="$m"; done
  [[ -f "$ROOT/configs/$answer.env" ]] || die "no configuration '$answer' - one of: $(ramp_models | tr '\n' ' ')"
  echo "$answer"
}
steps=("$@")
((${#steps[@]})) || steps=(deps build model link)
for s in "${steps[@]}"; do
  case "$s" in deps|build|model|link) ;; *) die "unknown step '$s' (deps build model link)" ;; esac
done

# What `las` runs without CONFIG is recorded once, after preflight passed, so a configuration this
# machine cannot hold never sticks: the CONFIG from the environment (the first one installed), else
# the answer here, else without a terminal the recommendation for this RAM.
default_file="$LAS_HOME/default.env"
record=""
if [[ ! -f "$default_file" ]]; then
  if [[ -n "$had_config" ]]; then record="$CONFIG"
  elif [[ -t 0 && -t 1 ]]; then record="$(choose_config)"
  else record="$(recommended_model "$(mem_total_mb)")"; record="${record:-$CONFIG}"
  fi
  # config.env has already resolved everything for the default; another configuration starts over,
  # with it in the environment, which records it after preflight like any CONFIG.
  [[ "$record" == "$CONFIG" ]] || CONFIG="$record" exec bash "$ROOT/install.sh" "$@"
fi
record_config() {
  [[ -n "$record" ]] || return 0
  mkdir -p "$LAS_HOME"
  printf '# Written by install.sh: the configuration `las` runs when CONFIG is not set.\nCONFIG=%s\n' \
    "$record" > "$default_file"
  log "default configuration: $record, recorded in $default_file (edit it to change)"
}

# Names the step that failed instead of leaving the last command's message alone on the screen.
current=""
on_err() {
  local code=$?
  case "$current" in
    "") ;;
    preflight) ;;  # preflight has already said what is wrong and how to go ahead anyway
    *) printf '\033[1;31mxx\033[0m step '\''%s'\'' failed (exit %d). Re-run just that step with: ./install.sh %s\n' \
         "$current" "$code" "$current" >&2 ;;
  esac
  exit "$code"
}
trap on_err ERR

[[ -n "${SKIP_PREFLIGHT:-}" ]] || { current=preflight; bash "$ROOT/scripts/preflight.sh" "${steps[@]}"; echo; }
record_config

for s in "${steps[@]}"; do
  current="$s"
  case "$s" in
    deps)  log "step deps: apt toolchain for $BACKEND (asks for sudo)" ;;
    build) log "step build: compiling llama-server, typically 10-30 minutes" ;;
    model) log "step model: ~$((MODEL_DISK_MB / 1024)).$((MODEL_DISK_MB % 1024 * 10 / 1024)) GB, from the Hugging Face cache if it is there" ;;
    link)  log "step link" ;;
  esac
  case "$s" in
    deps|build|model) bash "$ROOT/scripts/$s.sh" ;;
    link) link ;;
  esac
done
current=""
log "done - start the server with: las serve (configuration $CONFIG)"
