.pragma library

// Pure helpers for the omapass overlay. No QML types, no state — everything
// here is a function of its arguments so it stays trivially testable.

// Subsequence match with a score, so "ghcs" finds "github.com/cs" but a
// contiguous run and a match right after a separator both rank higher.
function score(haystack, needle) {
  if (!needle) return 1
  var hay = haystack.toLowerCase()
  var pin = needle.toLowerCase()

  var total = 0
  var hayIndex = 0
  var streak = 0

  for (var i = 0; i < pin.length; i++) {
    var ch = pin.charAt(i)
    var found = hay.indexOf(ch, hayIndex)
    if (found === -1) return 0

    var points = 1
    if (found === hayIndex && i > 0) {
      streak++
      points += streak * 3          // contiguous run
    } else {
      streak = 0
    }
    if (found === 0) points += 6    // start of the whole path
    else {
      var prev = hay.charAt(found - 1)
      if (prev === "/" || prev === "." || prev === "-" || prev === "_")
        points += 4                 // start of a path or hostname segment
    }

    total += points
    hayIndex = found + 1
  }

  // Prefer shorter paths when the run of matches is otherwise equal.
  return total + Math.max(0, 20 - haystack.length) * 0.1
}

// Entries are {path, name, folder}. Returns the same objects, filtered and
// ordered best-first, capped at `limit`.
function filterEntries(entries, filter, limit) {
  if (!entries || entries.length === 0) return []

  var out = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!entry || !entry.path) continue

    var s = filter ? score(entry.path, filter) : 1
    if (s <= 0) continue

    // A hit on the leaf name is what the user usually means.
    if (filter) {
      var nameScore = score(entry.name, filter)
      if (nameScore > 0) s += nameScore * 1.5
    }
    out.push({ entry: entry, score: s })
  }

  out.sort(function (a, b) {
    if (b.score !== a.score) return b.score - a.score
    return a.entry.path.localeCompare(b.entry.path)
  })

  var rows = []
  var cap = Math.min(out.length, limit || out.length)
  for (var j = 0; j < cap; j++) rows.push(out[j].entry)
  return rows
}

