#!/bin/bash

# Smoke test for the omapass CLI. Builds a throwaway GPG home and store, so it
# never touches a real one, and puts them back on the way out.
#
# It exists because `unlocked` was dispatched to a function that had been
# deleted, and nothing noticed for two releases: bash only complains when the
# branch is actually taken.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMAPASS="$ROOT/bin/omapass"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (got '$2', wanted '$3')"; fi; }

echo "omapass smoke test"
echo

# --- every dispatched subcommand must resolve to something that exists -------

echo "dispatcher"
while read -r name; do
  [[ -n $name ]] || continue
  if grep -qE "^${name}\(\) \{" "$OMAPASS" || declare -F "$name" >/dev/null; then
    ok "$name is defined"
  else
    bad "$name is dispatched but never defined"
  fi
done < <(grep -oE '\bcmd_[a-z_]+' "$OMAPASS" | sort -u)

# fingerprint_available is called from the dispatcher without a cmd_ prefix
grep -qE '^fingerprint_available\(\) \{' "$OMAPASS" \
  && ok "fingerprint_available is defined" \
  || bad "fingerprint_available is missing"

echo

# --- behaviour, against a store built for the occasion ----------------------

export GNUPGHOME="$TMP/gnupg"
export PASSWORD_STORE_DIR="$TMP/store"
export OMAPASS_CONFIG="$TMP/config"
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"

echo "fixture"
if gpg --batch --quiet --passphrase '' --quick-generate-key \
     "omapass smoke <smoke@example.invalid>" default default never 2>/dev/null; then
  ok "throwaway key created"
else
  bad "could not create a key — stopping"; exit 1
fi
FPR=$(gpg --list-secret-keys --with-colons | awk -F: '$1=="fpr"{print $10; exit}')
pass init "$FPR" >/dev/null 2>&1 && ok "store initialised" || bad "pass init failed"

printf 'hunter2\nlogin: someone\nurl: https://example.com\notpauth://totp/S:me?secret=JBSWY3DPEHPK3PXP\nfree text\n' \
  | "$OMAPASS" insert smoke/full >/dev/null 2>&1
printf 'plain\n' | "$OMAPASS" insert smoke/bare >/dev/null 2>&1
echo

echo "reads"
check "list finds both entries" \
  "$("$OMAPASS" list | grep -c '"path"')" "2"
check "reveal returns the password" \
  "$("$OMAPASS" reveal smoke/full)" "hunter2"
check "body keeps every line" \
  "$("$OMAPASS" body smoke/full | wc -l)" "5"
check "fields hides the password" \
  "$("$OMAPASS" fields smoke/full | grep -c hunter2)" "0"
check "fields reports the otp flag" \
  "$("$OMAPASS" fields smoke/full | tr -d ' \n' | grep -c '"otp":true')" "1"
check "unlocked returns json" \
  "$("$OMAPASS" unlocked | grep -c unlocked)" "1"
check "status parses as json" \
  "$("$OMAPASS" status | python3 -c 'import sys,json;json.load(sys.stdin);print("y")' 2>/dev/null)" "y"
check "config parses as json" \
  "$("$OMAPASS" config | python3 -c 'import sys,json;json.load(sys.stdin);print("y")' 2>/dev/null)" "y"
echo

echo "writes"
"$OMAPASS" generate smoke/gen 20 no >/dev/null 2>&1
check "generate makes the right length" "$("$OMAPASS" reveal smoke/gen | wc -c)" "21"
check "generate honours no-symbols" \
  "$("$OMAPASS" reveal smoke/gen | grep -cE '^[A-Za-z0-9]+$')" "1"
"$OMAPASS" rename smoke/gen smoke/renamed >/dev/null 2>&1
check "rename moves the entry" "$("$OMAPASS" list | grep -c 'smoke/renamed')" "1"
"$OMAPASS" remove smoke/renamed >/dev/null 2>&1
check "remove deletes it" "$("$OMAPASS" list | grep -c 'smoke/renamed')" "0"
echo

echo "input handling"
check "rejects a leading dash" \
  "$("$OMAPASS" reveal -f 2>&1 | grep -c "may not start with")" "1"
check "rejects path traversal" \
  "$("$OMAPASS" reveal ../escape 2>&1 | grep -c "may not contain")" "1"
check "rejects an absolute path" \
  "$("$OMAPASS" reveal /etc/passwd 2>&1 | grep -c "must be relative")" "1"
check "rejects writing into the store's .git" \
  "$("$OMAPASS" reveal ".git/hooks/pre-commit" 2>&1 | grep -c "may not start with")" "1"
check "rejects a dotfile entry" \
  "$("$OMAPASS" reveal ".gpg-id" 2>&1 | grep -c "may not start with")" "1"
check "rejects a control character in a name" \
  "$("$OMAPASS" reveal "$(printf 'tab\there')" 2>&1 | grep -c "control characters")" "1"
check "rejects an empty path segment" \
  "$("$OMAPASS" reveal "a//b" 2>&1 | grep -c "empty path segment")" "1"
check "rejects a trailing dot" \
  "$("$OMAPASS" reveal "trailing." 2>&1 | grep -c "space or dot")" "1"
check "still accepts folders" \
  "$("$OMAPASS" reveal "github.com/nobody" 2>&1 | grep -c "no such entry")" "1"
