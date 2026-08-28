#!/bin/bash

# Installs omapass into Omarchy: links the plugin, enables it in the shell, and
# adds the keybinding. Safe to re-run.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="cschaba.omapass"
LEGACY_ID="omapass"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
LEGACY_DIR="$HOME/.config/omarchy/plugins/$LEGACY_ID"
BINDINGS="$HOME/.config/hypr/bindings.conf"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

# The hotkey comes from the config file, so changing it is a config edit plus a
# re-run rather than an argument you have to remember. OMAPASS_KEYBIND still
# wins, as it does everywhere else.
KEYBIND="$("$SOURCE_DIR/bin/omapass" config 2>/dev/null |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["keybind"])' 2>/dev/null)"
KEYBIND="${KEYBIND:-SUPER SHIFT, K}"

say() { echo "  $*"; }

# Everything this script writes outside its own plugin directory, backed up the
# first time it is touched in a run. install.sh edits two files the user owns —
# saying so, and leaving a copy, is the difference between "we only change our
# own entries" being a claim and being checkable.
backup_once() {
  local file="$1" stamp
  [[ -f $file ]] || return 0
  stamp="${file}.omapass-backup"
  [[ -e $stamp ]] && return 0
  cp -p "$file" "$stamp"
  say "  saved $stamp"
}

echo "omapass will change two files that belong to you:"
say "$SHELL_JSON — adds its bar widget and plugin entry"
say "$BINDINGS — adds the keybinding"
say "A copy of each is kept alongside it. ./uninstall.sh removes both entries."
echo

# 0. migrate an install from before the id was namespaced. Without this the old
# plugin directory stays behind and the shell loads omapass twice — once under
# each id — which fights over the bar slot and the IPC target.
if [[ -e $LEGACY_DIR || -L $LEGACY_DIR ]]; then
  # Never delete the tree we are installing from — someone whose checkout *is*
  # the old plugin directory would lose it.
  if [[ "$(readlink -f "$LEGACY_DIR")" == "$SOURCE_DIR" && ! -L $LEGACY_DIR ]]; then
    say "! $LEGACY_DIR is this checkout; move it aside and re-run to finish the rename"
  else
    omarchy-shell shell setPluginEnabled "$LEGACY_ID" false >/dev/null 2>&1 || true
    rm -rf "$LEGACY_DIR"
    say "✓ removed the old $LEGACY_ID plugin directory"
  fi
fi

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
  omarchy-shell shell setPluginEnabled "$PLUGIN_ID" true >/dev/null 2>&1 || true
  say "✓ enabled in omarchy-shell"
else
  say "! omarchy-shell is not running — it will pick omapass up on next start"
fi

# 3. bar widget
# A dual-kind plugin (overlay + bar-widget) is already "enabled" via plugins[],
# so `omarchy bar put` reports success and adds nothing. Write the layout entry
# ourselves when it is missing.
if command -v python3 >/dev/null 2>&1; then
  backup_once "$SHELL_JSON"
  python3 - "$SHELL_JSON" "$PLUGIN_ID" "$LEGACY_ID" <<'PYEOF'
import json, os, sys, tempfile

path, plugin_id, legacy_id = sys.argv[1], sys.argv[2], sys.argv[3]
if not os.path.exists(path):
    print(f"  ! no shell.json yet — add the widget with: omarchy bar put {plugin_id}")
    raise SystemExit(0)

try:
    with open(path) as f:
        config = json.load(f)
except (json.JSONDecodeError, OSError) as exc:
    # Refuse rather than guess: rewriting a file we could not parse is exactly
    # the way an installer eats somebody's configuration.
    print(f"  ! could not read {path}: {exc}")
    print(f"  ! leaving it alone — add the widget yourself with: omarchy bar put {plugin_id}")
    raise SystemExit(0)

changed = False

# Rename any entry left over from the un-namespaced id, in both places it can
# appear: the enabled-plugins list and the bar layout.
plugins = config.get("plugins")
if isinstance(plugins, list):
    for entry in plugins:
        if isinstance(entry, dict) and entry.get("id") == legacy_id:
            entry["id"] = plugin_id
            changed = True

layout = config.setdefault("bar", {}).setdefault("layout", {})
for section in layout.values():
    for entry in section:
        if isinstance(entry, dict) and entry.get("id") == legacy_id:
            entry["id"] = plugin_id
            changed = True

placed = any(e.get("id") == plugin_id for sec in layout.values() for e in sec)
if not placed:
    right = layout.setdefault("right", [])
    index = next((i for i, e in enumerate(right) if e.get("id") == "omarchy.power"), len(right))
    right.insert(index, {"id": plugin_id})
    changed = True

if not changed:
    print("  ✓ bar widget already placed")
    raise SystemExit(0)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print("  ✓ bar widget placed" if not placed else "  ✓ migrated the bar widget to the new plugin id")
PYEOF
fi

# 4. keybinding
# Rewrite rather than append: re-running after changing the hotkey should move
# the binding, not leave the old one behind to conflict with the new one.
mkdir -p "$(dirname "$BINDINGS")"
touch "$BINDINGS"
backup_once "$BINDINGS"

if grep -qE "shell toggle ($PLUGIN_ID|$LEGACY_ID)\\b" "$BINDINGS"; then
  existing=$(grep -m1 -E "shell toggle ($PLUGIN_ID|$LEGACY_ID)\\b" "$BINDINGS")
  if [[ $existing == *"$KEYBIND"* && $existing == *"$PLUGIN_ID"* ]]; then
    say "✓ keybinding already set to ${KEYBIND//,/ +}"
  else
    tmp=$(mktemp)
    grep -vE "shell toggle ($PLUGIN_ID|$LEGACY_ID)\\b" "$BINDINGS" |
      grep -v "^# omapass — password manager overlay$" >"$tmp"
    mv "$tmp" "$BINDINGS"
    cat >>"$BINDINGS" <<BIND

# omapass — password manager overlay
bindd = $KEYBIND, Passwords, exec, omarchy-shell shell toggle $PLUGIN_ID
BIND
    say "✓ keybinding set to ${KEYBIND//,/ +}"
    hyprctl reload >/dev/null 2>&1 || true
  fi
else
  cat >>"$BINDINGS" <<BIND

# omapass — password manager overlay
bindd = $KEYBIND, Passwords, exec, omarchy-shell shell toggle $PLUGIN_ID
BIND
  say "✓ added ${KEYBIND//,/ +} to $BINDINGS"
  hyprctl reload >/dev/null 2>&1 || true
fi

echo
say "omapass installed. Press ${KEYBIND//,/ +} to open it."
if ! command -v pass >/dev/null 2>&1; then
  say "pass isn't installed yet — the overlay will offer to set it up on first open."
fi
