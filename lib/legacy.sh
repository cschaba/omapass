#!/bin/bash
# shellcheck shell=bash
#
# Who owns ~/.config/omarchy/plugins/omapass.
#
# The bare `omapass` id was ours until 0.1.12 namespaced it to
# `cschaba.omapass`, so a directory still sitting under the old name is
# normally an install of ours, left behind for us to clear away. It is no
# longer only ours: other plugins use the name now, and one of them
# (tonyrumans/omapass) declares `omapass` as its plugin id, so it installs to
# exactly that path. By path alone a stale install of ours and a current
# install of theirs are indistinguishable — and the answer decides whether
# something gets `rm -rf`ed. (#44)
#
# The manifest is what tells them apart. Every manifest omapass ever shipped
# names Omapass.qml as its overlay entry point, back to the first commit, where
# a namespaced id and a homepage field do not yet exist. Theirs is a bar widget
# with no overlay at all.
#
# Fail closed: anything that cannot be positively identified as ours belongs to
# somebody else, because the cost of being wrong is asymmetric. Leaving a stale
# directory of ours behind is untidy; deleting a working install of someone
# else's is the kind of thing a password manager does not get to do twice.

# Prints one of:
#   absent   nothing is there
#   ours     safe to disable and remove
#   <id>     the plugin id that claims it, or "unknown" for an unreadable
#            manifest — either way, not ours to touch
legacy_dir_owner() {
  local dir="$1" manifest="$1/manifest.json" id

  [[ -e $dir || -L $dir ]] || { printf 'absent'; return; }

  # No manifest: older than the plugin contract, which has required one since
  # before anyone else used the name. Ours.
  [[ -f $manifest ]] || { printf 'ours'; return; }

  # Any one of these three is proof it is ours, and between them they cover
  # every version we have released under either id. Deliberately grep rather
  # than a JSON parser: the uninstaller has to keep working on a machine where
  # the dependencies have already been taken away.
  if grep -q '"id"[[:space:]]*:[[:space:]]*"cschaba\.omapass"' "$manifest" ||
    grep -q '"overlay"[[:space:]]*:[[:space:]]*"Omapass\.qml"' "$manifest" ||
    grep -q '"homepage"[[:space:]]*:[[:space:]]*"[^"]*github\.com/cschaba/omapass"' "$manifest"; then
    printf 'ours'
    return
  fi

  id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1)
  printf '%s' "${id:-unknown}"
}
