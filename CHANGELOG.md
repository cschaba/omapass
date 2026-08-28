# Changelog

Notable changes per release. Dates are ISO. This project follows
[semantic versioning](https://semver.org): breaking changes to the config file,
the CLI surface, or the entry format bump the major.

## [Unreleased]

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

[Unreleased]: https://github.com/cschaba/omapass/compare/v0.1.2...HEAD
[0.1.0]: https://github.com/cschaba/omapass/releases/tag/v0.1.0
[#2]: https://github.com/cschaba/omapass/issues/2
[0.1.1]: https://github.com/cschaba/omapass/releases/tag/v0.1.1
[#4]: https://github.com/cschaba/omapass/issues/4
[0.1.2]: https://github.com/cschaba/omapass/releases/tag/v0.1.2
