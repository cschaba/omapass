# Changelog

Notable changes per release. Dates are ISO. This project follows
[semantic versioning](https://semver.org): breaking changes to the config file,
the CLI surface, or the entry format bump the major.

## [Unreleased]

## [0.1.46] — 2026-09-04

### Added

- The `?` that opens the shortcut sheet is on every surface now, not only the
  manager's list. The two places you are most likely to be stuck — halfway
  through a form, or in the pulldown — were the two with no way to the sheet
  but a key you had to already know. `F1` works in the form as well. The
  pulldown has no room for the sheet, so both the key and the button open the
  manager with it already up. ([#32])

- The `?` sits in the top-right corner in the manager and the editor, rather
  than on the hint row at the bottom. That row is the busiest line in the app,
  and in the editor a third thing to aim at beside Cancel and Save is one too
  many. The entry count moves left to make room. The pulldown keeps its `?` at
  the bottom, next to `Manage…`, because its top row is the search field and
  its bottom row is short. ([#32])

  `Esc` is the reflex that closes a help window, and in the editor it is also
  the key that discards the draft. It only means the first of those while the
  sheet is up. ([#32])

### Changed

- `scripts/release.sh` asks `git ls-remote` where `main` points instead of
  running `git fetch`. It only ever wanted the answer to "is this checkout
  behind?", and it now gets it without pulling anything into the repository.
  That `git fetch` was the marketplace scanner's one finding against omapass
  (`remote-git-execution-unpinned`), and a finding is fail-closed there — no
  maintainer can accept one, which is why the submission sat for a month.

### Fixed

- Three rows on the shortcut sheet were not true. `Ctrl+Q` (scan a QR code) and
  `Ctrl+S` (sync) are bound in the manager and not in the bar pulldown, but
  neither said **manager only**, so the sheet sent you to the pulldown to press
  a key that was never there. And the sheet's own fallback for the open hotkey
  still read `Super + Shift + K`, the chord that changed in 0.1.45. Two tests
  now hold the sheet to the code: every key the pulldown does not bind has to
  be marked, and the fallback chord is derived from `lib/config.sh` rather than
  typed. ([#32], [#41])

- The shortcut sheet is readable again. It had no background of its own, over a
  list that nothing had told to get out of the way, so the two sets of text sat
  on top of each other. It paints its own background now and covers the card
  corner to corner — a view on top of the others, not a panel floating in one —
  and everything underneath goes dark while it is up. Those panes are hidden in
  place rather than removed, because a `Column` lays out only its visible
  children and dropping them would have pulled the footer to the top of the
  card. ([#32])

## [0.1.45] — 2026-08-31

### Changed

- The default hotkey is **`SUPER + ALT + P`**, was `SUPER + SHIFT + K`. Checked
  against a live Omarchy install rather than picked by feel: `SUPER + P`,
  `SUPER + SHIFT + P` and `SUPER + CTRL + P` are all taken, and `SUPER + ALT`
  is busy with 25 window and group bindings but not with `P`. Nothing breaks
  for anyone already installed — OmaPass has never written to `bindings.lua`,
  it prints the line for you to paste, so an existing binding keeps working.
  Re-running `install.sh` now says which chord it actually found and offers the
  new line rather than reporting "already there" and hiding the change. ([#41])

## [0.1.44] — 2026-08-31

### Added

- A shortcut sheet, on `F1` or the `?` in the bottom-right corner. OmaPass is
  keyboard-first, which is only a virtue while you can find out what the keys
  are — and the footer hints can only ever carry the handful that fit. The
  sheet covers both surfaces at once, says which rows are manager-only, and
  lists only what your machine can do: no one-time-code rows without
  `pass-otp`, no sync row without a git store. It also spells your configured
  hotkey the way a person says it rather than the way `keybind` writes it.
  `F1` in the bar pulldown opens the manager showing it. ([#32])

### Changed

- `F1` is the shortcut sheet rather than the About screen, which is the
  convention everywhere else. About moved onto the sheet, so it is one keypress
  further away and no harder to find. ([#32])

## [0.1.43] — 2026-08-31

### Fixed

- The OTP field accepts what sites and other password managers actually hand
  out. A bare secret is enough — spaces and lower case included — and a URI
  missing its label, such as `otpauth://totp?secret=…`, is repaired rather than
  refused. Both are then stored as a complete `otpauth://` line and shown in
  the field before saving. This is not just a looser check: `pass-otp`'s parser
  makes the label optional to match and then dies on the missing account name,
  so the URI in the report would have been unreadable by the very command that
  has to read it. `Ctrl+Q` QR enrolment refuses such a code up front instead of
  storing one that cannot be used. A word shorter than 16 characters is never
  taken for a secret, so a password pasted into the wrong field is not silently
  turned into a one-time code. ([#40])

## [0.1.42] — 2026-08-30

## [0.1.41] — 2026-08-30

### Changed

- The product is called **OmaPass**, matching the OmaIpsum/OmaNano family. The
  manifest's display name and description carry the new casing, and so does
  every place the name is written as prose: the README and DEVELOPMENT.md, the
  About screen's title and *Quit OmaPass*, the setup notices, and what
  `install.sh` and `uninstall.sh` print. Every identifier stays lowercase and
  unchanged — the plugin id `cschaba.omapass`, the `bin/omapass` command,
  `~/.config/omapass/`, the layer-shell namespace, the notification app name,
  the `omapass:` prefix on error output, and the `"omapass"` description on the
  Hyprland keybinding, which `install.sh` matches on to recognise its own
  binding.

## [0.1.40] — 2026-08-30

### Added

- The bar pulldown remembers your last search after you copy something from
  it, with the same entry still under the cursor — needing the username, then
  the password, then the one-time code used to mean typing the same search
  three times. The text comes back selected, so a new search replaces it
  rather than extending it. Closing the pulldown without copying anything
  clears it, and so does the vault re-locking: the filter is a fragment of an
  entry name and should not outlive the gate that decides who may see those.
  Bounded by the new `search-memory` setting (default 120 seconds, `0` to
  always start empty). ([#38])

## [0.1.39] — 2026-08-30

### Added

- The version number on the About screen (`F1`) is a link to the project on
  GitHub, with a tooltip that names the destination before you follow it. The
  homepage line at the bottom got the same tooltip, and both now open through
  the same helper the rest of omapass uses — so `http(s)` goes to Omarchy's
  browser launcher rather than straight to `xdg-open`. New CLI command
  `open-url`. ([#36])

### Fixed

- The password field no longer disappears when *generate* is ticked. It stays
  where it is, disabled and reading "generated when you save", so the form
  keeps its shape instead of reshuffling every time the box is touched — and
  the field the section is named after is actually in it. Clicking it switches
  generation off and puts the cursor there, since a field you cannot type into
  is an invitation with nothing behind it. ([#33])

### Added

- The README says that omapass was written with heavy use of AI, and how to
  check that against the history — every commit that changes anything carries
  a `Co-Authored-By: Claude` trailer. Worth stating plainly in a project that
  asks to hold your passwords, rather than leaving people to infer it. ([#35])

## [0.1.38] — 2026-08-30

### Added

- Closing omapass with an unsaved entry form open no longer throws the form
  away. Filling that form in usually means fetching a password out of another
  application, and reaching another application means closing this one — so
  the two halves of the job were in each other's way. Reopening brings the
  form back as it was. `Esc` and Cancel still discard, which is the difference
  between putting the form down and deciding against it. The draft is held in
  memory only, never written to disk, dropped on save, on cancel and whenever
  the vault re-locks, never restored while a fingerprint prompt is up, and
  bounded by the new `draft-timeout` setting (default 300 seconds, `0` to keep
  nothing). ([#37])

## [0.1.37] — 2026-08-29

### Fixed

- `Ctrl+Shift+U` never reached omapass: it is Unicode entry in IBus and fcitx,
  which claim it before the application sees it — it typed `U+` into the search
  field instead. Copying a field has moved to `Alt`, which input methods leave
  alone: `Alt+U` copies the URL and `Alt+N` copies the name, replacing
  `Ctrl+Shift+U` and `Ctrl+Shift+C`. `Ctrl+U` still opens the URL, so `Alt`
  copies a field and `Ctrl` acts on one. ([#31])
- Actions that fail now say so. A detached action had nowhere to put an error —
  nothing reads its stderr, and the surface that started it has already closed
  — so copying the username of an entry that has no username field looked
  exactly like a key that did nothing. Those failures raise a notification.
  ([#31])

## [0.1.36] — 2026-08-29

### Fixed

- The fingerprint gate no longer spills out of the bar pulldown when the
  reader fails. The pulldown was giving it a fixed height, which could not be
  right for both "touch the reader" and a password prompt carrying a failure
  message and the way past it — so the state that needs the panel most was the
  one where the title sat above the panel edge and the escape hatch ran into
  the footer. The gate now reports how tall it needs to be, and its opt-out
  hint is shortened on compact surfaces instead of wrapping into four lines.
  ([#30])

## [0.1.35] — 2026-08-29

### Changed

- The welcome screen opens by itself, a moment after the shell loads omapass,
  instead of waiting to be found in an overlay a new user has no way to open
  yet. It comes from the plugin rather than from `install.sh`, so it works
  whichever way omapass was installed — `omarchy plugin add` never runs that
  script. Once dismissed it does not return; installs with a fingerprint
  unlock are left alone, so nobody is met by a scan prompt seconds after
  logging in. `install.sh` also clears the "seen" marker on a genuine first
  install, so removing omapass and putting it back greets you again. ([#25])

## [0.1.34] — 2026-08-29

### Changed

- The README says how to update an installed copy: `omarchy plugin update`,
  then `omarchy restart shell`, then `bin/omapass doctor` to confirm the
  windows are as new as the files. `rescanPlugins` — which `plugin update`
  runs on its own — does not re-read the QML of a plugin that is already
  loaded, so the restart is not optional.

## [0.1.33] — 2026-08-29

### Changed

- The README no longer opens with an "early software, expect rough edges"
  warning. What was worth keeping from it — how to try omapass against a
  throwaway store — is now a short section next to the install steps.

## [0.1.32] — 2026-08-29

### Added

- Copy the entry's name (`Ctrl+Shift+C`), copy its URL (`Ctrl+Shift+U`) and
  open its URL (`Ctrl+U`) — from the bar pulldown as well as the overlay, with
  clickable hints along the bottom of both. `http`/`https` go through
  Omarchy's own browser launcher and everything else through `xdg-open`, so
  `ssh`, `sftp`, `ftp` and the rest land wherever the desktop already sends
  them. The name and the URL are copied as ordinary text, not as secrets:
  neither expires. New CLI commands `copy-name`, `copy-url` and `open`. ([#29])

## [0.1.31] — 2026-08-29

### Changed

- The README shows screenshots of the running plugin instead of hand-drawn
  ASCII sketches, which had already drifted from the real UI. ([#28])

## [0.1.30] — 2026-08-29

### Changed

- `bar-section` defaults to `right` explicitly, rather than deferring to the
  manifest and leaving the answer somewhere the reader has to go and find.
  Behaviour is unchanged — it already placed on the right — but `omapass config`
  now says so, and an invalid value falls back to right instead of nothing.
  ([#26])

## [0.1.29] — 2026-08-29

### Added

- `bar-section` in the config chooses where the bar icon is placed on the first
  install — `left`, `center` or `right`. It is an initial placement only: once
  the widget is on the bar, Omarchy owns where it sits, and re-running the
  installer no longer moves it. ([#26])

### Changed

- The README shows `omarchy plugin add … --enable` without `--yes`, since
  `--yes` answers Omarchy's "which bar section?" prompt for you. ([#26])

## [0.1.28] — 2026-08-29

### Changed

- omapass no longer writes anything outside its own directories. `install.sh`
  registers the plugin with `omarchy plugin enable`, which places the bar widget
  too, and **prints** the keybinding line for you to add rather than editing
  `bindings.lua`. `uninstall.sh` prints the line to remove. Neither touches
  `shell.json` directly any more, and the `.omapass-backup` copies are no longer
  needed — nothing of yours is written to back up. ([#27])

## [0.1.27] — 2026-08-29

### Fixed

- The keybinding never worked. `install.sh` wrote it to
  `~/.config/hypr/bindings.conf`, and Omarchy 4 runs Hyprland with
  `configProvider: lua` — so that file, and everything `hyprland.conf` sources,
  is never read. It goes to `~/.config/hypr/bindings.lua` now, applied
  immediately, and installing removes any stale entry left in the old file.
  ([#24])

### Added

- `install.sh` checks Hyprland's live binding list before writing, and names
  what already holds the chord. It sees bindings from any source, not just
  Omarchy's own. ([#24])

## [0.1.26] — 2026-08-29

### Changed

- `Ctrl+N` in the bar pulldown opens the new-entry form directly, and `Ctrl+E`
  opens the editor on the selected entry. Both used to land on the manager's
  list, leaving the thing you asked for another keystroke away. ([#22])

## [0.1.25] — 2026-08-29

### Fixed

- `ui:` log lines are numbered. Each event is written by its own process, so
  four fired from one function reached the file in whatever order the kernel
  chose — and a trace whose order cannot be trusted cannot answer "which step
  was last", which is the only thing it is for. Timestamps carry milliseconds
  now too. ([#21])

## [0.1.24] — 2026-08-29

### Added

- `omapass doctor` warns when the running shell is older than the interface
  files on disk. The shell loads omapass's QML once at startup and keeps it for
  the life of the process, so updating gives you a current command line and
  stale windows — indistinguishable from a fix that did not work. ([#21])

## [0.1.23] — 2026-08-28

### Added

- `omapass doctor`: which copy of omapass is running, its version, where the
  config, store and log are, and whether logging is on. It warns when more than
  one installed directory claims the plugin id — installing twice (`install.sh`
  and later `omarchy plugin add`) leaves omarchy loading one of them with
  nothing on screen to say which. ([#21])
- The About screen says when the debug log is off, and how to turn it on,
  rather than only showing a link when it is already on. ([#21])

## [0.1.22] — 2026-08-28

### Added

- The debug log now records the UI's own steps, not just the commands it runs.
  A save that fails before reaching the helper — the editor refusing it, or a
  check stopping it — previously left no trace at all, which made it
  undiagnosable from a log. Each step names itself and nothing else: no entry
  names, no values. ([#21])

## [0.1.21] — 2026-08-28

### Fixed

- `work / aws` — a folder path typed the way people write paths — was rejected
  for the spaces, and the refusal was small grey text in the editor's footer.
  Between them that reads as the save doing nothing. Whitespace around a `/` is
  tidied away now, and a refused save is shown in full size with a warning
  mark. ([#21])

## [0.1.20] — 2026-08-28

### Security

- Saving a new entry over an existing name destroyed the old password without a
  word, and renaming onto an existing name destroyed the target the same way.
  Both used `pass`'s force flag. Creating now refuses when the name is taken,
  renaming refuses when the destination is, and only editing replaces. ([#21])

### Fixed

- A refused save reported nothing: the reload that followed cleared the error
  before it could be read. Errors are now cleared deliberately rather than as a
  side effect, and the helper's own message is shown instead of a generic one.
  ([#21])
- The editor catches a name clash before saving, so it stays open with the name
  selected rather than closing on a save the store will reject. ([#21])

### Added

- `tests/entries.sh`: a round-trip matrix over the editor's data path — fields
  present and absent, spaces everywhere, `http`/`https`/`ftp`/`ssh` URLs,
  none/one/many extra lines, and conflict handling. Runs in CI and before every
  release. ([#21])

## [0.1.19] — 2026-08-28

### Added

- A real quit. **Quit omapass** on the About screen, or `bin/omapass quit`,
  disables the plugin: the bar icon goes, the hotkey stops responding, and the
  shell unloads it. Nothing is uninstalled, and both the confirmation and the
  command print how to start it again. ([#20])

## [0.1.18] — 2026-08-28

### Fixed

- A new entry was filed under the folder of whichever entry happened to be
  selected. `Ctrl+N` pre-filled that folder and left the cursor after it, so
  typing `newsite.example` stored `github.com/newsite.example` — the save
  worked, but the entry was not where anyone would look for it. The name now
  starts empty. ([#21])

### Changed

- After saving, the list selects the entry that was written, so it is visibly
  there rather than something to go looking for. ([#21])

## [0.1.17] — 2026-08-28

### Added

- An opt-in debug log (`log = on`), written so it can be pasted into a bug
  report unread: it records which operation ran and how it ended, and never
  passwords, usernames, URLs or entry names. Entries appear as a per-run salted
  digest, so lines can be correlated without disclosing what they refer to. The
  file is `0600` and rotates at `log-max-kb`. The About screen offers a link to
  it while logging is on. ([#19])

## [0.1.16] — 2026-08-28

### Security

- Entry names could put files where they did not belong. A name beginning with a
  dot was accepted, so `.git/hooks/pre-commit` wrote inside the store's own git
  repository, and control characters produced entries that could not be referred
  to again. Names are now checked for dot-prefixed parts, control characters,
  empty folders and trailing space or dot. ([#17])
- A newline pasted into any editor field was written straight into the entry. A
  `pass` entry is line-oriented, so a newline in the username box became a new
  line in the file — enough to attach an unwanted `otpauth://` secret without it
  appearing in the field it was pasted into. Field values are now stripped of
  newlines and control characters, and the OTP box only accepts an `otpauth://`
  URI. ([#17])

### Changed

- The editor says why a name is rejected instead of showing one generic
  message. ([#17])

## [0.1.15] — 2026-08-28

### Fixed

- Only the first password could be saved. Every save after it silently stored
  nothing — no error, no log line, nothing in the store. The helper's stdin is
  closed after writing, to tell `pass insert -m` the entry is complete, and the
  flag controlling it was never turned back on, so later saves handed `pass` no
  input at all. ([#16])

## [0.1.14] — 2026-08-28

### Changed

- `install.sh` names the two files it edits before it edits them, keeps a
  `.omapass-backup` copy of each, and refuses to rewrite a `shell.json` it
  cannot parse. It only ever adds or removes its own entries. ([#12])

## [0.1.13] — 2026-08-28

### Changed

- The README now says how `omapass-reset` and `uninstall.sh` differ: one removes
  your passwords, the other removes the app. They were documented 270 lines
  apart with neither mentioning the other, so "reset" read as though it should
  have uninstalled everything. Both scripts say it in their own help and output
  too, which is where the question actually gets asked. ([#15])

## [0.1.12] — 2026-08-28

### Changed

- The plugin id is now `cschaba.omapass`. The Omarchy plugin marketplace expects
  a namespaced id, and a bare one risks colliding with anybody else's. Running
  `./install.sh` migrates an existing install — the plugin directory, the bar
  entry, the enabled-plugins list and the keybinding all move across. ([#12])

### Added

- `uninstall.sh`, which removes the plugin, its bar widget and its keybinding,
  and leaves your password store and GPG key alone. `--purge` also removes
  omapass's own config and state. ([#12])

## [0.1.11] — 2026-08-28

### Added

- A welcome screen on first run, showing the version, what the three keys worth
  knowing do, and a link to the project. The same panel is the About screen
  afterwards, on `F1`. ([#14])

## [0.1.10] — 2026-08-28

### Changed

- The README is written for someone meeting omapass for the first time, rather
  than describing how it came to be the way it is. Wording that only made sense
  if you had followed the development is gone, along with a warning that
  described the state of testing on one particular afternoon. ([#13])

## [0.1.9] — 2026-08-28

### Fixed

- Falling back from the fingerprint reader to the password took about ten
  touches instead of three. The failure counter counts whole fprintd
  conversations, and fprintd retries roughly three times inside each one, so
  allowing three conversations meant nine or ten touches — long enough to read
  as the app being stuck rather than falling back. One conversation is now
  enough, which lands on the usual three-tries convention, and
  `fingerprint-retries` makes it tunable without a release. Found on real
  hardware. ([#10])

## [0.1.8] — 2026-08-28

### Fixed

- The editor accepted input of unbounded length, and its "Other lines" box hid
  everything past the third line with no way to scroll to it. Each field now has
  a limit, a counter appears as that limit comes into view, and the notes box
  scrolls. The name is validated against what a filesystem will actually take —
  255 bytes per path segment — so an over-long name is refused by name rather
  than failing later as a write error. ([#9])

## [0.1.7] — 2026-08-28

### Added

- Right-clicking the bar icon opens the full manager directly, rather than
  going through the pulldown and its "Manage…" link. The tooltip says so.
  ([#7])

## [0.1.6] — 2026-08-28

### Fixed

- An unreachable fingerprint reader trapped you at the gate. It retried forever
  and the only way out was noticing a link. The gate now gives up on its own —
  after two device errors, or three unrecognised fingers — and hands over to the
  password prompt saying why. Switching back to the reader resets that, and when
  no password service exists it says so rather than offering a door onto a wall.
  ([#8])

## [0.1.5] — 2026-08-28

### Added

- The pulldown offers `^O otp` when the selected entry actually carries a TOTP
  secret. It only knows that once gpg-agent is already warm — the same rule the
  overlay follows, so arrowing through a list never triggers a pinentry prompt
  just to draw a hint. ([#5])

## [0.1.4] — 2026-08-28

### Added

- The key hints along the bottom of the overlay and the pulldown are clickable.
  Reading "^L fill login" and not being able to click it is a small papercut
  that repeats every time. ([#3])

## [0.1.3] — 2026-08-28

### Added

- The fingerprint gate offers "Use password instead", switchable with `Tab`.
  It authenticates against `omarchy-lock-password`, the same PAM service the
  Omarchy lock screen uses — a real check rather than a way around the gate,
  which would have made it decoration. ([#6])

## [0.1.2] — 2026-08-28

### Changed

- The default hotkey is `SUPER + SHIFT + K`. `SUPER + CTRL + K` was already
  bound by Omarchy itself, so the old default could never have worked. The
  hotkey is a `keybind` setting in the config file now, and re-running
  `install.sh` moves the binding rather than adding a second one. ([#4])

## [0.1.1] — 2026-08-28

### Fixed

- Setup printed `probe: unbound variable` after a successful run. A `RETURN`
  trap set inside a function stays armed for its caller, so cleanup fired a
  second time once the variable was out of scope. ([#2])

## [0.1.0] — 2026-08-28

First release. Under development and largely untested — see the warning at the
top of the README.

### Added

- Full-screen overlay: search, copy, type, fill-login, reveal, and a detail pane
  that does not decrypt until gpg-agent is already warm.
- Bar widget with a search pulldown for the quick path.
- Create, edit, generate, rename and delete entries, so the `pass` CLI is
  optional.
- One-time codes via `pass-otp`: copy, type, and QR enrolment that reads the
  code off the screen without the image touching disk.
- Fingerprint unlock in front of the vault when a finger is enrolled, using
  Omarchy's own PAM service.
- Guided first-run setup, and a startup check of all eight requirements that
  shows the exact command fixing each missing one.
- `omapass-reset` for exercising the setup flow repeatedly, backing up the store
  and the GPG key before it removes either.
- A config file at `~/.config/omapass/config`.
- `tests/smoke.sh`.

### Security

- Copy, type, login and OTP never bring a secret into the long-lived shell
  process; the helper pipes it from gpg straight to `wl-copy` or `wtype`.
- Secrets travel over stdin and in shell variables, never in argv.
- The clipboard is marked sensitive, so Omarchy's clipboard manager will not
  record it, and the selection is dropped after a timeout.

[Unreleased]: https://github.com/cschaba/omapass/compare/v0.1.46...HEAD
[0.1.0]: https://github.com/cschaba/omapass/releases/tag/v0.1.0
[#2]: https://github.com/cschaba/omapass/issues/2
[0.1.1]: https://github.com/cschaba/omapass/releases/tag/v0.1.1
[#4]: https://github.com/cschaba/omapass/issues/4
[0.1.2]: https://github.com/cschaba/omapass/releases/tag/v0.1.2
[#6]: https://github.com/cschaba/omapass/issues/6
[0.1.3]: https://github.com/cschaba/omapass/releases/tag/v0.1.3
[#3]: https://github.com/cschaba/omapass/issues/3
[0.1.4]: https://github.com/cschaba/omapass/releases/tag/v0.1.4
[#5]: https://github.com/cschaba/omapass/issues/5
[0.1.5]: https://github.com/cschaba/omapass/releases/tag/v0.1.5
[#8]: https://github.com/cschaba/omapass/issues/8
[0.1.6]: https://github.com/cschaba/omapass/releases/tag/v0.1.6
[#7]: https://github.com/cschaba/omapass/issues/7
[0.1.7]: https://github.com/cschaba/omapass/releases/tag/v0.1.7
[#9]: https://github.com/cschaba/omapass/issues/9
[0.1.8]: https://github.com/cschaba/omapass/releases/tag/v0.1.8
[#10]: https://github.com/cschaba/omapass/issues/10
[0.1.9]: https://github.com/cschaba/omapass/releases/tag/v0.1.9
[#13]: https://github.com/cschaba/omapass/issues/13
[0.1.10]: https://github.com/cschaba/omapass/releases/tag/v0.1.10
[#14]: https://github.com/cschaba/omapass/issues/14
[0.1.11]: https://github.com/cschaba/omapass/releases/tag/v0.1.11
[#12]: https://github.com/cschaba/omapass/issues/12
[0.1.12]: https://github.com/cschaba/omapass/releases/tag/v0.1.12
[#15]: https://github.com/cschaba/omapass/issues/15
[0.1.13]: https://github.com/cschaba/omapass/releases/tag/v0.1.13
[0.1.14]: https://github.com/cschaba/omapass/releases/tag/v0.1.14
[#16]: https://github.com/cschaba/omapass/issues/16
[0.1.15]: https://github.com/cschaba/omapass/releases/tag/v0.1.15
[#17]: https://github.com/cschaba/omapass/issues/17
[0.1.16]: https://github.com/cschaba/omapass/releases/tag/v0.1.16
[#19]: https://github.com/cschaba/omapass/issues/19
[0.1.17]: https://github.com/cschaba/omapass/releases/tag/v0.1.17
[#21]: https://github.com/cschaba/omapass/issues/21
[0.1.18]: https://github.com/cschaba/omapass/releases/tag/v0.1.18
[#20]: https://github.com/cschaba/omapass/issues/20
[0.1.19]: https://github.com/cschaba/omapass/releases/tag/v0.1.19
[0.1.20]: https://github.com/cschaba/omapass/releases/tag/v0.1.20
[0.1.21]: https://github.com/cschaba/omapass/releases/tag/v0.1.21
[0.1.22]: https://github.com/cschaba/omapass/releases/tag/v0.1.22
[0.1.23]: https://github.com/cschaba/omapass/releases/tag/v0.1.23
[0.1.24]: https://github.com/cschaba/omapass/releases/tag/v0.1.24
[0.1.25]: https://github.com/cschaba/omapass/releases/tag/v0.1.25
[#22]: https://github.com/cschaba/omapass/issues/22
[0.1.26]: https://github.com/cschaba/omapass/releases/tag/v0.1.26
[#24]: https://github.com/cschaba/omapass/issues/24
[0.1.27]: https://github.com/cschaba/omapass/releases/tag/v0.1.27
[#27]: https://github.com/cschaba/omapass/issues/27
[0.1.28]: https://github.com/cschaba/omapass/releases/tag/v0.1.28
[#26]: https://github.com/cschaba/omapass/issues/26
[#28]: https://github.com/cschaba/omapass/issues/28
[#25]: https://github.com/cschaba/omapass/issues/25
[#29]: https://github.com/cschaba/omapass/issues/29
[#30]: https://github.com/cschaba/omapass/issues/30
[#31]: https://github.com/cschaba/omapass/issues/31
[#32]: https://github.com/cschaba/omapass/issues/32
[#33]: https://github.com/cschaba/omapass/issues/33
[#35]: https://github.com/cschaba/omapass/issues/35
[#36]: https://github.com/cschaba/omapass/issues/36
[#38]: https://github.com/cschaba/omapass/issues/38
[#40]: https://github.com/cschaba/omapass/issues/40
[#41]: https://github.com/cschaba/omapass/issues/41
[#37]: https://github.com/cschaba/omapass/issues/37
[0.1.29]: https://github.com/cschaba/omapass/releases/tag/v0.1.29
[0.1.30]: https://github.com/cschaba/omapass/releases/tag/v0.1.30
[0.1.31]: https://github.com/cschaba/omapass/releases/tag/v0.1.31
[0.1.32]: https://github.com/cschaba/omapass/releases/tag/v0.1.32
[0.1.33]: https://github.com/cschaba/omapass/releases/tag/v0.1.33
[0.1.34]: https://github.com/cschaba/omapass/releases/tag/v0.1.34
[0.1.35]: https://github.com/cschaba/omapass/releases/tag/v0.1.35
[0.1.36]: https://github.com/cschaba/omapass/releases/tag/v0.1.36
[0.1.37]: https://github.com/cschaba/omapass/releases/tag/v0.1.37
[0.1.38]: https://github.com/cschaba/omapass/releases/tag/v0.1.38
[0.1.39]: https://github.com/cschaba/omapass/releases/tag/v0.1.39
[0.1.40]: https://github.com/cschaba/omapass/releases/tag/v0.1.40
[0.1.41]: https://github.com/cschaba/omapass/releases/tag/v0.1.41
[0.1.42]: https://github.com/cschaba/omapass/releases/tag/v0.1.42
[0.1.43]: https://github.com/cschaba/omapass/releases/tag/v0.1.43
[0.1.44]: https://github.com/cschaba/omapass/releases/tag/v0.1.44
[0.1.45]: https://github.com/cschaba/omapass/releases/tag/v0.1.45
[0.1.46]: https://github.com/cschaba/omapass/releases/tag/v0.1.46
