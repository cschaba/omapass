#!/bin/bash

# Cut a release: bump the version, move the changelog entry, tag, push.
#
# A maintainer tool, run by hand from a local checkout. It is not part of
# installing or running omapass and is not included in the release tarball, so
# no user ever executes it. It reads the remote — `git ls-remote`, to find out
# whether this checkout is behind — and writes to it only to push the release
# it has just built. It never fetches remote code, and nothing from the remote
# is ever checked out, merged or run.
#
# The tag is what triggers the packaging workflow, so everything that could fail
# is checked here first — a tag you have to delete and re-push is worse than a
# release that refuses to start.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/manifest.json"
CHANGELOG="$ROOT/CHANGELOG.md"
REMOTE="${OMAPASS_RELEASE_REMOTE:-origin}"
DRY_RUN=0

die() { echo "release: $*" >&2; exit 1; }
say() { echo "  $*"; }
run() { if (( DRY_RUN )); then echo "  would run: $*"; else "$@"; fi; }

current_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -1
}

# major.minor.patch, or an explicit version
next_version() {
  local current="$1" bump="$2"
  case "$bump" in
  major | minor | patch)
    local IFS=.
    read -r a b c <<<"$current"
    [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ && $c =~ ^[0-9]+$ ]] \
      || die "cannot bump '$current' — it is not major.minor.patch"
    case "$bump" in
    major) echo "$((a + 1)).0.0" ;;
    minor) echo "$a.$((b + 1)).0" ;;
    patch) echo "$a.$b.$((c + 1))" ;;
    esac
    ;;
  *)
    [[ $bump =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] \
      || die "'$bump' is not a version or one of major/minor/patch"
    echo "$bump"
    ;;
  esac
}

usage() {
  cat <<'USAGE'
scripts/release.sh <major|minor|patch|X.Y.Z> [--dry-run]

  Checks the tree, runs the tests, bumps manifest.json, moves the Unreleased
  section of CHANGELOG.md under the new version, commits, tags vX.Y.Z, and
  pushes. The tag is what makes GitHub build and publish the release.
USAGE
}

main() {
  local bump="${1:-}"
  [[ -n $bump ]] || { usage; exit 1; }
  [[ $bump == "-h" || $bump == "--help" ]] && { usage; exit 0; }
  shift
  [[ ${1:-} == "--dry-run" ]] && DRY_RUN=1

  # --- refuse to release from a state you would regret ---------------------

  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
  [[ -z $(git status --porcelain) ]] || die "working tree is dirty — commit or stash first"

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  [[ $branch == "main" ]] || die "on '$branch' — releases are cut from main"

  # Ask the remote where main points rather than fetching it. Same question —
  # is this checkout behind? — with nothing pulled into the repository and
  # nothing from the remote ever reachable by anything that runs. The old
  # `git fetch "$REMOTE" main` was the marketplace scanner's one finding
  # against omapass, and a finding is fail-closed there: no maintainer can
  # accept it. See "Publishing" in AGENTS.md.
  local remote_head
  remote_head=$(git ls-remote --heads "$REMOTE" main 2>/dev/null | awk 'NR == 1 { print $1 }')
  [[ -n $remote_head ]] || die "could not reach $REMOTE"

  if git cat-file -e "${remote_head}^{commit}" 2>/dev/null; then
    local behind
    behind=$(git rev-list --count "HEAD..$remote_head")
    [[ $behind -eq 0 ]] || die "$behind commit(s) behind $REMOTE/main — pull first"
  else
    # The remote tip is not in this checkout at all, so it is certainly ahead.
    die "$REMOTE/main is at ${remote_head:0:12}, which this checkout has never seen — pull first"
  fi

  local current next tag
  current=$(current_version)
  next=$(next_version "$current" "$bump")
  tag="v$next"

  git rev-parse "$tag" >/dev/null 2>&1 && die "tag $tag already exists"

  say "current  $current"
  say "next     $next  ($tag)"
  echo

  # --- everything that must hold before a tag exists ------------------------

  say "running tests"
  ./tests/smoke.sh >/dev/null 2>&1 || die "tests/smoke.sh failed — not releasing"
  ./tests/entries.sh >/dev/null 2>&1 || die "tests/entries.sh failed — not releasing"
  say "  tests pass"

  local f
  for f in bin/omapass bin/omapass-setup bin/omapass-reset lib/config.sh install.sh scripts/release.sh; do
    bash -n "$f" || die "$f has a syntax error"
  done
  say "  shell scripts parse"

  python3 -c "import json,sys; json.load(open('$MANIFEST'))" 2>/dev/null \
    || die "manifest.json is not valid JSON"
  say "  manifest.json is valid"

  if command -v qmllint >/dev/null 2>&1; then
    for f in "$ROOT"/*.qml; do
      qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml "$f" >/dev/null 2>&1 \
        || die "$(basename "$f") does not parse"
    done
    say "  qml parses"
  fi

  grep -q "^## \[Unreleased\]" "$CHANGELOG" || die "CHANGELOG.md has no [Unreleased] section"
  echo

  # --- write ---------------------------------------------------------------

  if (( DRY_RUN )); then
    say "dry run — stopping before any change"
    exit 0
  fi

  python3 - "$MANIFEST" "$next" <<'PY'
import json, sys, collections
path, version = sys.argv[1], sys.argv[2]
with open(path) as f:
    manifest = json.load(f, object_pairs_hook=collections.OrderedDict)
manifest["version"] = version
with open(path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY
  say "manifest.json -> $next"

  python3 - "$CHANGELOG" "$next" <<'PY'
import datetime, re, sys
path, version = sys.argv[1], sys.argv[2]
today = datetime.date.today().isoformat()
text = open(path).read()

# Everything under [Unreleased] becomes the new version's section.
text = text.replace(
    "## [Unreleased]\n",
    f"## [Unreleased]\n\n## [{version}] — {today}\n",
    1,
)
# Refresh the link definitions at the bottom.
text = re.sub(
    r"^\[Unreleased\]: .*$",
    f"[Unreleased]: https://github.com/cschaba/omapass/compare/v{version}...HEAD",
    text,
    count=1,
    flags=re.M,
)
if f"[{version}]: " not in text:
    text = text.rstrip("\n") + f"\n[{version}]: https://github.com/cschaba/omapass/releases/tag/v{version}\n"
open(path, "w").write(text)
PY
  say "CHANGELOG.md -> $next section"

  run git add "$MANIFEST" "$CHANGELOG"
  run git commit -q -m "Release $next"
  run git tag -a "$tag" -m "omapass $next"
  run git push "$REMOTE" main
  run git push "$REMOTE" "$tag"

  echo
  say "pushed $tag — GitHub is building the release now:"
  say "  https://github.com/cschaba/omapass/actions"
  say "  https://github.com/cschaba/omapass/releases/tag/$tag"
}

main "$@"
