#!/bin/bash

# Installs omapass into Omarchy: links the plugin, enables it in the shell, and
# adds the keybinding. Safe to re-run.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/omapass"
BINDINGS="$HOME/.config/hypr/bindings.conf"
KEYBIND="${OMAPASS_KEYBIND:-SUPER CTRL, K}"

say() { echo "  $*"; }

# 1. link (or copy, if the source is somewhere transient)
if [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
  say "✓ plugin already installed at $PLUGIN_DIR"
elif [[ -L $PLUGIN_DIR && $(readlink -f "$PLUGIN_DIR") == "$SOURCE_DIR" ]]; then
  say "✓ plugin already linked from $SOURCE_DIR"
else
  ln -sfn "$SOURCE_DIR" "$PLUGIN_DIR"
  say "✓ linked $SOURCE_DIR → $PLUGIN_DIR"
fi

# 2. register with the running shell
if omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  sleep 1
  omarchy-shell shell setPluginEnabled omapass true >/dev/null 2>&1 || true
  say "✓ enabled in omarchy-shell"
else
  say "! omarchy-shell is not running — it will pick omapass up on next start"
fi

# 3. keybinding
if [[ -f $BINDINGS ]] && grep -q "shell toggle omapass" "$BINDINGS"; then
  say "✓ keybinding already present in $BINDINGS"
else
  mkdir -p "$(dirname "$BINDINGS")"
  cat >>"$BINDINGS" <<BIND

# omapass — password manager overlay
bindd = $KEYBIND, Passwords, exec, omarchy-shell shell toggle omapass
BIND
  say "✓ added ${KEYBIND//,/ +} to $BINDINGS"
  hyprctl reload >/dev/null 2>&1 || true
fi

echo
say "omapass installed. Press ${KEYBIND//,/ +} to open it."
if ! command -v pass >/dev/null 2>&1; then
  say "pass isn't installed yet — the overlay will offer to set it up on first open."
fi
