#!/usr/bin/env bash
# Installs pi if missing and registers the server as provider "local", made the default model.
# Merges into an existing pi config; re-run after changing CTX, PORT or MAX_TOKENS.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! has pi; then
  has npm || die "pi and npm not found - install Node.js first"
  log "installing pi"
  npm install -g @earendil-works/pi-coding-agent
fi

dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
mkdir -p "$dir"
log "writing pi config in $dir"

DIR="$dir" PORT="$PORT" ALIAS="$MODEL_ALIAS" CTX="$CTX" MAX_TOKENS="$MAX_TOKENS" python3 - <<'EOF'
import json, os
d = os.environ["DIR"]

def load(name):
    try:
        with open(os.path.join(d, name)) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

def save(name, data):
    with open(os.path.join(d, name), "w") as f:
        json.dump(data, f, indent=2)

models = load("models.json")
models.setdefault("providers", {})["local"] = {
    "api": "openai-completions",
    "baseUrl": f"http://127.0.0.1:{os.environ['PORT']}/v1",
    "apiKey": "none",
    "models": [{
        "id": os.environ["ALIAS"],
        "contextWindow": int(os.environ["CTX"]),
        "maxTokens": int(os.environ["MAX_TOKENS"]),
    }],
}
save("models.json", models)

settings = load("settings.json")
settings.update(defaultProvider="local", defaultModel=os.environ["ALIAS"])
save("settings.json", settings)
EOF
