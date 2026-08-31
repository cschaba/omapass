#!/bin/bash

# Installs omapass into Omarchy. Safe to re-run.
#
# It writes nothing outside the plugin. The bar widget and plugin registration
# go through omarchy's own commands, and anything that needs a change to a file
# you own — the keybinding — is printed for you to paste. A plugin editing
# somebody else's config is a plugin you have to trust twice.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="cschaba.omapass"
LEGACY_ID="omapass"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
LEGACY_DIR="$HOME/.config/omarchy/plugins/$LEGACY_ID"
BINDINGS="$HOME/.config/hypr/bindings.lua"
LEGACY_BINDINGS="$HOME/.config/hypr/bindings.conf"

say() { echo "  $*"; }

# The hotkey as the config file spells it ("SUPER ALT, P") becomes the form
# bindings.lua wants ("SUPER + ALT + P").
lua_chord() {
  local spec="$1" mods key
  if [[ $spec == *,* ]]; then
    mods="$(echo "${spec%%,*}" | xargs)"
    key="$(echo "${spec#*,}" | xargs)"
  else
    mods=""
    key="$(echo "$spec" | xargs)"
  fi
  if [[ -n $mods ]]; then
    printf '%s + %s' "$(echo "$mods" | sed 's/  */ + /g')" "$key"
  else
    printf '%s' "$key"
  fi
}

# What Hyprland already runs for this chord, if anything. Its own binding list
# is the only honest answer — it covers tools that have nothing to do with
# Omarchy, which is exactly where a surprise conflict comes from.
chord_holder() {
  local spec="$1" mods key mask=0 m
  command -v hyprctl >/dev/null 2>&1 || return 0
  if [[ $spec == *,* ]]; then
    mods="${spec%%,*}"
    key="${spec#*,}"
  else
    mods=""
    key="$spec"
  fi
  for m in $mods; do
    case "${m^^}" in
    SUPER) mask=$((mask + 64)) ;;
    ALT) mask=$((mask + 8)) ;;
    CTRL | CONTROL) mask=$((mask + 4)) ;;
    SHIFT) mask=$((mask + 1)) ;;
    esac
  done
  hyprctl binds -j 2>/dev/null | python3 -c '
import json, sys
mask, key = int(sys.argv[1]), sys.argv[2].upper()
try:
    binds = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for b in binds:
    if b.get("modmask") == mask and str(b.get("key", "")).upper() == key:
        if b.get("description") == "omapass":
            continue
        print(b.get("description") or b.get("dispatcher") or "another binding")
        break
' "$mask" "$(echo "$key" | xargs)" 2>/dev/null
}

