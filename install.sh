#!/bin/bash

# Installs omapass into Omarchy: links the plugin, enables it in the shell, and
# adds the keybinding. Safe to re-run.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/omapass"
BINDINGS="$HOME/.config/hypr/bindings.conf"

# The hotkey comes from the config file, so changing it is a config edit plus a
# re-run rather than an argument you have to remember. OMAPASS_KEYBIND still
# wins, as it does everywhere else.
KEYBIND="$("$SOURCE_DIR/bin/omapass" config 2>/dev/null |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["keybind"])' 2>/dev/null)"
KEYBIND="${KEYBIND:-SUPER SHIFT, K}"

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

# 3. bar widget
# A dual-kind plugin (overlay + bar-widget) is already "enabled" via plugins[],
# so `omarchy bar put` reports success and adds nothing. Write the layout entry
# ourselves when it is missing.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$HOME/.config/omarchy/shell.json" <<'PYEOF'
import json, os, sys, tempfile

path = sys.argv[1]
if not os.path.exists(path):
    print("  ! no shell.json yet — add the widget with: omarchy bar put omapass")
    raise SystemExit(0)

with open(path) as f:
    config = json.load(f)

layout = config.setdefault("bar", {}).setdefault("layout", {})
if any(e.get("id") == "omapass" for sec in layout.values() for e in sec):
    print("  ✓ bar widget already placed")
    raise SystemExit(0)

right = layout.setdefault("right", [])
index = next((i for i, e in enumerate(right) if e.get("id") == "omarchy.power"), len(right))
right.insert(index, {"id": "omapass"})

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print("  ✓ added the bar widget")
PYEOF
fi

# 4. keybinding
# Rewrite rather than append: re-running after changing the hotkey should move
# the binding, not leave the old one behind to conflict with the new one.
mkdir -p "$(dirname "$BINDINGS")"
touch "$BINDINGS"

if grep -q "shell toggle omapass" "$BINDINGS"; then
  existing=$(grep -m1 "shell toggle omapass" "$BINDINGS")
  if [[ $existing == *"$KEYBIND"* ]]; then
    say "✓ keybinding already set to ${KEYBIND//,/ +}"
  else
    tmp=$(mktemp)
    grep -v "shell toggle omapass" "$BINDINGS" |
      grep -v "^# omapass — password manager overlay$" >"$tmp"
    mv "$tmp" "$BINDINGS"
    cat >>"$BINDINGS" <<BIND

# omapass — password manager overlay
bindd = $KEYBIND, Passwords, exec, omarchy-shell shell toggle omapass
BIND
    say "✓ moved the keybinding to ${KEYBIND//,/ +}"
    hyprctl reload >/dev/null 2>&1 || true
  fi
else
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
