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

## Secrets

Two rules the whole design rests on, worth keeping when you extend it:

- A decrypted password never enters the long-lived shell process, and never
  appears in a command line. It goes from `gpg` to `wl-copy` or `wtype` inside
  a short-lived helper, over stdin.
- The debug log records what happened, never what it happened to — no
  passwords, no usernames, and no entry names, which are disclosure in their
  own right.

`DEVELOPMENT.md` has a recipe that re-checks the first of these with PATH shims.
