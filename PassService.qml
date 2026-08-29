import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import "PassStore.js" as PassStore

// Every call into bin/omapass lives here, so the overlay and the bar widget
// cannot drift apart on how secrets are handled.
//
// The rule the whole design rests on: actions that touch a decrypted password
// are *detached* — the helper pipes it from gpg into wl-copy or wtype and
// exits, and nothing comes back into this process. Only fields() and reveal()
// read anything back, and neither of them can see a password unless the user
// asked for it.
Item {
  id: root

  property string bin: ""

  property var status: null
  property var entries: []
  property bool loading: false
  property bool unlocked: false
  property string errorText: ""

  readonly property bool ready: status !== null && status.ready === true
  readonly property bool hasOtpSupport: status !== null && status.otp === true
  readonly property bool hasGit: status !== null && status.git === true
  readonly property bool fingerprintRequired: status !== null && status.fingerprint === true
  readonly property bool passwordAuthAvailable: status !== null && status.passwordAuth === true
  readonly property bool welcomed: status !== null && status.welcomed === true

  function markWelcomed() { run(["welcomed", "--mark"]) }

  // Detached like everything else: the shell is about to unload this plugin,
  // so nothing here can wait for the result.
  function quit() { run(["quit"]) }

  // The UI's own breadcrumbs, so a failure that never reaches a process is
  // still visible in the log. Never pass a name or a value — only which step
  // was reached and, where it helps, why it stopped.
  // Each event is a detached process, so four events fired in one function
  // reach the file in whatever order the kernel schedules them — and a trace
  // whose order cannot be trusted cannot answer "which step was last", which
  // is the only question it exists to answer. The counter restores the order
  // the calls were actually made in.
  property int logSequence: 0

  function logEvent(message) {
    // setting() looks in config first — "log" lives there, not at the top level.
    if (root.setting("log", false) !== true) return
    root.logSequence += 1
    run(["log", "--event", "#" + root.logSequence + " " + String(message)])
  }

  // The effective configuration, already resolved by bin/omapass — file,
  // environment and defaults folded together. The UI never parses the file.
  readonly property var config: status !== null && status.config ? status.config : ({})

  function setting(name, fallback) {
    var value = root.config[name]
    if (value === undefined || value === null) value = root.status ? root.status[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  readonly property var requirements: PassStore.setupSteps(status)

  signal listReloaded()
  signal fieldsLoaded(string path, var fields, bool otp)
  signal revealed(string path, string password)
  signal bodyLoaded(string path, string body)
  signal writeFinished(bool ok)

  // --- reads ----------------------------------------------------------------

  function refresh() {
    statusProc.running = true
    unlockedProc.running = true
  }

  function reload() {
    root.loading = true
    listProc.running = true
  }

  // Cleared deliberately, not as a side effect of reloading — a write that
  // fails asks for a reload, and clearing there wiped the reason before anyone
  // could read it.
  function clearError() { root.errorText = "" }

  // Only ever called once gpg-agent is warm; see the note on `unlocked`.
  function loadFields(path) {
    if (!path) return
    fieldsProc.entryPath = path
    fieldsProc.command = [root.bin, "fields", path]
    fieldsProc.running = true
  }

  // The editor's read path: the whole entry, so nothing it does not model gets
  // dropped on save.
  function loadBody(path) {
    if (!path) return
    bodyProc.entryPath = path
    bodyProc.command = [root.bin, "body", path]
    bodyProc.running = true
  }

  function reveal(path) {
    if (!path) return
    revealProc.entryPath = path
    revealProc.command = [root.bin, "reveal", path]
    revealProc.running = true
  }

  // --- detached actions -----------------------------------------------------

  // No shell parsing of the arguments: Util.execArgv runs `exec "$@"`, so an
  // entry name is only ever a positional parameter, never something bash
  // re-tokenizes.
  function run(args) {
    if (!root.bin) return
    Util.execArgv([root.bin].concat(args))
  }

  function copyPassword(path) { if (path) { run(["copy", path]); markUnlockedSoon() } }
  function copyUser(path)     { if (path) { run(["copy-user", path]); markUnlockedSoon() } }
  function typePassword(path) { if (path) { run(["type", path]); markUnlockedSoon() } }
  function typeUser(path)     { if (path) { run(["type-user", path]); markUnlockedSoon() } }
  function typeLogin(path)    { if (path) { run(["login", path]); markUnlockedSoon() } }
  function copyOtp(path)      { if (path && hasOtpSupport) { run(["otp", path, "copy"]); markUnlockedSoon() } }
  function typeOtp(path)      { if (path && hasOtpSupport) { run(["otp", path, "type"]); markUnlockedSoon() } }

  // Hands off to slurp + grim + zbarimg. Detached, because the overlay has to
  // be out of the way before the user can drag a box over the QR code.
  function scanOtp(path)      { if (path && hasOtpSupport) { run(["otp-scan", path]); markUnlockedSoon() } }
  function sync()             { if (hasGit) run(["sync"]) }

  // Setup hints are public commands, so this is an ordinary copy — no
  // sensitive flag, no timeout, and it may land in clipboard history.
  function copyCommand(command) {
    if (command) Util.execArgv(["wl-copy", "--type", "text/plain", String(command)])
  }

  // A decrypt we just triggered warms the agent; re-probe so previews start
  // filling in on their own.
  function markUnlockedSoon() { unlockRecheck.restart() }

  // --- writes ---------------------------------------------------------------

  // payload: { path, originalPath, body, generate, length, symbols }
  function save(payload) {
    root.logEvent("save: requested"
      + " generate=" + (payload.generate === true)
      + " editing=" + (payload.originalPath ? "yes" : "no"))

    var problem = PassStore.nameProblem(payload.path)
    if (problem) {
      root.logEvent("save: refused by name check")
      root.errorText = problem
      root.writeFinished(false)
      return
    }
    if (payload.originalPath && payload.originalPath !== payload.path) {
      root.logEvent("save: renaming first")
      renameProc.pendingPayload = payload
      renameProc.command = [root.bin, "rename", payload.originalPath, payload.path]
      renameProc.running = true
      return
    }
    write(payload)
  }

  function write(payload) {
    var args = [root.bin, "insert", payload.path]
    if (payload.generate)
      args = args.concat(["--generate", String(payload.length), payload.symbols ? "yes" : "no"])
    // Editing replaces on purpose; creating must not. originalPath is set only
    // when the editor was opened on an entry that already existed — including
    // after a rename, where the entry now sits at the new path.
    if (payload.originalPath) args.push("--force")

    insertProc.command = args
    insertProc.pendingBody = payload.body
    insertProc.generated = payload.generate === true
    // Re-arm stdin for this run. onStarted closes it to signal EOF, and the
    // property stays false afterwards — so every save after the first would
    // otherwise hand `pass insert -m` no pipe at all and silently store
    // nothing. Set here, next to the command, so the two cannot drift apart.
    insertProc.stdinEnabled = true
    insertProc.running = true
    root.logEvent("save: insert started running=" + insertProc.running)
  }

  function remove(path) {
    if (!path) return
    removeProc.command = [root.bin, "remove", path]
    removeProc.running = true
  }

  // --- plumbing -------------------------------------------------------------

  Timer {
    id: unlockRecheck
    interval: 1200
    onTriggered: unlockedProc.running = true
  }

  Process {
    id: statusProc
    command: [root.bin, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.status = PassStore.parseStatus(text)
        if (root.ready) root.reload()
      }
    }
  }

  Process {
    id: unlockedProc
    command: [root.bin, "unlocked"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.unlocked = JSON.parse(text).unlocked === true } catch (e) { root.unlocked = false }
      }
    }
  }

  Process {
    id: listProc
    command: [root.bin, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.entries = PassStore.parseList(text)
        root.listReloaded()
      }
    }
    onExited: function (exitCode) {
      root.loading = false
      if (exitCode !== 0) root.errorText = "Could not read the password store"
    }
  }

  Process {
    id: fieldsProc
    property string entryPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        root.fieldsLoaded(fieldsProc.entryPath,
                          parsed && parsed.fields ? parsed.fields : [],
                          parsed ? parsed.otp === true : false)
      }
    }
    onExited: function (exitCode) { if (exitCode === 0) root.unlocked = true }
  }

  Process {
    id: bodyProc
    property string entryPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.bodyLoaded(bodyProc.entryPath, String(text))
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) root.errorText = "Could not decrypt that entry"
      else root.unlocked = true
    }
  }

  Process {
    id: revealProc
    property string entryPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.revealed(revealProc.entryPath, String(text).replace(/\n+$/, ""))
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) root.errorText = "Could not decrypt that entry"
      else root.unlocked = true
    }
  }

  Process {
    id: insertProc
    property string pendingBody: ""
    property bool generated: false
    property string failure: ""

    // The helper already explains itself — "github.com/you already exists —
    // edit it, or choose another name" is far more use than a generic failure,
    // and inventing a second wording for every case is how the two drift.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: insertProc.failure = String(text).replace(/^omapass:\s*/, "").trim()
    }
    // Re-armed by write() before every run; see the note there.
    stdinEnabled: true
    // Write on `started`: the pipe does not exist before the child is up, and
    // closing stdin is what tells `pass insert -m` to stop reading.
    onStarted: {
      insertProc.write(insertProc.pendingBody)
      insertProc.pendingBody = ""
      insertProc.stdinEnabled = false
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.errorText = insertProc.failure
          || (insertProc.generated ? "Could not generate a password"
                                   : "Could not save that entry")
      }
      else root.errorText = ""
      insertProc.failure = ""
      if (insertProc.generated) root.markUnlockedSoon()
      root.writeFinished(exitCode === 0)
      root.reload()
    }
  }

  Process {
    id: renameProc
    property var pendingPayload: null
    property string failure: ""

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: renameProc.failure = String(text).replace(/^omapass:\s*/, "").trim()
    }

    onExited: function (exitCode) {
      var payload = renameProc.pendingPayload
      renameProc.pendingPayload = null
      if (exitCode !== 0) {
        root.errorText = renameProc.failure || "Could not rename that entry"
        renameProc.failure = ""
        root.writeFinished(false)
        root.reload()
        return
      }
      if (payload) root.write(payload)
      else root.reload()
    }
  }

  Process {
    id: removeProc
    onExited: function (exitCode) {
      if (exitCode !== 0) root.errorText = "Could not delete that entry"
      root.writeFinished(exitCode === 0)
      root.reload()
    }
  }
}
