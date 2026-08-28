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

// Which setup steps are still outstanding, in the order they must happen.
function setupSteps(status) {
  if (!status) return []
  return [
    { key: "pass", label: "pass CLI installed", done: status.pass === true },
    { key: "gpg", label: "GPG key available", done: status.gpg === true && (status.keys || []).length > 0 },
    { key: "store", label: "Password store initialised", done: status.store === true }
  ]
}

// A name is valid if pass can store it: relative, no traversal, no newline.
function validName(name) {
  if (!name) return false
  var trimmed = String(name).trim()
  if (!trimmed) return false
  if (trimmed.charAt(0) === "/") return false
  if (trimmed.indexOf("..") !== -1) return false
  if (trimmed.indexOf("\n") !== -1) return false
  return true
}

// Turns the editor's field rows back into the body pass stores: password on
// line one, "key: value" after it.
function composeBody(password, fields, otpUri) {
  var lines = [password || ""]
  for (var i = 0; i < (fields || []).length; i++) {
    var f = fields[i]
    if (!f || !f.key) continue
    var key = String(f.key).trim()
    var value = String(f.value === undefined ? "" : f.value).trim()
    if (!key || !value) continue
    lines.push(key + ": " + value)
  }
  if (otpUri) lines.push(otpUri)
  return lines.join("\n") + "\n"
}
