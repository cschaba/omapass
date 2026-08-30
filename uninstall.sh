#!/bin/bash

# Removes omapass from Omarchy.
#
# Like install.sh, it changes nothing outside the plugin: the plugin directory
# and omapass's own config and state are its to remove, and the keybinding —
# which lives in a file you own — is printed for you to delete.

set -euo pipefail

PLUGIN_ID="cschaba.omapass"
LEGACY_ID="omapass"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
BINDINGS="$HOME/.config/hypr/bindings.lua"
LEGACY_BINDINGS="$HOME/.config/hypr/bindings.conf"
CONFIG="${OMAPASS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omapass/config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omapass"

PURGE=0
[[ ${1:-} == "--purge" ]] && PURGE=1
if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  cat <<'USAGE'
./uninstall.sh [--purge]

  Removes the plugin and takes it off the bar.
  --purge also removes omapass's own config and state.

  Your password store and GPG key are never touched, and neither is any
  configuration file outside the plugin — the keybinding is printed for you
  to remove.
USAGE
  exit 0
fi

say() { echo "  $*"; }

# 1. unregister, through omarchy's own command
if command -v omarchy >/dev/null 2>&1; then
  for id in "$PLUGIN_ID" "$LEGACY_ID"; do
    omarchy plugin disable "$id" >/dev/null 2>&1 || true
  done
  say "✓ disabled and taken off the bar"
else
  say "! omarchy not found — run:  omarchy plugin disable $PLUGIN_ID"
fi

# 2. the plugin directory, under either id
for dir in "$PLUGINS_DIR/$PLUGIN_ID" "$PLUGINS_DIR/$LEGACY_ID"; do
  if [[ -e $dir || -L $dir ]]; then
    rm -rf "$dir"
    say "✓ removed $dir"
  fi
done

# 3. omapass's own files, only when asked
if (( PURGE )); then
  [[ -e $CONFIG ]] && rm -f "$CONFIG" && say "✓ removed $CONFIG"
  [[ -d $STATE_DIR ]] && rm -rf "$STATE_DIR" && say "✓ removed $STATE_DIR"
  rmdir "$(dirname "$CONFIG")" 2>/dev/null || true
fi

# 4. what is left for you, because it is not ours to edit
echo
for file in "$BINDINGS" "$LEGACY_BINDINGS"; do
  [[ -f $file ]] || continue
  grep -qE "shell toggle ($PLUGIN_ID|$LEGACY_ID)\b" "$file" || continue
  say "The keybinding is still in $file:"
  grep -nE "shell toggle ($PLUGIN_ID|$LEGACY_ID)\b" "$file" | sed 's/^/      /'
  say "Delete that line when convenient — OmaPass will not edit your config."
  echo
done

for backup in "$HOME/.config/omarchy/shell.json.omapass-backup" \
              "$HOME/.config/hypr/bindings.lua.omapass-backup" \
              "$HOME/.config/hypr/bindings.conf.omapass-backup"; do
  [[ -f $backup ]] && say "An older OmaPass left a backup at $backup — safe to delete."
done

say "OmaPass removed."
if (( ! PURGE )) && [[ -e $CONFIG ]]; then
  say "Its config is still at $CONFIG (--purge removes it)."
fi
say "Your password store is untouched at ${PASSWORD_STORE_DIR:-$HOME/.password-store}."
say "It is a plain pass store — the pass command still reads it."
