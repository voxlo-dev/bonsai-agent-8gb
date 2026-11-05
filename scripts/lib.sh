# SPDX-License-Identifier: MIT
# Shared helpers for the install steps and `las`.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config.env"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
# a >= b, for dotted versions
version_ge() { [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

# NVIDIA's own packages put nvcc in /usr/local/cuda/bin, which no shell has on its PATH by default.
if ! has nvcc && [[ -x /usr/local/cuda/bin/nvcc ]]; then PATH="/usr/local/cuda/bin:$PATH"; fi

# The installed nvcc's release (12.9), and the one apt would install (12.0); empty for none. A
# missing command must not fail the pipeline: under pipefail its 127 would end the caller.
nvcc_version() { { nvcc --version 2>/dev/null || true; } | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p'; }
apt_cuda_version() {
  { LC_ALL=C apt-cache policy nvidia-cuda-toolkit 2>/dev/null || true; } \
    | sed -n 's/^ *Candidate: \([0-9]*\.[0-9]*\).*/\1/p'
}

# MODEL_FILE's parts, one per line: itself, or for a split GGUF (-00001-of-0000N.gguf) every part.
model_parts() {
  if [[ "$MODEL_FILE" =~ ^(.*)-00001-of-([0-9]{5})\.gguf$ ]]; then
    local i
    for ((i = 1; i <= 10#${BASH_REMATCH[2]}; i++)); do
      printf '%s-%05d-of-%s.gguf\n' "${BASH_REMATCH[1]}" "$i" "${BASH_REMATCH[2]}"
    done
  else
    printf '%s\n' "$MODEL_FILE"
  fi
}

# --- the ramp: the configurations by RAM, preflight reports them, install.sh asks with them -----
# A value from a file without sourcing it, so all of them can be read next to the one CONFIG
# selected: model_var qwen36-35b MODEL_RAM_MB from models/, config_var from configs/, falling back
# to its model's file.
env_var() { sed -n "s/^$2=//p; s/^: \"\${$2:=\(.*\)}\"$/\1/p" "$1" | tr -d '"'; }
model_var() { env_var "$ROOT/models/$1.env" "$2"; }
config_var() {
  local v; v="$(env_var "$ROOT/configs/$1.env" "$2")"
  [[ -n "$v" ]] || v="$(model_var "$(env_var "$ROOT/configs/$1.env" MODEL)" "$2")"
  echo "$v"
}
mem_total_mb() { awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null; }
# What preflight gates MemTotal on: the RAM a configuration holds while serving plus ~2 GB for the rest.
ram_needed_mb() { local r; r="$(config_var "$1" MODEL_RAM_MB)"; ((r > 0)) && echo $((r + 2000)) || echo 0; }
# RAMP then RAMP_ALSO (config.env), the configurations of a supported model only.
ramp_configs() {
  local c
  for c in $RAMP $RAMP_ALSO; do
    [[ "$(config_var "$c" MODEL_SUPPORT)" == supported ]] && echo "$c"
  done
}
# Runs here: enough RAM in total, and measured on BACKEND.
config_fits() {
  [[ " $(config_var "$1" MODEL_BACKENDS) " == *" $BACKEND "* ]] && (($2 >= $(ram_needed_mb "$1")))
}
# The recommendation for MemTotal $1: the last of RAMP that fits. RAMP_ALSO is a choice, never one.
recommended_config() {
  local c rec=""
  for c in $(ramp_configs); do
    [[ " $RAMP " == *" $c "* ]] && config_fits "$c" "$1" && rec="$c"
  done
  echo "$rec"
}
# Strata is the user's install (README.md#strata): empty when STRATA_VERSION is there, else why not.
strata_missing() {
  local v; v="$("$STRATA_BIN" --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || true)"
  if [[ -z "$v" ]]; then echo "Strata is not installed"
  elif [[ "$v" != "$STRATA_VERSION" ]]; then echo "Strata $v is installed, this needs $STRATA_VERSION"
  fi
}
# One line per configuration for MemTotal $1, numbered: what it holds in RAM, its role, whether it runs here.
print_ramp() {
  local c i=0 ram need full rec note strata; rec="$(recommended_config "$1")" strata="$(strata_missing)"
  for c in $(ramp_configs); do
    i=$((i + 1)) ram="$(config_var "$c" MODEL_RAM_MB)" need="$(ram_needed_mb "$c")"
    full="$(config_var "$c" MODEL_RAM_FULL_MB)"
    if [[ " $(config_var "$c" MODEL_BACKENDS) " != *" $BACKEND "* ]]; then note="not measured on $BACKEND"
    elif (($1 < need)); then note="needs ~$((need / 1024)) GB of RAM in total"
    elif [[ "$(config_var "$c" ENGINE)" == strata && -n "$strata" ]]; then note="needs Strata $STRATA_VERSION, yours to install"
    elif [[ "$c" == "$rec" ]]; then note="runs here - recommended"
    elif ((full > 0 && $1 < full)); then note="runs here, slower: full speed from ~$((full / 1024)) GB free"
    else note="runs here"
    fi
    printf '   %d) %-30s %-32s %4s GB RAM  %-40s %s\n' "$i" "$c" "$(config_var "$c" MODEL_TITLE)" \
      "+$(((ram + 1023) / 1024))" "$(config_var "$c" MODEL_ROLE)" "$note"
  done
}
