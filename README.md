# omapass

A password manager for [Omarchy 4](https://omarchy.org), built as a shell
plugin and backed by [`pass`](https://www.passwordstore.org/).

It is a full-screen overlay in the same family as Omarchy's clipboard and emoji
pickers: one keystroke opens it, you type to filter, and Enter puts the password
on your clipboard. It also creates, edits, generates, renames and deletes
entries, so `pass` on the command line stays optional.

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
git clone https://github.com/you/omapass.git
cd omapass
./install.sh
```

`install.sh` links the plugin into `~/.config/omarchy/plugins/omapass`, enables
it in the running shell, and adds a `SUPER + CTRL + K` binding to
`~/.config/hypr/bindings.conf`. Set `OMAPASS_KEYBIND` to choose a different one:

```bash
OMAPASS_KEYBIND="SUPER, P" ./install.sh
```

If you would rather use Omarchy's own plugin installer:

```bash
omarchy plugin add https://github.com/you/omapass.git --enable --yes
```

Then add the binding yourself:

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

| Key | Action |
|-----|--------|
| type anything | filter |
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | move |
| `Enter` | copy password to the clipboard |
| `Shift+Enter` | type the password into the window underneath |
| `Alt+Enter` | copy the username |
| `Ctrl+L` | fill a login form — username, Tab, password, Enter |
| `Ctrl+O` | copy the one-time code (needs `pass-otp`) |
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

## The CLI

`bin/omapass` is a normal script and works on its own:

```bash
bin/omapass status                  # JSON: what is installed and set up
bin/omapass list                    # JSON: every entry
bin/omapass fields github.com/cs    # JSON: everything except the password
bin/omapass copy github.com/cs
bin/omapass type github.com/cs
bin/omapass login github.com/cs     # username, Tab, password, Enter
bin/omapass otp github.com/cs copy
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

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `PASSWORD_STORE_DIR` | `~/.password-store` | where the store lives |
| `OMAPASS_CLIP_TIME` | `45` | seconds before the clipboard is dropped |
| `OMAPASS_TYPE_DELAY` | `12` | ms between simulated keystrokes |
| `OMAPASS_TYPE_FOCUS_DELAY` | `0.2` | seconds to wait for focus before typing |
| `OMAPASS_KEYBIND` | `SUPER CTRL, K` | binding added by `install.sh` |

## Requirements

Omarchy 4, `pass`, `gpg`, `wl-clipboard`, `wtype`, and `jq` — all but `pass`
ship with Omarchy. `pass-otp` is optional and only needed for one-time codes.

## Development

The plugin is a plain directory; the install script links it, so edits in your
checkout are live:

```bash
omarchy-shell shell rescanPlugins          # reload plugin code
omarchy-shell shell toggle omapass         # open it
journalctl --user -f | grep omarchy-shell  # QML errors land here
qmllint -I /usr/share/omarchy/shell *.qml  # check before reloading
```

Hot reload on save only works for a real directory under
`~/.config/omarchy/plugins/`; through the symlink `install.sh` creates you need
the `rescanPlugins` call above.

## License

MIT.
