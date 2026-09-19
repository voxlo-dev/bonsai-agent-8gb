#!/usr/bin/env bash
# Runs the install steps in order, or only the ones named: deps build model pi link
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

link() {
  mkdir -p "$HOME/.local/bin"
  for b in bonsai-server bonsai-pi; do ln -sf "$ROOT/bin/$b" "$HOME/.local/bin/$b"; done
  log "linked bonsai-server and bonsai-pi into ~/.local/bin"
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "~/.local/bin is not on PATH"
}

steps=("$@")
((${#steps[@]})) || steps=(deps build model pi link)

for s in "${steps[@]}"; do
  case "$s" in
    deps|build|model|pi) bash "$ROOT/scripts/$s.sh" ;;
    link) link ;;
    *) die "unknown step '$s' (deps build model pi link)" ;;
  esac
done
log "done - start the server with: bonsai-server, then bonsai-pi in another terminal"