function parseList(raw) {
  try {
    var parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch (e) {
    return []
  }
}

function parseStatus(raw) {
  try {
    var parsed = JSON.parse(raw)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (e) {
    return null
  }
}

// Every requirement the backend checked, in the order a person would fix them.
// Each row carries the exact command that fixes it, so the overlay can show
// instructions rather than just a red cross.
function setupSteps(status) {
  if (!status || !Array.isArray(status.requirements)) return []
  return status.requirements
}

// What is actually blocking startup — optional extras do not count.
function missingRequirements(status) {
  return setupSteps(status).filter(function (r) { return !r.ok && !r.optional })
}

// The guided script can install packages, make a key and init the store. It
// cannot do anything about a requirement it does not know how to fix, so the
// overlay only offers the button when it would help.
function guidedSetupHelps(status) {
  return missingRequirements(status).length > 0
}

// Why a name cannot be stored, or "" when it can. The same rules bin/omapass
// enforces — it is the boundary that matters, this is so the editor can say
// what is wrong before asking the user to press save again.
//
// Note what is *not* rejected: "/" separates folders and is the whole point,
// and "$" and other punctuation are ordinary characters here. Nothing omapass
// runs goes through a shell, so shell metacharacters carry no meaning.
// Tidies what a person types into what pass stores. "work / aws" is a folder
// path typed the way people write paths; rejecting it for the spaces is
// pedantry, and rejecting it *quietly* reads as the save doing nothing at all.
function normalizeName(name) {
  return String(name === undefined || name === null ? "" : name)
    .trim()
    .split("/")
    .map(function (part) { return part.trim() })
    .join("/")
}

function nameProblem(name) {
  var value = normalizeName(name)
  if (!value) return "Enter a name, like github.com/you"
  if (value.charAt(0) === "/") return "Name must be relative — drop the leading /"
  if (value.charAt(0) === "-") return "Name may not start with -"
  if (value.indexOf("..") !== -1) return "Name may not contain .."
  if (/[\u0000-\u001f\u007f]/.test(value)) return "Name may not contain control characters"

  var parts = value.split("/")
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    if (!part) return "Name has an empty folder — check the slashes"
    if (part.charAt(0) === ".") return "Folders and names may not start with a dot"
    if (/[\s.]$/.test(part)) return "Name may not end with a space or dot"
    // Bytes, not characters: this becomes a filename.
    if (unescape(encodeURIComponent(part)).length > 255) return "Name is too long"
  }
  return ""
}

// Case-sensitive, like the filesystem the store lives on.
function entryExists(entries, name) {
  if (!entries || !name) return false
  for (var i = 0; i < entries.length; i++)
    if (entries[i] && entries[i].path === name) return true
  return false
}

function validName(name) {
  return nameProblem(name) === ""
}

// Splits a decrypted entry into the parts the editor shows. Everything that is
// not the password, a known field, or the otpauth line is kept verbatim in
// `notes` — an editor that quietly drops what it does not understand is an
// editor that eats your TOTP secret.
function parseBody(raw) {
  var lines = String(raw || "").replace(/\n+$/, "").split("\n")
  var out = { password: lines.length ? lines[0] : "", login: "", url: "", otp: "", notes: [] }

  for (var i = 1; i < lines.length; i++) {
    var line = lines[i]

    if (/^otpauth:\/\//i.test(line.trim())) {
      if (!out.otp) out.otp = line.trim()
      else out.notes.push(line)
      continue
    }

    var match = line.match(/^\s*([^:=]+)[:=]\s*(.*)$/)
    if (!match) {
      out.notes.push(line)
      continue
    }

    var key = match[1].trim().toLowerCase()
    var value = match[2]
    if (!out.login && (key === "login" || key === "username" || key === "user" || key === "email"))
      out.login = value
    else if (!out.url && (key === "url" || key === "site" || key === "host"))
      out.url = value
    else
      out.notes.push(line)
  }

  return out
}

// Whether `fields` (as the backend reports them) carries a URL. The keys are
// the ones parseBody() recognises, and the ones bin/omapass opens — all three
// have to name the same set or a surface offers an action the backend refuses.
function hasUrl(fields) {
  for (var i = 0; i < (fields || []).length; i++) {
    var key = String(fields[i].key || "").toLowerCase()
    if ((key === "url" || key === "site" || key === "host")
        && String(fields[i].value || "").length > 0)
      return true
  }
  return false
}

// A pass entry is a line-oriented format, so a newline inside a field value is
// not data — it is a new line in the file. Pasting one into the username field
// could silently attach an attacker's otpauth:// secret, or overwrite another
// field. Everything the editor writes goes through here first.
//
// Control characters go too: they are invisible when the entry is read back,
// which makes them the wrong thing to store either way.
function sanitizeValue(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .trim()
}

// Field keys additionally cannot contain the separator, or reading the entry
// back would split them in the wrong place.
function sanitizeKey(key) {
  return sanitizeValue(key).replace(/[:=]/g, "").trim()
}

// What `pass otp` will actually accept, which is stricter than it first looks.
// Its own regex makes the label optional — but it then reads an accountname out
// of that label and dies with "missing accountname" when there is none. So
// `otpauth://totp?secret=...`, which several password managers hand out and
// which parses fine on paper, is refused by the thing that has to read it. (#40)
//
// Checked against pass-otp's parser rather than inferred from the spec.
function validOtpUri(uri) {
  var value = sanitizeValue(uri)
  if (!value) return true
  var m = value.match(/^otpauth:\/\/(totp|hotp)\/([^?]*)\?(.+)$/i)
  if (!m) return false
  // The label has to yield a non-empty accountname. pass-otp splits it on the
  // first colon and takes the right-hand side, falling back to the whole label.
  var label = decodeURIComponent(m[2].replace(/\+/g, " "))
  var account = label.indexOf(":") === -1 ? label : label.slice(label.indexOf(":") + 1)
  if (!account.trim()) return false
  return /(^|&)secret=[^&]+/i.test(m[3])
}

// A bare secret, as printed under a QR code when a site offers "can't scan it?".
// Base32 only, and long enough that a password pasted into the wrong field is
// not mistaken for one — the shortest secret anyone issues is 16 characters,
// while "hunter2" would otherwise pass for base32 quite happily.
function looksLikeOtpSecret(value) {
  var bare = sanitizeValue(value).replace(/[\s-]+/g, "")
  return bare.length >= 16 && /^[A-Za-z2-7]+=*$/.test(bare)
}

// Turns what the user actually pasted into something `pass otp` can read.
// Three shapes go in: a complete URI, a URI missing its label, and a bare
// secret. One shape comes out. Returns "" for empty input, and null for
// anything that cannot be rescued, so the caller can tell the two apart.
function normalizeOtp(value, entryName) {
  var raw = sanitizeValue(value)
  if (!raw) return ""

  // The label is cosmetic to pass-otp but not optional, so the entry's own name
  // is the honest thing to put there — it is what the user called this account.
  var label = encodeURIComponent(sanitizeValue(entryName) || "omapass")

  if (looksLikeOtpSecret(raw))
    return "otpauth://totp/" + label + "?secret=" + raw.replace(/[\s-]+/g, "").toUpperCase()

  var missingLabel = raw.match(/^otpauth:\/\/(totp|hotp)\?(.+)$/i)
  if (missingLabel)
    return "otpauth://" + missingLabel[1].toLowerCase() + "/" + label + "?" + missingLabel[2]

  // A label that is present but empty, or one that is only an issuer with no
  // account after the colon: same problem, same repair.
  var emptyLabel = raw.match(/^otpauth:\/\/(totp|hotp)\/([^?]*)\?(.+)$/i)
  if (emptyLabel && !validOtpUri(raw)) {
    var stub = emptyLabel[2].replace(/:.*$/, "")
    var rebuilt = stub ? stub + ":" + label : label
    var candidate = "otpauth://" + emptyLabel[1].toLowerCase() + "/" + rebuilt + "?" + emptyLabel[3]
    if (validOtpUri(candidate)) return candidate
  }

  return validOtpUri(raw) ? raw : null
}

// Turns the editor's field rows back into the body pass stores: password on
// line one, "key: value" after it.
function composeBody(password, fields, otpUri) {
  // The password keeps its own line and is never sanitized beyond newlines:
  // punctuation is exactly what a good password is made of.
  var lines = [sanitizeValue(password).length ? String(password).replace(/[\r\n]+/g, "") : ""]

  for (var i = 0; i < (fields || []).length; i++) {
    var f = fields[i]
    if (!f) continue
    var key = sanitizeKey(f.key)
    var value = sanitizeValue(f.value)
    if (!key || !value) continue
    lines.push(key + ": " + value)
  }

  var otp = sanitizeValue(otpUri)
  if (otp && validOtpUri(otp)) lines.push(otp)
  return lines.join("\n") + "\n"
}
