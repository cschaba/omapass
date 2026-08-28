# omapass

> [!WARNING]
> **Under development. Not tested. Do not trust it with passwords you cannot
> afford to lose.**
>
> This is early work on an alpha version of Omarchy 4. It has not been used in
> anger by anyone, on any machine, for any length of time. In particular the
> paths that decrypt — copy, type, reveal, edit, and QR enrolment — have never
> been driven through the GUI by a human; they have only been exercised from the
> command line against a throwaway store.
>
> Everything is written to your real `pass` store, and delete and edit are real
> deletes and real overwrites. If you try it, back the store up first
> (`tar -czf pass-backup.tar.gz ~/.password-store`) or point it somewhere
> disposable with `PASSWORD_STORE_DIR`.

A password manager for [Omarchy 4](https://omarchy.org), built as a shell
plugin and backed by [`pass`](https://www.passwordstore.org/).

It gives you two ways in. A bar icon with a search pulldown for the common
case — find a password, copy it, get on with your day. And a full-screen
overlay, in the same family as Omarchy's clipboard and emoji pickers, that also
creates, edits, generates, renames and deletes entries, so `pass` on the command
line stays optional.

The bar pulldown — click the lock, or search straight away:

```
 󰌾  ← bar icon
 ┌────────────────────────────────┐
 │ git                            │
 ├────────────────────────────────┤
 │ carsten          github.com    │
 │ deploy-bot       github.com    │
 ├────────────────────────────────┤
 │ ⏎ copy  ⇧⏎ type      Manage…   │
 └────────────────────────────────┘
```

And the full manager:

```
SUPER + CTRL + K

 ┌────────────────────────────────────────────────┐
 │ github                              3 of 24    │
 ├──────────────────────┬─────────────────────────┤
 │ ▸ cs                 │ github.com/cs           │
 │   github.com         │                         │
 │                      │ password                │
 │   deploy-bot         │ ••••••••••••            │
 │   github.com         │                         │
 │                      │ login                   │
 │   personal           │ cs@example.com          │
 │   github.com         │                         │
 ├──────────────────────┴─────────────────────────┤
 │ ⏎ copy  ⇧⏎ type  ⌥⏎ user  ^L fill login  …     │
 └────────────────────────────────────────────────┘
```

## Install

```bash
git clone https://github.com/cschaba/omapass.git
cd omapass
./install.sh
```

`install.sh` links the plugin into `~/.config/omarchy/plugins/omapass`, enables
it in the running shell, puts the widget on your bar, and adds a
`SUPER + CTRL + K` binding to `~/.config/hypr/bindings.conf`. Set
`OMAPASS_KEYBIND` to choose a different one:

```bash
OMAPASS_KEYBIND="SUPER, P" ./install.sh
```

If you would rather use Omarchy's own plugin installer:

```bash
omarchy plugin add https://github.com/cschaba/omapass.git --enable --yes
```

Then place the bar widget and add the binding yourself. Note that
`omarchy bar put omapass` reports success but does nothing here: omapass
declares both `overlay` and `bar-widget`, so the shell already considers it
enabled through `plugins[]` and never writes a layout entry. Add it to
`~/.config/omarchy/shell.json` by hand instead:

```jsonc
"bar": { "layout": { "right": [ /* … */ { "id": "omapass" }, { "id": "omarchy.power" } ] } }
```

and the binding:

```
bindd = SUPER CTRL, K, Passwords, exec, omarchy-shell shell toggle omapass
```

To reach it from the Omarchy menu too, add a row to
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"passwords": {"icon":"󰌾","label":"Passwords","aliases":["pass","omapass"],
              "action":"omarchy-shell shell toggle omapass"},
```

### First run

omapass needs `pass`, a GPG key, and an initialised password store. If any of
them is missing, the overlay says so and offers to walk you through it —
press Enter and it opens a terminal running `bin/omapass-setup`, which installs
the packages, generates a key, and runs `pass init`.

If you already use `pass`, there is nothing to do; omapass reads the store you
have, including one you clone from another machine.

## Keys

### Bar pulldown

The search field is focused the moment it opens, so just type.

| Key | Action |
|-----|--------|
| `↑` `↓` `PgUp` `PgDn` | move through results |
| `Enter` | copy password |
| `Shift+Enter` | type the password into the window underneath |
| `Alt+Enter` | copy the username |
| `Ctrl+L` | fill a login form |
| `Ctrl+O` | copy the one-time code |
| `Ctrl+Shift+O` | type the one-time code |
| `Ctrl+N` / `Ctrl+E` | open the full manager |
| `Esc` | clear the search, then close |

### Full overlay

| Key | Action |
|-----|--------|
| type anything | filter |
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | move |
| `Enter` | copy password to the clipboard |
| `Shift+Enter` | type the password into the window underneath |
| `Alt+Enter` | copy the username |
| `Ctrl+L` | fill a login form — username, Tab, password, Enter |
| `Ctrl+O` | copy the one-time code (needs `pass-otp`) |
| `Ctrl+Shift+O` | type the one-time code |
| `Ctrl+Q` | scan a QR code into the selected entry |
| `Esc` | leave the fingerprint prompt, when one is shown |
| `Ctrl+R` | reveal the password in the detail pane |
| `Tab` | unlock the store / load details for the selected entry |
| `Ctrl+N` | new entry |
| `Ctrl+E` | edit the selected entry |
| `Delete` / `Ctrl+D` | delete the selected entry |
| `Ctrl+S` | `git pull --rebase && git push` the store |
| `Esc` | clear the filter, then close |

In the editor: `Ctrl+Enter` saves, `Esc` cancels, `Tab` moves between fields.
Renaming is just editing the name — omapass runs `pass mv` for you.

## How it handles secrets

The plugin runs inside `omarchy-shell`, a long-lived process that also draws
your bar and handles notifications. Keeping decrypted passwords in there would
mean keeping them in memory for the length of your session, so omapass mostly
doesn't.

- **Copy, type, login and OTP never enter the shell process.** They are detached
  calls to `bin/omapass`, which pipes the secret from `gpg` straight into
  `wl-copy` or `wtype` and exits.
- **Secrets are never passed as arguments.** They travel in shell variables and
  over stdin, so they never show up in `/proc/*/cmdline` or in `ps` output for
  other users on the machine.
- **The clipboard is marked sensitive.** `wl-copy --sensitive` sets the
  `x-kde-passwordManagerHint` type, which is what Omarchy's own clipboard
  manager checks before recording a copy — so a password you copy here does not
  end up in your clipboard history. The copy is served by a `wl-copy` that
  `timeout` kills after 45 seconds (`OMAPASS_CLIP_TIME`), dropping the selection
  entirely.
- **The detail pane does not decrypt on its own.** Moving the cursor down a list
  of 200 entries should not fire 200 pinentry prompts, so omapass only reads an
  entry for preview once `gpg-agent` already has your key cached. Until then the
  pane says `Locked`, and `Tab` is the deliberate unlock.
- **Two paths do bring a password into QML, both by request:** `Ctrl+R`, which
  clears itself after 15 seconds, and opening the editor on an existing entry —
  `pass` stores an entry as a single blob, so rewriting one means having all of
  it. Both are cleared when the overlay closes.

None of this defends against someone who is already running code as you. It
defends against the ordinary ways a password leaks sideways: clipboard history,
process listings, and a long-lived GUI process holding your vault in memory.

### Checking the argv claim yourself

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

### Entry names

`pass` takes the entry name as a positional argument, so a name beginning with
`-` would be read as an option — `insert`, `generate` and `mv` have no
file-existence check to catch it first. Names starting with `-` are rejected,
and every call site passes `--` before the name.

## The CLI

`bin/omapass` is a normal script and works on its own:

```bash
bin/omapass status                  # JSON: what is installed and set up
bin/omapass fingerprint             # JSON: whether fingerprint unlock applies
bin/omapass list                    # JSON: every entry
bin/omapass fields github.com/cs    # JSON: everything except the password
bin/omapass copy github.com/cs
bin/omapass type github.com/cs
bin/omapass login github.com/cs     # username, Tab, password, Enter
bin/omapass otp github.com/cs copy
bin/omapass otp-scan github.com/cs  # read a QR code off the screen
bin/omapass body github.com/cs      # whole entry — the editor's read path
bin/omapass insert new/entry --generate 32 yes < body
bin/omapass rename old/name new/name
bin/omapass remove old/entry
bin/omapass sync
```

Entries are plain `pass` entries — password on the first line, `key: value`
after it, an `otpauth://` line for TOTP:

```
hunter2
login: cs@example.com
url: https://github.com
otpauth://totp/GitHub:cs?secret=…
```

## Fingerprint unlock

If you have a fingerprint enrolled, omapass puts a scan in front of the vault —
both the overlay and the bar pulldown show a reader prompt instead of your
entries until you touch it.

It is on automatically when, and only when, both of these are true:

- `/etc/pam.d/omarchy-lock-fingerprint` exists, and
- `fprintd-list $USER` reports an enrolled finger

That is the same pair Omarchy's own lock screen tests, and it authenticates
against the same PAM service. Requiring both matters: a reader with nothing
enrolled would put up a prompt that can never be satisfied.

A successful scan holds for two minutes, so opening the picker twice in a row
does not cost two touches. Each surface keeps its own window — unlocking the
pulldown does not unlock the overlay.

### It cannot lock you out

A biometric gate in front of your passwords is only reasonable if it always has
a way past:

- `Esc` closes the surface at any time.
- `pass` on the command line is untouched, and so is `bin/omapass`. The gate is
  in the GUI, not in the store.
- Creating `~/.config/omapass/no-fingerprint` turns it off. After three failed
  reads the prompt says so on screen.
- A failed scan re-arms rather than giving up, because fprintd ends the
  conversation on a bad read.

This is a second local factor in front of a GUI, not a cryptographic one. Your
entries are still encrypted to your GPG key and still need its passphrase; the
fingerprint does not protect anything on disk.

> **Untested.** This machine has no fingerprint reader and no
> `omarchy-lock-fingerprint` PAM service, so the detection logic was verified in
> both directions but the scan itself has never run. Treat it as unproven.

## One-time codes (TOTP)

omapass stores TOTP secrets the way `pass-otp` does — an `otpauth://` line in
the entry — so anything else that speaks pass-otp reads the same store.

| What | How |
|------|-----|
| Enrol from a QR code | select the entry, `Ctrl+Q`, drag a box over the code on screen |
| Enrol by hand | paste the `otpauth://` URI into the editor's OTP field |
| Copy the current code | `Ctrl+O` (overlay or pulldown) |
| Type the code into a form | `Ctrl+Shift+O` |
| See which entries have one | the detail pane says so; `omapass fields` reports `"otp": true` |

`Ctrl+Q` pipes `grim` into `zbarimg` without the screenshot touching disk, and
replaces an entry's existing `otpauth://` line rather than stacking a second
one. It needs `slurp`, `grim` and `zbar`; the first two ship with Omarchy.

The code itself is treated like a password: copied with the sensitive hint set,
and dropped from the clipboard after `OMAPASS_CLIP_TIME`.

Not implemented: showing a live code with a countdown in the detail pane. Copy
and type cover the actual use, and a live display would mean decrypting the
entry on a timer for as long as the panel is open.

## Testing the setup flow again

`bin/omapass-reset` puts things back to a pre-setup state so the first-run
experience can be exercised more than once.

```bash
bin/omapass-reset --status         # what is set up, and which backups exist
bin/omapass-reset                  # remove the store and its GPG key
bin/omapass-reset --all            # also uninstall pass and pass-otp
bin/omapass-reset --restore        # put the most recent backup back
```

Nothing is deleted before it has been written to a tarball under
`~/.local/state/omapass/backups`, and `--key` exports the secret key *into that
tarball* first — along with its ownertrust, without which a restored key cannot
encrypt. `--restore` puts the store, the key, and the trust back.

gpg-agent is restarted at the end so the next run starts locked, which is the
state the setup flow is meant to be tested from.

## Configuration

One file: `~/.config/omapass/config`. Write a commented template with every
default spelled out:

```bash
bin/omapass config --init
bin/omapass config          # the values actually in force, as JSON
bin/omapass config --path
```

```ini
store             = ~/.password-store   # ~ is expanded
clip-time         = 45                  # seconds before the clipboard is dropped
type-delay        = 12                  # ms between simulated keystrokes
type-focus-delay  = 0.2                 # seconds to wait for focus before typing
reveal-timeout    = 15                  # seconds a revealed password stays up
fingerprint       = auto                # auto | always | off
fingerprint-grace = 120                 # seconds a successful scan stays valid
pulldown-rows     = 7                   # rows in the bar pulldown
backup-dir        = ~/.local/state/omapass/backups
```

`key = value`, `#` comments, and `key_name` works as well as `key-name`.
Precedence is **environment > config file > default**, so a one-off run can
override without editing anything:

```bash
OMAPASS_CLIP_TIME=5 bin/omapass copy some/entry
PASSWORD_STORE_DIR=/tmp/scratch bin/omapass list
```

The file is parsed, never sourced — a config file that can run code is a config
file that can be turned into a payload. Unknown keys and unparseable numbers
produce a warning on stderr and fall back to the default rather than failing.

The overlay and the pulldown do not read this file. `bin/omapass status` resolves
everything and hands the result over as JSON, so there is only ever one parser.

`fingerprint = always` requires a scan whenever the PAM service exists, even
when enrolment cannot be confirmed — useful for a reader `fprintd-list` does not
report cleanly. `Esc` and the `pass` CLI still get you past it either way.

The bar pulldown's row count can also be set per-widget in `shell.json`
(Setup → Plugins), which wins over `pulldown-rows`.

## Tests

```bash
tests/smoke.sh
```

Builds a throwaway GPG home and password store, exercises the CLI against it,
and cleans up after itself — it never touches a real store. It also checks that
every subcommand the dispatcher can reach is actually defined, which is not
paranoia: `unlocked` was dispatched to a function that had been deleted, and
bash only complains when that branch is taken, so it shipped twice.

## Requirements

Omarchy 4, `pass`, `gpg`, `wl-clipboard`, `wtype`, and `jq` — all but `pass`
ship with Omarchy. `pass-otp` is optional and only needed for one-time codes;
QR enrolment additionally wants `zbar` (`slurp` and `grim` already ship).

## Development

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

### Two things that cost me an afternoon

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

## License

MIT.
