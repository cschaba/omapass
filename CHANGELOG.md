# Changelog

Notable changes per release. Dates are ISO. This project follows
[semantic versioning](https://semver.org): breaking changes to the config file,
the CLI surface, or the entry format bump the major.

## [Unreleased]

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

[Unreleased]: https://github.com/cschaba/omapass/compare/v0.1.14...HEAD
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
