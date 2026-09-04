# Working on omapass

Conventions for anyone — human or agent — making changes here. The reasoning
behind the code is in [DEVELOPMENT.md](DEVELOPMENT.md); this is about process.

## One branch per issue

**Work for an issue happens on its own branch, never directly on `main`.**

```bash
git checkout main && git pull
git checkout -b issue/18-folders     # issue/<number>-<short-slug>
```

`main` stays releasable. Half-finished work, an approach that turns out wrong,
a fix waiting on the reporter to confirm — none of it belongs on the branch
other people install from.

Merge to `main` when the change is complete and its tests pass:

```bash
git checkout main
git merge --no-ff issue/18-folders
git branch -d issue/18-folders
```

`--no-ff` keeps the branch visible in the history, so `git log` still shows
which commits belonged to which issue.

Two things stay on `main` directly: a released version's own bookkeeping
(`scripts/release.sh` commits there), and single-commit corrections to
documentation that no issue is tracking.

## One release per fixed issue

`scripts/release.sh patch` after merging. It runs the tests, bumps
`manifest.json`, moves the `CHANGELOG.md` entry, tags and pushes; the tag
publishes the release. Add the changelog entry under `[Unreleased]` as part of
the fix, not afterwards.

## Commits

Authored `Carsten <carsten@s10r.de>`, with a `Co-Authored-By: Claude` trailer
where that applies. Close issues with `Fixes #N` in the body. Say *why* the
change is what it is — the diff already shows what changed.

## Issues

Fix issues opened by the repository owner directly. For anyone else's,
evaluate it and hand back options rather than acting on your own judgement.

## Before you believe a test

**Restart the shell after changing any QML.** `omarchy-shell` loads a plugin's
QML once at startup and keeps it for the life of the process. Change a file and
`bin/omapass` goes current immediately while the windows do not — so a fix looks
like it did nothing. `bin/omapass doctor` now says when this has happened, and
`omarchy restart shell` fixes it. Three releases went out against #21 before
anyone noticed.

**Never test against a real password store.** Build a throwaway `GNUPGHOME` and
`PASSWORD_STORE_DIR`; `tests/entries.sh` shows the pattern. If you must touch a
real store, say so and clean up — it is usually a git repository, so additions
land in its history.

**Revert temporary overrides.** Forcing `fingerprint_available()` to return true
is the usual one. `grep -rn TEMPORARY` before committing.

## Keep the shortcut sheet true

**Change a key, add a feature, and update `HelpSheet.qml` in the same commit.**
The sheet is the only place a user finds out what the keys are, so a stale row
is worse than a missing one: a key that does nothing sends someone hunting for
a fault that is not there, and one that is documented on the wrong surface
sends them to the wrong window.

Three things go stale in different ways, so check all three:

- **The keys themselves.** A binding that exists and is not on the sheet is
  invisible; a row for a binding that no longer exists is a lie.
- **Where each one works.** The manager and the bar pulldown do not bind the
  same set. Anything the pulldown does not handle says **manager only** on its
  row, and `Ctrl+Q` and `Ctrl+S` were both wrong about this for two releases.
- **What the row claims it does.** `Ctrl+S` naming the git commands it runs is
  worth more than "sync", and it stops being worth anything the moment the
  commands change.

`tests/smoke.sh` holds the sheet to the code — every bound key appears on it,
and every key the pulldown does not bind is marked manager only. Both checks
read the QML rather than a list someone has to remember to edit, so they fail
on the commit that causes the drift rather than on the release that ships it.
Neither can tell whether the wording is *right*, which is the part that still
needs reading.

## Use the Omarchy API

**Omarchy already does most of this. Look before building.**

