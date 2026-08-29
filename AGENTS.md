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

[mp]: https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/3086

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

### One accepted finding

`remote-git-execution-unpinned` on `scripts/release.sh`. The analyser tracks
whether a git source is pinned to a 40-character SHA or is the plugin's own
repository; `git fetch --quiet "$REMOTE" main` uses a variable, so it cannot
tell, and the later `./tests/smoke.sh` reads as an execution sink.

It is a modelling gap rather than a risk — `scripts/` is not in the release
tarball, and nothing fetched is ever checked out or executed. The finding is
non-blocking and a maintainer can accept it. Do not contort `release.sh` to
silence it; the reasoning is recorded on the submission.

## Secrets

Two rules the whole design rests on, worth keeping when you extend it:

- A decrypted password never enters the long-lived shell process, and never
  appears in a command line. It goes from `gpg` to `wl-copy` or `wtype` inside
  a short-lived helper, over stdin.
- The debug log records what happened, never what it happened to — no
  passwords, no usernames, and no entry names, which are disclosure in their
  own right.

`DEVELOPMENT.md` has a recipe that re-checks the first of these with PATH shims.
