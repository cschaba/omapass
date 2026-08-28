# Developing omapass

Notes for working on omapass itself. If you only want to *use* it, everything
you need is in [README.md](README.md).

[CHANGELOG.md](CHANGELOG.md) records what changed when.

## Layout

| Path | |
|------|--|
| `manifest.json` | Omarchy plugin manifest, and the only place the version lives |
| `Omapass.qml` | the full-screen overlay |
| `BarWidget.qml` | the bar icon and its search pulldown |
| `EntryEditor.qml` | the add/edit form |
| `FingerprintGate.qml` | fingerprint and password unlock |
| `SetupNotice.qml`, `ActionHints.qml` | the first-run screen, the clickable key hints |
| `PassService.qml` | every call into `bin/omapass` — the only place that shells out |
| `PassStore.js` | pure functions: filtering, entry parsing, body composition |
| `bin/omapass` | the backend; everything that touches a secret happens here |
| `bin/omapass-setup` | guided first-run, run in a terminal |
| `bin/omapass-reset` | returns things to a pre-setup state, for testing |
| `lib/config.sh` | config parsing, shared by the scripts in `bin/` |
| `tests/smoke.sh` | the test suite |
| `scripts/release.sh` | cuts a release |

The UI never parses the config file and never runs `pass` directly. It calls
`bin/omapass`, which resolves everything and answers in JSON, so there is only
ever one parser and one place where secrets are handled.

## Working on it

`install.sh` symlinks your checkout into `~/.config/omarchy/plugins/omapass`,
so edits are picked up without reinstalling — but you have to ask for a reload:

```bash
omarchy restart shell                      # the reliable reload
omarchy-shell shell toggle omapass         # open the overlay
omarchy-shell omapass.widget toggle        # open the bar pulldown
journalctl --user -f | grep omarchy-shell  # QML errors land here
```

**`rescanPlugins` does not reload code through the symlink.** The shell watches
`~/.config/omarchy/plugins` with `inotifywait -r`, which does not follow symlinked
directories, so nothing ever fires; and `rescanPlugins` re-reads manifests without
re-instantiating a `keepLoaded` plugin. Use `omarchy restart shell`, or work
directly in a real directory under `~/.config/omarchy/plugins/`.

### Two traps that cost an afternoon each

**A bar widget must publish its own implicit size.** The bar sizes each slot
from `activeItem.implicitWidth/implicitHeight`, so a widget root that does not
set them gets a 0×0 slot and renders nothing — no icon, no gap, no error, no log
line. Built-ins do this explicitly (see `panels/power/Panel.qml`), and so does
`BarWidget.qml`.

**Errors in a plugin can surface silently.** Omarchy's panel Loader error path
calls `errorString()` as a function, which throws, so the real message is lost.
To see what a plugin file actually says, load it in a throwaway Quickshell config
*outside* the shell's config root:

```bash
mkdir -p /tmp/probe && cd /tmp/probe
ln -sfn /usr/share/omarchy/shell/Commons Commons
ln -sfn /usr/share/omarchy/shell/Ui Ui
cat > shell.qml <<'EOF'
import Quickshell
import QtQuick
ShellRoot { FloatingWindow { Loader {
  source: "file:///path/to/omapass/BarWidget.qml"
  onStatusChanged: console.warn("status=" + status)   // 1 Ready, 3 Error
} } }
EOF
quickshell -p /tmp/probe
```

Keep the plugin outside that config root — inside it, Quickshell treats the
directory as a module and sibling types stop resolving, which produces
misleading `X is not a type` errors.

## Testing the fingerprint paths