Reinventing a piece of it is how omapass ended up editing `shell.json` by hand
(#27) when `omarchy plugin enable` does the same job, correctly, including
placing the bar widget. The homemade version was more code, and wrong.

Where to look first:

| Need | Use |
|------|-----|
| Enable, disable, list, add or remove a plugin | `omarchy plugin …` |
| Put a widget on the bar, move it, set an option | `omarchy bar …` |
| Open, close or toggle a plugin surface | `omarchy-shell shell summon\|hide\|toggle <id> [payload]` |
| Call into a loaded plugin | `omarchy-shell shell call <id> <method> <arg>` |
| A plugin's own IPC | `IpcHandler` with an `ipcTarget`, as `Ui/Panel.qml` does |
| Desktop notification | `omarchy-notification-send` |
| Run something in a terminal | `omarchy-launch-floating-terminal-with-presentation` |
| Reload the shell after a QML change | `omarchy restart shell` |

And in QML, from `qs.Commons` and `qs.Ui`:

| Need | Use |
|------|-----|
| Colours, fonts, spacing, radii | `Color`, `Style`, `Border` — never a literal |
| A bar button with a popup | `Ui/Panel.qml`, `BarIconButton`, `KeyboardPanel` |
| Keyboard handling in a panel | `PanelKeyCatcher` |
| Text input, confirmation, dropdown | `TextField`, `ConfirmDialog`, `Dropdown` |
| Running a process | `Quickshell.Io.Process`, or `Util.execArgv` for a detached one |
| Authentication | `PamContext`, with the same services the lock screen uses |

`~/.local/share/omarchy/shell/plugins/README.md` documents the plugin contract,
and the first-party plugins beside it are worked examples — the clipboard picker
for an overlay, `panels/power` for a bar widget, `lock` for PAM.

Two habits follow from this. Read the first-party plugin that already solves
your problem before writing a line. And when something Omarchy provides does not
quite fit, say so in the commit — that is a much more interesting claim than it
looks, and usually wrong.

## Stay inside the plugin

**omapass never creates, edits or deletes a file outside its own directories.**

What is ours:

- the plugin directory, `~/.config/omarchy/plugins/cschaba.omapass`
- `~/.config/omapass/` — its config
- `~/.local/state/omapass/` — its log, backups and first-run marker
- the password store, and only through `pass`

Everything else belongs to the user, including `~/.config/hypr/bindings.lua` and
`~/.config/omarchy/shell.json`. Being careful about editing them — announcing
first, keeping a backup, touching only our own lines — is not the same as not
editing them, and a plugin that rewrites your compositor config is one you have
to trust twice.

Where something outside genuinely has to change, **detect it and print it**: the
exact line, or the exact command, and then stop. `install.sh` prints the
`o.bind` line for the keybinding and lets the user paste it.

Omarchy's own commands are the exception, because they are omarchy managing
omarchy's configuration and are what a user would type by hand:

```bash
omarchy plugin enable cschaba.omapass    # also places the bar widget
omarchy plugin disable cschaba.omapass
omarchy bar put cschaba.omapass
```

Prefer them over touching `shell.json`, which they own.

## Publishing

omapass is listed on the [Omarchy plugin marketplace][mp]. The listing points at
**the repository, not a release**, so a reviewer sees whatever is on `main` at
the moment they look. That is the sharper reason for the branch rule above:
`main` is the public face, not a workspace.

[mp]: https://github.com/omacom/omarchy-plugin-marketplace/issues/3086

### Promises already made

The submission form has a checklist, and it was ticked. Each item is a claim
about how omapass behaves, so a change that breaks one silently makes the
listing untrue:

- **"Does not overwrite user configuration without explicit consent."**
  omapass goes further than the checklist asks: it writes nothing outside its
  own directories at all. See *Stay inside the plugin* above. The easiest way to
  keep this claim true is to keep having nothing to declare.
- **"The repository is public and contains installation and removal
  instructions."** `uninstall.sh` has to keep working, and keep leaving the
  password store alone.
- **"Documented the licence and any external dependencies."** A new runtime
  dependency belongs in the README's Requirements table and in the startup
  requirements check, not only in the code that calls it.

### What the static scan reads

Every `.sh`, `.js`, `.mjs`, `.qml`, `.py`, `.rb`, `.pl`, `.lua`, `.yml`,
`.yaml`, `.toml`, `.desktop`, `.service`, `.sudoers`, `.bash`, `.fish`, `.zsh`
in the repository, plus extensionless files under `bin/` and `scripts/`, plus
the root README.

**Excluded:** anything under `tests/`, `docs/`, `.github/`, `spec/`, `specs/`,
`fixtures/`, `coverage/`, `node_modules/`.

So `bin/*`, `lib/config.sh`, `install.sh`, `uninstall.sh` and all the QML are
read; `tests/` and `docs/` are not. Worth knowing before adding anything that
shells out, invokes a package manager, or asks for `sudo`.

### Capabilities it will flag

These are detected and reported to the reviewer, and all of them are ours
already: `privilege` and `package-manager` (the guided setup offers to
`pacman -S` the dependencies), `installer` (the three scripts), and
`remote-build` (the `git clone` in the README). They are expected. A **new**
one appearing in a diff means the plugin started doing something categorically
different, and deserves a second look before it ships.

### Findings are fail-closed. Capabilities are not.

This distinction decides whether the listing can ever be published, and it is
worth knowing before writing anything that shells out.

**Capabilities are fine.** They produce a `review-required` outcome, which a
maintainer can accept. The four above have been accepted for plugins already
listed — `privilege`, `package-manager` and `installer` together on
`omavoice`, `remote-build` on others.

**A finding is not.** It produces `needs-fixes`, and `VERIFICATION.md` in the
marketplace repository is explicit that `needs-fixes` and findings "are never
eligible for maintainer verification and remain fail closed". No maintainer can
wave one through, however good the argument against it. Of the approved
listings sampled, every single one had an empty finding set.

omapass had one — `remote-git-execution-unpinned` on `scripts/release.sh`,
where `git fetch --quiet "$REMOTE" main` named a branch through a variable the
analyser could not resolve to a pinned SHA, and the later `./tests/smoke.sh`
read as an execution sink. It cost the submission a month of silence: the
maintainer applied `needs-fixes` and later removed `validated`, with no comment
either time, because the gate had already decided.

`release.sh` now asks `git ls-remote` where `main` points instead of fetching
it. Same question, nothing pulled into the repository. **Do not reintroduce a
fetch of a remote branch**, here or anywhere else that is scanned, and treat
any new finding as blocking rather than as something to explain on the issue.
The explanation is on #3086 and it changed nothing.

## Secrets

Two rules the whole design rests on, worth keeping when you extend it:

- A decrypted password never enters the long-lived shell process, and never
  appears in a command line. It goes from `gpg` to `wl-copy` or `wtype` inside
  a short-lived helper, over stdin.
- The debug log records what happened, never what it happened to — no
  passwords, no usernames, and no entry names, which are disclosure in their
  own right.

`DEVELOPMENT.md` has a recipe that re-checks the first of these with PATH shims.
