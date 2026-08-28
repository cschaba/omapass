#!/bin/bash

# Round-trip matrix for entries: what the editor composes, what the store keeps,
# and what the editor reads back.
#
# This walks the real data path without the GUI — PassStore.composeBody builds
# the body exactly as the editor does, bin/omapass writes and reads it, and
# PassStore.parseBody parses it exactly as the editor would. A field that
# survives all three survives the app.
#
# Everything runs against a throwaway GPG home and store.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMAPASS="$ROOT/bin/omapass"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
same() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1"
           printf '        got:  %s\n        want: %s\n' "$2" "$3"; fi; }

command -v node >/dev/null 2>&1 || { echo "node is required for these tests"; exit 1; }

export GNUPGHOME="$TMP/gnupg"
export PASSWORD_STORE_DIR="$TMP/store"
export XDG_STATE_HOME="$TMP/state"
export OMAPASS_CONFIG="$TMP/config"
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"

echo "entry round-trip matrix"
echo

gpg --batch --quiet --passphrase '' --quick-generate-key \
  "omapass entries <entries@example.invalid>" default default never 2>/dev/null \
  || { echo "could not create a test key"; exit 1; }
pass init "$(gpg --list-secret-keys --with-colons | awk -F: '$1=="fpr"{print $10; exit}')" >/dev/null 2>&1

# Compose a body the way the editor does. Arguments are JSON so values with
# spaces, quotes and punctuation reach node intact.
compose() {
  node -e '
    const fs = require("fs");
    let src = fs.readFileSync(process.argv[1], "utf8").replace(".pragma library", "");
    eval(src);
    const [password, login, url, otp, notes] = JSON.parse(process.argv[2]);
    const fields = [];
    if (login) fields.push({ key: "login", value: login });
    if (url) fields.push({ key: "url", value: url });
    let body = composeBody(password, fields, otp);
    if (notes) body += notes + "\n";
    process.stdout.write(body);
  ' "$ROOT/PassStore.js" "$1"
}

# Parse a stored body the way the editor does, returning one field.
parse_field() {
  node -e '
    const fs = require("fs");
    let src = fs.readFileSync(process.argv[1], "utf8").replace(".pragma library", "");
    eval(src);
    const parsed = parseBody(fs.readFileSync(0, "utf8"));
    const key = process.argv[2];
    process.stdout.write(key === "notes" ? parsed.notes.join("\n") : String(parsed[key]));
  ' "$ROOT/PassStore.js" "$1"
}

# name | password | login | url | otp | notes
run_case() {
  local label="$1" name="$2" password="$3" login="$4" url="$5" otp="$6" notes="$7"
  local payload body stored

  payload=$(node -e 'process.stdout.write(JSON.stringify(process.argv.slice(1)))' \
    "$password" "$login" "$url" "$otp" "$notes")
  body=$(compose "$payload")

  if ! printf '%s\n' "$body" | "$OMAPASS" insert "$name" >/dev/null 2>&1; then
    bad "$label (insert failed)"
    return
  fi

  stored=$("$OMAPASS" body "$name" 2>/dev/null)
  same "$label — password" "$(printf '%s' "$stored" | parse_field password)" "$password"
  [[ -n $login ]] && same "$label — login" "$(printf '%s' "$stored" | parse_field login)" "$login"
  [[ -n $url ]] && same "$label — url" "$(printf '%s' "$stored" | parse_field url)" "$url"
  [[ -n $otp ]] && same "$label — otp" "$(printf '%s' "$stored" | parse_field otp)" "$otp"
  [[ -n $notes ]] && same "$label — notes" "$(printf '%s' "$stored" | parse_field notes)" "$notes"
  return 0
}

echo "fields present and absent"
run_case "minimal"        "m/minimal"  "pw1"                 ""                  ""                       "" ""
run_case "login only"     "m/login"    "pw2"                 "someone@example.com" ""                     "" ""
run_case "url only"       "m/url"      "pw3"                 ""                  "https://example.com"    "" ""
run_case "otp only"       "m/otp"      "pw4"                 ""                  ""                       "otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP" ""
run_case "everything"     "m/all"      "pw5"                 "someone@example.com" "https://example.com"  "otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP" "recovery: 1234"
echo

echo "spaces"
run_case "spaces in password" "s/pw"   "correct horse battery" ""                ""                       "" ""
run_case "spaces in login"    "s/login" "pw"                 "first last"        ""                       "" ""
same "spaces in name" \
  "$(printf 'p\n' | "$OMAPASS" insert "s/my account name" >/dev/null 2>&1 && "$OMAPASS" reveal "s/my account name")" "p"
echo

echo "url schemes"
for scheme in "http://example.com/a" "https://example.com/a?b=c&d=e" \
              "ftp://files.example.com/pub" "ssh://git@host.example.com:22/repo.git" \
              "https://example.com/path with spaces"; do
  run_case "url $scheme" "u/$(printf '%s' "$scheme" | md5sum | cut -c1-8)" "pw" "" "$scheme" "" ""
done
echo

echo "other lines"
run_case "no notes"    "n/none" "pw" "" "" "" ""
run_case "one note"    "n/one"  "pw" "" "" "" "recovery: single"
run_case "many notes"  "n/many" "pw" "" "" "" "$(printf 'first line\nsecond line\nthird line')"
echo

echo "conflicts"
printf 'ORIGINAL\n' | "$OMAPASS" insert c/exists >/dev/null 2>&1
printf 'REPLACEMENT\n' | "$OMAPASS" insert c/exists >/dev/null 2>&1
same "creating over an entry is refused" "$("$OMAPASS" reveal c/exists)" "ORIGINAL"
printf 'REPLACEMENT\n' | "$OMAPASS" insert c/exists --force >/dev/null 2>&1
same "--force replaces on purpose" "$("$OMAPASS" reveal c/exists)" "REPLACEMENT"

printf 'KEEP\n' | "$OMAPASS" insert c/target >/dev/null 2>&1
printf 'MOVE\n' | "$OMAPASS" insert c/source >/dev/null 2>&1
"$OMAPASS" rename c/source c/target >/dev/null 2>&1
same "renaming onto an entry is refused" "$("$OMAPASS" reveal c/target)" "KEEP"
same "the source survives a refused rename" "$("$OMAPASS" reveal c/source)" "MOVE"
"$OMAPASS" rename c/source c/moved >/dev/null 2>&1
same "renaming to a free name works" "$("$OMAPASS" reveal c/moved)" "MOVE"
echo

echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