CONFIG_JSON="$("$SOURCE_DIR/bin/omapass" config 2>/dev/null || echo '{}')"
config_value() {
  printf '%s' "$CONFIG_JSON" |
    python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

KEYBIND="$(config_value keybind)"
KEYBIND="${KEYBIND:-SUPER ALT, P}"
BAR_SECTION="$(config_value barSection)"
CHORD="$(lua_chord "$KEYBIND")"

# --- 1. the plugin itself ---------------------------------------------------

if [[ -e $LEGACY_DIR || -L $LEGACY_DIR ]]; then
  if [[ "$(readlink -f "$LEGACY_DIR")" == "$SOURCE_DIR" && ! -L $LEGACY_DIR ]]; then
    say "! $LEGACY_DIR is this checkout; move it aside and re-run"
  else
    omarchy plugin disable "$LEGACY_ID" >/dev/null 2>&1 || true
    rm -rf "$LEGACY_DIR"
    say "✓ removed the old $LEGACY_ID plugin directory"
  fi
fi

# Nothing of omapass was here before this run: a first install rather than a
# re-run or an upgrade. It decides one thing only — whether to greet the user
# again, below.
FIRST_INSTALL=false
[[ -e $PLUGIN_DIR || -L $PLUGIN_DIR ]] || FIRST_INSTALL=true

if [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
  say "✓ plugin already installed at $PLUGIN_DIR"
elif [[ -L $PLUGIN_DIR && $(readlink -f "$PLUGIN_DIR") == "$SOURCE_DIR" ]]; then
  say "✓ plugin already linked from $SOURCE_DIR"
else
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  ln -sfn "$SOURCE_DIR" "$PLUGIN_DIR"
  say "✓ linked $SOURCE_DIR → $PLUGIN_DIR"
fi

# Uninstalling leaves the "you have been welcomed" marker behind on purpose, so
# that re-running this script does not nag. But someone who removed omapass and
# is putting it back has asked to start over, and being greeted is part of
# starting over. Only omapass's own state is touched.
if [[ $FIRST_INSTALL == true ]]; then
  "$SOURCE_DIR/bin/omapass" welcomed --reset >/dev/null 2>&1 || true
fi

# The shell keeps its own list of what is installed, and a directory that
# appeared after it started is not on it. Quiet and best-effort: on a machine
# with no shell running there is nothing to tell.
omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

# --- 2. registration, through omarchy's own command -------------------------

# Whether the widget is already on the bar, asked of omarchy rather than read
# out of shell.json.
on_bar() {
  omarchy-shell shell listPlugins 2>/dev/null |
    python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if any(p.get("id") == sys.argv[1] and p.get("enabled") for p in plugins) else 1)
' "$PLUGIN_ID" 2>/dev/null
}

if command -v omarchy >/dev/null 2>&1; then
  if on_bar; then
    # Already placed: where it sits is Omarchy's to remember, and moving it
    # back on every re-run would undo whatever the user last chose.
    say "✓ already enabled and on the bar"
    [[ -n $BAR_SECTION ]] &&
      say "  (bar-section is only used for the first placement — move it with" &&
      say "   omarchy bar move $PLUGIN_ID --section $BAR_SECTION)"
  else
    placement=()
    [[ -n $BAR_SECTION ]] && placement=(--section "$BAR_SECTION")
    if omarchy plugin enable "$PLUGIN_ID" "${placement[@]}" >/dev/null 2>&1; then
      say "✓ enabled, and the bar widget placed${BAR_SECTION:+ on the $BAR_SECTION}"
    else
      say "! could not enable it — run:  omarchy plugin enable $PLUGIN_ID"
    fi
  fi
else
  say "! omarchy not found — run:  omarchy plugin enable $PLUGIN_ID"
fi

# --- 3. the keybinding, which is yours to add -------------------------------

echo
# The chord already in the file, if any. Worth reading rather than just
# noticing that a line exists: the default moved in 0.1.45, so anyone upgrading
# has a working binding that no longer matches what the config asks for, and
# being told "already there" would hide that entirely. (#41)
existing_chord() {
  [[ -f $BINDINGS ]] || return 0
  sed -n "s/.*o\.bind(\"\([^\"]*\)\".*shell toggle $PLUGIN_ID.*/\1/p" "$BINDINGS" | head -1
}

EXISTING="$(existing_chord)"

if [[ -n $EXISTING ]]; then
  if [[ $EXISTING == "$CHORD" ]]; then
    say "✓ a keybinding for OmaPass is already in $BINDINGS"
  else
    say "✓ OmaPass is on $EXISTING in $BINDINGS"
    say "  Your config asks for $CHORD. Keep the one you have, or swap the line for:"
    echo
    echo "    o.bind(\"$CHORD\", \"omapass\", \"omarchy-shell shell toggle $PLUGIN_ID\")"
    echo
    say "  then reload with:  hyprctl reload"
  fi
elif [[ -f $BINDINGS ]] && grep -q "shell toggle $PLUGIN_ID" "$BINDINGS"; then
  say "✓ a keybinding for OmaPass is already in $BINDINGS"
else
  say "One step left, in a file that belongs to you. Add this to"
  say "$BINDINGS:"
  echo
  echo "    -- omapass"
  echo "    o.bind(\"$CHORD\", \"omapass\", \"omarchy-shell shell toggle $PLUGIN_ID\")"
  echo
  say "then reload with:  hyprctl reload"
fi

HOLDER="$(chord_holder "$KEYBIND")"
if [[ -n $HOLDER ]]; then
  echo
  say "! $CHORD is already bound to \"$HOLDER\"."
  say "! Choose another with  keybind = SUPER SHIFT, K  in ~/.config/omapass/config"
  say "! and re-run this script to see the updated line."
fi

# Older versions wrote the binding to a file Hyprland never reads. Say so;
# removing it is not ours to do.
if [[ -f $LEGACY_BINDINGS ]] && grep -qE "shell toggle ($PLUGIN_ID|$LEGACY_ID)\b" "$LEGACY_BINDINGS"; then
  echo
  say "! An older OmaPass left a keybinding in $LEGACY_BINDINGS."
  say "! Omarchy 4 never reads that file, so the line does nothing. Delete it"
  say "! when convenient — OmaPass will not touch it."
fi

echo
say "OmaPass installed."
if ! command -v pass >/dev/null 2>&1; then
  say "pass isn't installed yet — OmaPass will offer to set it up on first open."
fi
if [[ $FIRST_INSTALL == true ]]; then
  say "The welcome screen opens by itself in a moment — no need to press anything."
fi
