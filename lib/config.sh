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
  case "$value" in
  "~") printf '%s' "$HOME" ;;
  "~/"*) printf '%s' "$HOME/${value#\~/}" ;;
  *) printf '%s' "$value" ;;
  esac
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
CLIP_TIME="${OMAPASS_CLIP_TIME:-$(config_number clip-time 45)}"
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