check "still accepts a dollar sign" \
  "$("$OMAPASS" reveal 'dollar$sign' 2>&1 | grep -c "no such entry")" "1"
check "rejects an over-long name segment" \
  "$("$OMAPASS" reveal "$(printf 'a%.0s' $(seq 1 300))" 2>&1 | grep -c "too long")" "1"
check "accepts a 255-byte segment" \
  "$("$OMAPASS" reveal "$(printf 'b%.0s' $(seq 1 255))" 2>&1 | grep -c "too long")" "0"
check "reports a missing entry" \
  "$("$OMAPASS" reveal nope/nothing 2>&1 | grep -c "no such entry")" "1"
echo

echo "config"
printf 'clip-time = 7\nbogus-key = 1\npulldown-rows = nope\n' > "$OMAPASS_CONFIG"
check "reads a value from the file" \
  "$("$OMAPASS" config | python3 -c 'import sys,json;print(json.load(sys.stdin)["clipTime"])')" "7"
check "falls back on a bad number" \
  "$("$OMAPASS" config 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["pulldownRows"])')" "7"
check "warns about an unknown key" \
  "$("$OMAPASS" config 2>&1 >/dev/null | grep -c "unknown setting")" "1"
check "fingerprint-retries has a default" \
  "$("$OMAPASS" config 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["fingerprintRetries"])')" "1"
check "environment beats the file" \
  "$(OMAPASS_CLIP_TIME=99 "$OMAPASS" config 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["clipTime"])')" "99"
echo

echo "field sanitation"
if command -v node >/dev/null 2>&1; then
  js_check() {
    local label="$1" expr="$2" want="$3"
    check "$label" "$(node -e "
      let src = require('fs').readFileSync('$ROOT/PassStore.js','utf8').replace('.pragma library','');
      eval(src);
      // String(): node colourises bare numbers and booleans, which the
      // comparison below would then never match.
      process.stdout.write(String($expr));
    " 2>/dev/null)" "$want"
  }
  js_check "a newline cannot inject a line" \
    "composeBody('pw',[{key:'login',value:'bob\notpauth://totp/EVIL'}],'').trim().split('\n').length" "2"
  js_check "a bogus otp value is dropped" \
    "composeBody('pw',[],'not-a-uri').trim().split('\n').length" "1"
  js_check "password punctuation survives" \
    "JSON.stringify(composeBody('a\$b#c',[],'').split('\n')[0])" '"a$b#c"'
  js_check "dotted folder rejected" \
    "nameProblem('.git/x') !== ''" "true"
  js_check "ordinary folder accepted" \
    "nameProblem('github.com/me') === ''" "true"
else
  ok "node unavailable — skipped the PassStore.js checks"
fi
echo

echo "release plumbing"
MANIFEST_VERSION=$(python3 -c "import json;print(json.load(open('$ROOT/manifest.json'))['version'])")
check "welcomed reports json" \
  "$("$OMAPASS" welcomed | grep -c welcomed)" "1"
check "status carries name and homepage" \
  "$("$OMAPASS" status | python3 -c 'import sys,json;d=json.load(sys.stdin);print(bool(d["name"] and d["homepage"]))')" "True"
check "version command matches the manifest" \
  "$("$OMAPASS" version)" "omapass $MANIFEST_VERSION"
check "status reports the same version" \
  "$("$OMAPASS" status | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])')" "$MANIFEST_VERSION"
# insertProc closes stdin on started() to signal EOF, and the property stays
# false. If write() stops re-arming it, every save after the first silently
# stores nothing — which shipped once. A display is needed to test it for real,
# so guard the line itself.
check "write() re-arms stdin before each insert" \
  "$(python3 -c "
import re
src = open('$ROOT/PassService.qml').read()
body = re.search(r'function write\(payload\) \{.*?\n  \}', src, re.S).group(0)
print('stdinEnabled = true' in body and 'running = true' in body)")" "True"
check "plugin id is namespaced" \
  "$(python3 -c "import json;print('.' in json.load(open('$ROOT/manifest.json'))['id'])")" "True"
check "manifest has the marketplace fields" \
  "$(python3 -c "
import json
m = json.load(open('$ROOT/manifest.json'))
need = ['schemaVersion','id','name','version','author','description','kinds','entryPoints']
print(all(m.get(k) for k in need))")" "True"
check "uninstall script is executable" \
  "$([[ -x "$ROOT/uninstall.sh" ]] && echo yes || echo no)" "yes"
check "manifest version is semver" \
  "$(python3 -c "import re;print(bool(re.fullmatch(r'\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?', '$MANIFEST_VERSION')))")" "True"
check "changelog has a section for it" \
  "$(grep -c "^## \[$MANIFEST_VERSION\]" "$ROOT/CHANGELOG.md")" "1"
check "changelog keeps an Unreleased section" \
  "$(grep -c '^## \[Unreleased\]' "$ROOT/CHANGELOG.md")" "1"
for ep in $(python3 -c "import json;print(' '.join(json.load(open('$ROOT/manifest.json'))['entryPoints'].values()))"); do
  [[ -f "$ROOT/$ep" ]] && ok "entry point $ep exists" || bad "entry point $ep is missing"
done
echo

echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
