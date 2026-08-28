#!/bin/bash

# Removes omapass from Omarchy: takes the widget off the bar, drops the plugin,
# and removes the keybinding.
#
# It does not touch your password store, your GPG key, or your config — those
# are yours and outlive the plugin. It says where they are on the way out, so
# removing them is a deliberate act rather than a side effect.

set -euo pipefail

PLUGIN_ID="cschaba.omapass"
LEGACY_ID="omapass"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.conf"
CONFIG="${OMAPASS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omapass/config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omapass"

PURGE=0
[[ ${1:-} == "--purge" ]] && PURGE=1
if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  cat <<'USAGE'
./uninstall.sh [--purge]

  Removes the plugin, its bar widget and its keybinding.
  --purge also removes omapass's own config and state.

  Your password store and GPG key are never touched — omapass-reset is the
  one that removes those.
USAGE
  exit 0
fi

say() { echo "  $*"; }

# 1. take it out of the running shell first, so nothing is left half-loaded
for id in "$PLUGIN_ID" "$LEGACY_ID"; do
  omarchy-shell shell setPluginEnabled "$id" false >/dev/null 2>&1 || true
done

# 2. bar layout and enabled-plugins list
if [[ -f $SHELL_JSON ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$SHELL_JSON" "$PLUGIN_ID" "$LEGACY_ID" <<'PYEOF'
import json, os, sys, tempfile

path, *ids = sys.argv[1:]
with open(path) as f:
    config = json.load(f)

removed = False

plugins = config.get("plugins")
if isinstance(plugins, list):
    kept = [e for e in plugins if not (isinstance(e, dict) and e.get("id") in ids)]
    if len(kept) != len(plugins):
        config["plugins"] = kept
        removed = True

layout = config.get("bar", {}).get("layout", {})
for name, section in layout.items():
    kept = [e for e in section if not (isinstance(e, dict) and e.get("id") in ids)]
    if len(kept) != len(section):
        layout[name] = kept
        removed = True

if removed:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    print("  ✓ removed from the bar and the plugin list")
else:
    print("  ✓ nothing left in shell.json")
PYEOF
fi

# 3. the plugin directory, under either id
for dir in "$PLUGINS_DIR/$PLUGIN_ID" "$PLUGINS_DIR/$LEGACY_ID"; do
  if [[ -e $dir || -L $dir ]]; then
    rm -rf "$dir"
    say "✓ removed $dir"
  fi
done

# 4. the keybinding, and the comment line that introduces it
if [[ -f $BINDINGS ]] && grep -qE "shell toggle ($PLUGIN_ID|$LEGACY_ID)\b" "$BINDINGS"; then
  tmp=$(mktemp)
  grep -vE "shell toggle ($PLUGIN_ID|$LEGACY_ID)\b" "$BINDINGS" |
    grep -v "^# omapass — password manager overlay$" >"$tmp"
  mv "$tmp" "$BINDINGS"
  say "✓ removed the keybinding"
  hyprctl reload >/dev/null 2>&1 || true
fi

# 5. omapass's own files, only when asked
if (( PURGE )); then
  [[ -e $CONFIG ]] && rm -f "$CONFIG" && say "✓ removed $CONFIG"
  [[ -d $STATE_DIR ]] && rm -rf "$STATE_DIR" && say "✓ removed $STATE_DIR"
  rmdir "$(dirname "$CONFIG")" 2>/dev/null || true
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

echo
say "omapass removed."
if (( ! PURGE )); then
  [[ -e $CONFIG ]] && say "Its config is still at $CONFIG (--purge removes it)."
fi
for backup in "$HOME/.config/omarchy/shell.json.omapass-backup" \
              "$HOME/.config/hypr/bindings.conf.omapass-backup"; do
  [[ -f $backup ]] && say "install.sh left a copy of your config at $backup"
done
say "Your password store is untouched at ${PASSWORD_STORE_DIR:-$HOME/.password-store}."
say "It is a plain pass store — the pass command still reads it."
