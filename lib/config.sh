#!/bin/bash
# shellcheck shell=bash
#
# Configuration for omapass, shared by every script in bin/.
#
# Deliberately not sourced as shell: a config file that can run code is a config
# file that can be turned into a payload. This reads `key = value` and nothing
# else, and unknown keys are reported rather than executed.
#
# Precedence is environment > config file > default, so a one-off run can
# override without editing anything.

# manifest.json is the single source of truth for the version: Omarchy already
# requires it there, so a second copy in a shell variable could only ever drift.
OMAPASS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

omapass_version() {
  local manifest="$OMAPASS_ROOT/manifest.json"
  [[ -r $manifest ]] || { printf 'unknown'; return; }
  local v
  v=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1)
  printf '%s' "${v:-unknown}"
}

CONFIG_FILE="${OMAPASS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omapass/config}"

# --- config -----------------------------------------------------------------
#
# One file is the source of truth, and bash is the only thing that parses it —
# `omapass config` hands the result to the UI as JSON so there is never a second
# parser to disagree with this one.
#
# Deliberately not sourced as shell. A config file that can run code is a config
# file that can be turned into a payload; this reads `key = value` and nothing
# else. Unknown keys are reported, not executed.

declare -A CONFIG=(
  [store]=""
  [clip-time]="45"
  [type-delay]="12"
  [type-focus-delay]="0.2"
  [reveal-timeout]="15"
  [fingerprint]="auto"
  [fingerprint-grace]="120"
  [pulldown-rows]="7"
  [backup-dir]=""
)

config_warn() { echo "omapass: $CONFIG_FILE: $*" >&2; }

expand_tilde() {
  local value="$1"
  # SC2088 warns about a tilde that will not expand — which is the point here.
  # These compare against a literal ~ the user typed; nothing should expand.
  # shellcheck disable=SC2088
  if [[ $value == "~" ]]; then
    printf '%s' "$HOME"
  elif [[ ${value:0:2} == "~/" ]]; then
    printf '%s' "$HOME/${value:2}"
  else
    printf '%s' "$value"
  fi
}

read_config() {
  [[ -r $CONFIG_FILE ]] || return 0

  local line key value lineno=0
  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    line="${line%%#*}"                       # strip comments
    line="${line#"${line%%[![:space:]]*}"}"  # trim leading space
    line="${line%"${line##*[![:space:]]}"}"  # trim trailing space
    [[ -n $line ]] || continue

    if [[ $line != *=* ]]; then
      config_warn "line $lineno: expected 'key = value'"
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    key="${key,,}"
    key="${key//_/-}"                        # accept clip_time as clip-time

    # Strip one layer of matching quotes, so a value with spaces survives.
    if [[ $value == \"*\" && ${#value} -ge 2 ]]; then value="${value:1:${#value}-2}"
    elif [[ $value == \'*\' && ${#value} -ge 2 ]]; then value="${value:1:${#value}-2}"
    fi

    if [[ -z ${CONFIG[$key]+set} ]]; then
      config_warn "line $lineno: unknown setting '$key'"
      continue
    fi
    CONFIG[$key]="$value"
  done <"$CONFIG_FILE"
}

# A number, or the default if the file says something that is not one. A typo in
# a timeout should not take the whole tool down.
config_number() {
  local key="$1" fallback="$2" value="${CONFIG[$1]}"
  if [[ $value =~ ^[0-9]+(\.[0-9]+)?$ ]]; then printf '%s' "$value"
  else
    [[ -z $value ]] || config_warn "$key: '$value' is not a number, using $fallback"
    printf '%s' "$fallback"
  fi
}

read_config

# Environment still wins, so a one-off run can override without editing a file.
STORE="${PASSWORD_STORE_DIR:-$(expand_tilde "${CONFIG[store]}")}"
STORE="${STORE:-$HOME/.password-store}"
# Read by the scripts that source this file, not here.
# shellcheck disable=SC2034
CLIP_TIME="${OMAPASS_CLIP_TIME:-$(config_number clip-time 45)}"
# shellcheck disable=SC2034
TYPE_DELAY="${OMAPASS_TYPE_DELAY:-$(config_number type-delay 12)}"

# pass reads this itself, for the git subcommands and anything we shell out to.
export PASSWORD_STORE_DIR="$STORE"

BACKUP_DIR="${OMAPASS_BACKUP_DIR:-$(expand_tilde "${CONFIG[backup-dir]}")}"
BACKUP_DIR="${BACKUP_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omapass/backups}"

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  # Anything else in C0 produces JSON the reader cannot parse. A control
  # character in a GPG uid should not take the whole status payload down.
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  printf '%s' "$s"
}