These cannot be tested without hardware, so they are the least-proven part of
omapass. This is the plan a tester should work through; the running record of
what has actually been confirmed is
[issue #11](https://github.com/cschaba/omapass/issues/11).

Check the gate is even active before starting — `bin/omapass fingerprint` must
report `true`, which needs **both** `/etc/pam.d/omarchy-lock-fingerprint` and an
enrolled finger in `fprintd-list $USER`.

| # | Case | Expected |
|---|------|----------|
| 1 | Open the overlay with a finger enrolled | Gate instead of the picker |
| 2 | Open the pulldown | Compact gate, search field hidden |
| 3 | Good scan | Gate clears, entries appear |
| 4 | Reopen within `fingerprint-grace` | No second scan |
| 5 | Reopen after it expires | Scan asked for again |
| 6 | Unlock the pulldown, then open the overlay | Overlay asks again — separate windows, by design |
| 7 | Wrong finger | Falls back to the password after `fingerprint-retries` conversations |
| 8 | Reader unreachable (`systemctl stop fprintd`, or block the sensor) | Falls back after two device errors, "reader is not available" |
| 9 | `Tab` after a fallback has fired | Returns to the reader, counters reset, scan retried |
| 10 | Correct login password | Unlocks |
| 11 | Wrong login password | "Wrong password", field cleared, retry works |
| 12 | `Esc` from either mode | Closes, nothing unlocked |
| 13 | `touch ~/.config/omapass/no-fingerprint` | Gate gone |
| 14 | `fingerprint = off` | Gate gone |
| 15 | `fingerprint = always` with the reader unavailable | Gate appears, then falls back |
| 16 | No `omarchy-lock-password` service, then fail the reader | Says there is nothing to fall back on, rather than offering a dead link |

Case 16 needs root and moves a system file; put it back afterwards.

### Counting is per conversation, not per touch

`fprintd` retries roughly three scans inside one PAM conversation before
reporting failure, and `fingerprint-retries` counts conversations. One is
therefore about three touches. Getting this wrong once made the fallback take
ten touches and read as a hang — see [#10].

### A trap when testing the pinentry paths

Reveal, the editor, and the pulldown's OTP hint are gated on gpg-agent already
holding a key, so they need a test key **with** a passphrase that you unlock
once. With a passphrase-less key `gpg-connect-agent` never reports anything
cached, `omapass unlocked` stays false, and those paths look broken when they
are not.

Everything else works fine against a passphrase-less key, which is otherwise the
easier fixture — see the safety rules above about never testing against a real
store.

[#10]: https://github.com/cschaba/omapass/issues/10

## Verifying the argv claim

"Secrets are never passed as arguments" is the kind of claim that rots quietly,
so it is worth being able to re-check. Put logging shims ahead of the real
binaries on `PATH` and read back every argv the helper execs:

```bash
mkdir -p /tmp/shim && export ARGV_LOG=/tmp/argv.log && : > "$ARGV_LOG"
for t in pass gpg gpg2 wl-copy wtype setsid timeout; do
  real=$(command -v "$t") || continue
  printf '#!/bin/bash
{ printf "%%s|" "%s"; printf "%%s " "$@"; echo; } >> "$ARGV_LOG"
exec "%s" "$@"
'     "$t" "$real" > "/tmp/shim/$t"
  chmod +x "/tmp/shim/$t"
done

PATH=/tmp/shim:$PATH bin/omapass copy some/entry
grep -F "$(bin/omapass reveal some/entry)" "$ARGV_LOG" && echo LEAK || echo clean
```

The copy path should exec exactly this — an entry name, a file path, and a
`wl-copy` with no payload, the secret arriving only down the pipe:

```
pass|show -- some/entry
gpg2|-d --quiet ... /home/you/.password-store/some/entry.gpg
setsid|timeout 45 wl-copy --type text/plain --sensitive --foreground
```

## Tests

```bash
tests/smoke.sh
```

Builds a throwaway GPG home and password store, exercises the CLI against it,
and cleans up after itself — it never touches a real store. It also checks that
every subcommand the dispatcher can reach is actually defined, which is not
paranoia: `unlocked` was dispatched to a function that had been deleted, and
bash only complains when that branch is taken, so it shipped twice.

## Releasing

`manifest.json` holds the version — Omarchy requires it there, so a second copy
anywhere else could only drift out of step. `bin/omapass version` and the
`version` field of `omapass status` both read it.

```bash
scripts/release.sh patch --dry-run   # see what it would do
scripts/release.sh minor             # or major, or an explicit 1.4.0
```

The script refuses before it writes anything: dirty tree, not on `main`, behind
the remote, tag already present, failing tests, unparseable shell or QML, invalid
`manifest.json`, or a `CHANGELOG.md` with no `[Unreleased]` section. Then it
bumps the manifest, moves the `[Unreleased]` entries under the new version with
today's date, commits, tags `vX.Y.Z`, and pushes.

Pushing the tag is what starts the release workflow. It re-checks that the tag
and the manifest agree, runs the tests again, and publishes:

| Asset | |
|-------|--|
| `omapass-X.Y.Z.tar.gz` | the plugin directory, droppable into `~/.config/omarchy/plugins/omapass` |
| `omapass-X.Y.Z.tar.gz.sha256` | its checksum |
| `PKGBUILD` | Arch package, with the version and checksum already filled in |

The tarball is unpacked and exercised in CI before publishing, so a release that
cannot run `omapass version` from a clean extract never reaches the releases
page.

Most people will not use any of it — `omarchy plugin add` clones the repository,
so a tag is only a marker. The tarball matters for offline installs and for
packaging.

### CI

Every push and pull request runs four jobs: `shellcheck --severity=warning` over
every script, `tests/smoke.sh` against a throwaway store, a `qmlformat` parse of
every QML file, and a `manifest.json` check that its entry points exist and its
version is semver.

The QML job parses rather than lints. `qs.Commons` and `qs.Ui` only resolve
inside the Omarchy shell, and older `qmllint` treats an unresolved import as an
error, so it rejects every file regardless of syntax. `qmlformat` ignores imports
and still catches real syntax errors. Run `qmllint -I /usr/share/omarchy/shell`
locally for the type checking CI cannot do.
