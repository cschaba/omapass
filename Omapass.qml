import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "PassStore.js" as PassStore

// omapass — a password manager overlay backed by pass(1).
//
// Decrypted passwords deliberately do not live in this process. Copy, type and
// login actions are detached calls to bin/omapass, which pipes the secret from
// gpg straight to wl-copy or wtype. The only path that brings a password into
// QML is reveal(), which the user has to ask for and which self-clears.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Resolved from this file's own location, so the plugin works wherever it
  // is installed (~/.config/omarchy/plugins/cschaba.omapass, a worktree, ...).
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property string bin: pluginDir + "bin/omapass"
  readonly property string setupBin: pluginDir + "bin/omapass-setup"

  property bool opened: false
  property string mode: "list"          // list | editor | confirm
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var status: pass.status
  readonly property bool ready: pass.ready
  readonly property bool hasOtpSupport: pass.hasOtpSupport
  readonly property bool hasUrlSupport: pass.hasUrlSupport
  readonly property bool hasGit: pass.hasGit

  // A fingerprint is enrolled and the PAM service exists, so the vault sits
  // behind a scan. The grace window keeps a quick reopen from demanding a
  // second touch; closing the surface does not by itself re-lock.
  readonly property bool fingerprintRequired: pass.fingerprintRequired
  property bool fingerprintPassed: false
  readonly property int fingerprintGraceMs: pass.setting("fingerprintGrace", 120) * 1000
  readonly property bool vaultLocked: root.ready && root.fingerprintRequired && !root.fingerprintPassed

  // Shown once on first run, and on demand with F1 after that. Waits until the
  // vault is open, so it never sits between the user and an unlock prompt.
  property bool aboutOpen: false
  // F1 is Help everywhere else in the world, so it is Help here too. About
  // moved onto the sheet rather than losing its way in. (#32)
  property bool helpOpen: false
  readonly property bool helpVisible: root.opened && root.ready && !root.vaultLocked
    && root.helpOpen && !root.aboutVisible
  // Marking the welcome as seen writes a file, and the flag that hides this
  // panel is read back from that file with the rest of the status — which does
  // not happen until the next open. Without a local latch the panel stays up
  // and the button does nothing.
  property bool aboutDismissed: false
  readonly property bool firstRunAbout: root.ready && !root.vaultLocked
    && !pass.welcomed && !root.aboutDismissed
  readonly property bool aboutVisible: root.ready && !root.vaultLocked && (root.aboutOpen || root.firstRunAbout)

  function dismissAbout() {
    if (root.firstRunAbout) {
      pass.markWelcomed()
      root.aboutDismissed = true
    }
    root.aboutOpen = false
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }
  // "SUPER ALT, P" is how Hyprland's config spells it; nobody says it that way.
  readonly property string openKeyLabel: {
    var spec = String(pass.setting("keybind", "SUPER ALT, P"))
    var parts = spec.split(",")
    var mods = parts[0].trim().split(/\s+/).filter(function (m) { return m.length })
    var key = parts.length > 1 ? parts[1].trim() : ""
    var pretty = mods.map(function (m) {
      var lower = m.toLowerCase()
      return lower === "super" ? "Super"
        : lower === "shift" ? "Shift"
        : lower === "ctrl" || lower === "control" ? "Ctrl"
        : lower === "alt" ? "Alt" : m
    })
    if (key) pretty.push(key.toUpperCase())
    return pretty.join(" + ")
  }

  readonly property var entries: pass.entries
  readonly property bool loading: pass.loading
  readonly property string errorText: pass.errorText

  // gpg-agent has a key cached, so reading an entry will not pop a pinentry.
  // Until then we do not touch the store just to fill in a preview.
  readonly property bool unlocked: pass.unlocked

  property var selectedFields: []
  property bool selectedHasOtp: false
  property string fieldsForPath: ""
  property string revealedPassword: ""

  property string pendingDelete: ""

  // An unfinished entry form, kept while omapass is closed. Filling this form
  // in usually means fetching a password from somewhere else, and the only way
  // to reach another application is to close this one — so closing it used to
  // throw away exactly the work the user was in the middle of. (#37)
  //
  // Memory only. It is never written anywhere, it is dropped on save, on
  // cancel, and whenever the vault re-locks, and draft-timeout puts an upper
  // bound on how long a typed password can sit here.
  property var editorDraft: null

  readonly property int draftTimeoutMs: pass.setting("draftTimeout", 300) * 1000

  function keepDraft() {
    if (root.mode !== "editor" || root.draftTimeoutMs <= 0) return
    root.editorDraft = editor.captureDraft()
    if (root.editorDraft) draftTimer.restart()
  }

  function forgetDraft() {
    root.editorDraft = null
    draftTimer.stop()
  }

  Timer {
    id: draftTimer
    interval: Math.max(1000, root.draftTimeoutMs)
    onTriggered: root.forgetDraft()
  }

  // A draft only comes back once the vault is open. It can hold a password,
  // and the editor draws above the fingerprint gate — resuming behind the gate
  // would hand back the very thing the gate exists to withhold.
  readonly property bool draftResumable: root.opened
    && root.editorDraft !== null
    && root.mode === "list"
    && root.ready
    && !root.vaultLocked
    && root.pendingAction === ""

  onDraftResumableChanged: if (root.draftResumable) Qt.callLater(root.resumeDraft)

  function resumeDraft() {
    if (!root.draftResumable) return
    // Stopped, not restarted: the clock is on how long a draft may sit while
    // omapass is closed, and it is running again the moment it is put down.
    draftTimer.stop()
    root.mode = "editor"
    editor.restoreDraft(root.editorDraft)
  }

  // --- theme (shares the [menu] surface tokens, like the other overlays) ---
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(22), Style.font.caption + Style.spacing.controlPaddingY)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(900), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(44), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX)

  readonly property bool selectedHasUrl: root.fieldsForPath === root.currentPath
                                        && PassStore.hasUrl(root.selectedFields)

  readonly property var currentRow: displayModel.count > 0 && selectedIndex >= 0 && selectedIndex < displayModel.count
    ? displayModel.get(selectedIndex) : null
  readonly property string currentPath: currentRow ? currentRow.path : ""

  // --- lifecycle ------------------------------------------------------------

  // What the caller asked for, held until the store has actually loaded. The
  // summon arrives before the entry list does, and before the vault is
  // unlocked, so the action cannot simply be run here.
  property string pendingAction: ""
  property string pendingActionEntry: ""

  // --- the welcome comes to you ---------------------------------------------
  //
  // #25. The welcome screen was correct and unreachable: it only lived in the
  // overlay, and on a fresh install the overlay is exactly what a new user has
  // no way to open yet. Putting the greeting in install.sh would have covered
  // one install path out of three — `omarchy plugin add` never runs it, and
  // that is the path the release notes tell people to use.
  //
  // What every path does have in common is that the shell ends up loading this
  // plugin, and `keepLoaded: true` means this object exists from that moment
  // even with no window on screen. So the plugin greets you itself.
  property bool welcomeOffered: false

  readonly property bool welcomeWanted: !root.opened
    && !root.welcomeOffered
    && pass.status !== null
    && !pass.welcomed
    // A fingerprint prompt arriving unasked, seconds after logging in, is a
    // worse first impression than a welcome you have to go and find. Those
    // installs meet it on their first deliberate open instead.
    && !pass.fingerprintRequired

  onWelcomeWantedChanged: if (root.welcomeWanted) welcomeDelay.restart()

  Timer {
    id: welcomeDelay
    // Long enough for the bar to be up and for a login to settle. An overlay
    // that takes the keyboard while the desktop is still assembling itself
    // reads as a glitch rather than as a greeting.
    interval: 1500
    onTriggered: {
      if (!root.welcomeWanted) return
      root.welcomeOffered = true
      // Through the shell, not by setting `opened` here: it is what keeps the
      // shell's record of which overlays are up true, and therefore what keeps
      // `omarchy-shell shell hide` and the hotkey's toggle honest.
      if (root.shell && typeof root.shell.summon === "function")
        root.shell.summon((root.manifest && root.manifest.id) || "cschaba.omapass", "{}")
    }
  }

  function open(payloadJson) {
    root.opened = true
    root.mode = "list"
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    graceTimer.stop()
    pass.clearError()

    var payload = null
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = null }
    root.pendingAction = payload && payload.action ? String(payload.action) : ""
    root.pendingActionEntry = payload && payload.entry ? String(payload.entry) : ""

    root.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  // Run once the list is in and the vault is open — never before, or a summon
  // would walk straight past the fingerprint gate.
  function runPendingAction() {
    if (!root.pendingAction || !root.ready || root.vaultLocked) return

    var action = root.pendingAction
    var entry = root.pendingActionEntry
    root.pendingAction = ""
    root.pendingActionEntry = ""

    pass.logEvent("summon: action=" + action)

    if (action === "help") {
      root.helpOpen = true
    } else if (action === "new") {
      // Ctrl+N with an unfinished new entry waiting is far more likely to mean
      // "back to that" than "throw it away and start again", and Cancel is
      // right there for when it does not.
      if (root.editorDraft && root.editorDraft.isNew === true) root.resumeDraft()
      else root.newEntry()
    } else if (action === "edit" && entry) {
      if (root.selectPath(entry)) root.editEntry()
    }
  }

  function close() {
    // Before mode is reset, or there is no editor left to ask.
    root.keepDraft()
    root.opened = false
    root.mode = "list"
    // A sheet left open would be the first thing seen on the next open, in
    // front of the list the user actually asked for.
    root.helpOpen = false
    root.forgetSecrets()
    // Re-lock after the grace window rather than immediately: opening the
    // picker twice in a row should not cost two scans.
    if (root.fingerprintPassed) graceTimer.restart()
  }

  function lockVault() {
    root.fingerprintPassed = false
    graceTimer.stop()
    root.forgetDraft()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "cschaba.omapass")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Anything derived from a decrypted entry goes away with the window.
  function forgetSecrets() {
    root.revealedPassword = ""
    root.selectedFields = []
    root.selectedHasOtp = false
    root.fieldsForPath = ""
    revealTimer.stop()
  }

  // IPC entry point: `omarchy-shell shell call omapass refresh ""`. The setup
  // script calls it so the overlay drops its setup screen once it is done.
  function refresh() {
    pass.refresh()
  }

  function reload() {
    pass.reload()
  }

  function rebuildDisplay() {
    var rows = PassStore.filterEntries(root.entries, root.filterText, 200)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      displayModel.append({
        path: rows[i].path,
        name: rows[i].name,
        folder: rows[i].folder
      })
    }

    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function () {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  // Preview fields only once the agent is warm; otherwise moving the cursor
  // would fire a pinentry prompt per row, which is nobody's idea of a picker.
  function loadFields() {
    if (!root.opened || !root.unlocked) return
    if (!root.currentPath || root.currentPath === root.fieldsForPath) return
    pass.loadFields(root.currentPath)
  }

  // --- navigation ----------------------------------------------------------

  function select(delta) {
    if (displayModel.count === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  // --- actions -------------------------------------------------------------

  function copyPassword() { if (root.currentPath) { pass.copyPassword(root.currentPath); root.dismiss() } }
  function copyUser()     { if (root.currentPath) { pass.copyUser(root.currentPath); root.dismiss() } }
  function copyName()     { if (root.currentPath) { pass.copyName(root.currentPath); root.dismiss() } }
  function copyUrl()      { if (root.currentPath) { pass.copyUrl(root.currentPath); root.dismiss() } }
  function openUrl()      { if (root.currentPath && root.hasUrlSupport) { pass.openUrl(root.currentPath); root.dismiss() } }
  function typePassword() { if (root.currentPath) { pass.typePassword(root.currentPath); root.dismiss() } }
  function typeLogin()    { if (root.currentPath) { pass.typeLogin(root.currentPath); root.dismiss() } }
  function copyOtp()      { if (root.currentPath && root.hasOtpSupport) { pass.copyOtp(root.currentPath); root.dismiss() } }
  function typeOtp()      { if (root.currentPath && root.hasOtpSupport) { pass.typeOtp(root.currentPath); root.dismiss() } }
  function scanOtp()      { if (root.currentPath && root.hasOtpSupport) { pass.scanOtp(root.currentPath); root.dismiss() } }
  function sync()         { pass.sync() }
  function copyCommand(command) { pass.copyCommand(command) }

  function toggleReveal() {
    if (!root.currentPath) return
    if (root.revealedPassword) {
      root.revealedPassword = ""
      revealTimer.stop()
      return
    }
    pass.reveal(root.currentPath)
  }

  // --- editor --------------------------------------------------------------

  function newEntry() {
    if (!root.ready) return
    editor.startNew()
    root.mode = "editor"
  }

  function editEntry() {
    if (!root.currentPath) return
    editor.startEdit(root.currentPath)
    root.mode = "editor"
  }

  function closeEditor() {
    // Cancel and save are both decisions about the form, so both end the
    // draft. Closing the *window* is not — that is the case keepDraft() is for.
    root.forgetDraft()
    root.mode = "list"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  property string pendingSelect: ""

  function saveEntry(payload) {
    root.closeEditor()
    // Remembered so the reload that follows can select it. "Did that save?" is
    // a question the app should answer by showing you, not leave you to check.
    root.pendingSelect = payload.path
    pass.save(payload)
  }

  function selectPath(path) {
    for (var i = 0; i < displayModel.count; i++) {
      if (displayModel.get(i).path === path) {
        root.cursorActive = true
        root.selectedIndex = i
        resultList.positionViewAtIndex(i, ListView.Contain)
        return true
      }
    }
    return false
  }

  function requestDelete() {
    if (!root.currentPath) return
    root.pendingDelete = root.currentPath
    deleteConfirm.selectedIndex = 1
    root.mode = "confirm"
  }

  function cancelDelete() {
    root.pendingDelete = ""
    root.mode = "list"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.pendingDelete
    root.pendingDelete = ""
    root.mode = "list"
    root.fieldsForPath = ""
    pass.remove(target)
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function launchSetup() {
    // The launcher builds a shell string out of "$*" and runs it through
    // `bash -c`, so the path is re-parsed by a shell. Quote it here: without
    // this a home directory with a space in it silently breaks setup, and a
    // path with shell metacharacters would execute them.
    Util.execArgv(["omarchy-launch-floating-terminal-with-presentation",
                   Util.shellQuote(root.setupBin)])
    root.dismiss()
  }

  // --- reactions -----------------------------------------------------------

  onCurrentPathChanged: {
    root.revealedPassword = ""
    revealTimer.stop()
    if (root.currentPath !== root.fieldsForPath) {
      root.selectedFields = []
      root.selectedHasOtp = false
    }
    fieldsDebounce.restart()
  }

  onUnlockedChanged: if (root.unlocked) fieldsDebounce.restart()

  Component.onCompleted: root.refresh()

  ListModel { id: displayModel }

  // Coalesces the burst of selection changes while the user holds an arrow key
  // down into one decrypt.
  Timer {
    id: fieldsDebounce
    interval: 180
    onTriggered: root.loadFields()
  }

  Timer {
    id: graceTimer
    interval: root.fingerprintGraceMs
    onTriggered: root.fingerprintPassed = false
  }

  Timer {
    id: revealTimer
    interval: pass.setting("revealTimeout", 15) * 1000
    onTriggered: root.revealedPassword = ""
  }

  // --- backend --------------------------------------------------------------

  PassService {
    id: pass
    bin: root.bin

    onListReloaded: {
      root.rebuildDisplay()
      Qt.callLater(root.runPendingAction)
      if (root.pendingSelect) {
        var wanted = root.pendingSelect
        root.pendingSelect = ""
        // After rebuildDisplay's own deferred positioning, or it would scroll
        // back to the old cursor.
        Qt.callLater(function () { root.selectPath(wanted) })
      }
    }

    onFieldsLoaded: function (path, fields, otp) {
      if (path !== root.currentPath) return
      root.selectedFields = fields
      root.selectedHasOtp = otp
      root.fieldsForPath = path
    }

    onRevealed: function (path, password) {
      if (path !== root.currentPath) return
      root.revealedPassword = password
      if (password) revealTimer.restart()
    }
  }

  // --- window ---------------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omapass"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.ready
        ? root.cardHeight
        : Math.min(root.cardHeight, setupNotice.implicitHeight + root.contentMargin * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Focus lives in a text field while the editor is open, and a focused
      // TextField swallows keys before the catcher below ever sees them. So
      // the way out of the sheet is a Shortcut, which sees them regardless.
      // Enabled only while the sheet is up, which is precisely when the
      // editor's own Esc and F1 stand down. (#32)
      Shortcut {
        sequences: ["Esc", "F1"]
        enabled: root.helpVisible
        context: Qt.WindowShortcut
        onActivated: {
          root.helpOpen = false
          if (root.mode === "editor") Qt.callLater(function () { editor.refocus() })
          else Qt.callLater(function () { keyCatcher.forceActiveFocus() })
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (root.mode === "editor") return          // the editor owns its keys

          if (root.mode === "confirm") {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          // Same rule the About screen already follows: while a sheet is over
          // the list, the list must not be driveable through it. Without this,
          // Ctrl+N behind the help sheet opens an editor nobody can see.
          if (root.helpVisible) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_F1
                || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              root.helpOpen = false
            event.accepted = true
            return
          }

          if (root.aboutVisible) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter || event.key === Qt.Key_F1)
              root.dismissAbout()
            event.accepted = true
            return
          }

          if (root.vaultLocked) {
            // Esc leaves, Tab swaps between the reader and a password. Every
            // other key is swallowed so the picker underneath cannot be driven
            // blind through the gate.
            if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
            else if (event.key === Qt.Key_Tab) { fingerprintGate.toggleMode(); event.accepted = true }
            else event.accepted = true
            return
          }

          if (!root.ready) {
            if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.launchSetup(); event.accepted = true }
            return
          }

          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0
          var alt = (event.modifiers & Qt.AltModifier) !== 0

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-8); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(8); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1); event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            // Explicit "show me this entry" — the one unlock the user opts into.
            if (!root.unlocked) root.toggleReveal()
            else root.loadFields()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_N) {
            root.newEntry(); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_E) {
            root.editEntry(); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_R) {
            root.toggleReveal(); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_L) {
            root.typeLogin(); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_U) {
            root.openUrl(); event.accepted = true
          // Alt copies a field, Ctrl does something with it. Both of these
          // were on Ctrl+Shift until an input method ate Ctrl+Shift+U before
          // Qt ever saw it; Alt is left alone by IBus and fcitx alike. (#31)
          } else if (alt && event.key === Qt.Key_U) {
            root.copyUrl(); event.accepted = true
          } else if (alt && event.key === Qt.Key_N) {
            root.copyName(); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_O) {
            if (shift) root.typeOtp()
            else root.copyOtp()
            event.accepted = true
          } else if (event.key === Qt.Key_F1) {
            root.helpOpen = !root.helpOpen; event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Q) {
            root.scanOtp(); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_S) {
            root.sync(); event.accepted = true
          } else if (event.key === Qt.Key_Delete || (ctrl && event.key === Qt.Key_D)) {
            root.requestDelete(); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!root.cursorActive && displayModel.count > 0) root.cursorActive = true
            else if (alt) root.copyUser()
            else if (shift) root.typePassword()
            else root.copyPassword()
            event.accepted = true
          } else if (!ctrl && !alt && event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      // --- setup gate --------------------------------------------------------

      FingerprintGate {
        id: fingerprintGate
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.vaultLocked
        armed: root.opened && root.vaultLocked
        passwordAvailable: pass.passwordAuthAvailable
        maxScanFailures: Math.max(1, pass.setting("fingerprintRetries", 1))
        foreground: root.foreground
        accent: root.selectedText
        fontFamily: root.fontFamily
        onAuthenticated: {
          root.fingerprintPassed = true
          Qt.callLater(function () { keyCatcher.forceActiveFocus() })
          Qt.callLater(root.runPendingAction)
        }
      }

      HelpSheet {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        z: 15
        visible: root.helpVisible
        foreground: root.foreground
        accent: root.selectedText
        fontFamily: root.fontFamily
        hasOtpSupport: root.hasOtpSupport
        hasUrlSupport: root.hasUrlSupport
        hasGit: root.hasGit
        openKey: root.openKeyLabel
        onDismissed: {
          root.helpOpen = false
          if (root.mode === "editor") Qt.callLater(function () { editor.refocus() })
          else Qt.callLater(function () { keyCatcher.forceActiveFocus() })
        }
        onAboutRequested: {
          root.helpOpen = false
          root.aboutOpen = true
        }
      }

      AboutPanel {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.aboutVisible
        service: pass
        firstRun: root.firstRunAbout
        foreground: root.foreground
        accent: root.selectedText
        selectedBackground: root.selectedBackground
        fontFamily: root.fontFamily
        onDismissed: root.dismissAbout()
        onQuitRequested: {
          root.dismissAbout()
          root.dismiss()
          pass.quit()
        }
      }

      SetupNotice {
        id: setupNotice
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.status !== null && !root.ready
        steps: PassStore.setupSteps(root.status)
        foreground: root.foreground
        accent: root.selectedText
        fontFamily: root.fontFamily
        onStartSetup: root.launchSetup()
        onCopyHint: function (command) { root.copyCommand(command) }
      }

      // --- main list ---------------------------------------------------------

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing
        visible: root.ready && !root.vaultLocked && !root.aboutVisible

        // header: search line
        Item {
          width: parent.width
          height: root.headerHeight
          // Hidden rather than removed while the shortcut sheet is over it.
          // A Column lays out only its visible children, so dropping these two
          // out would pull the footer up to the top of the card. (#32)
          opacity: root.helpVisible ? 0 : 1
          enabled: !root.helpVisible

          Text {
            id: searchText
            anchors.left: parent.left
            anchors.right: countText.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search passwords…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          // The corner, where there is room for it. A keyboard-first app still
          // has to be discoverable by someone reaching for the mouse — F1 is
          // only findable once you already know it is there — but the hint row
          // it used to sit on is the busiest line in the app. (#32)
          Rectangle {
            id: helpButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(20)
            height: width
            radius: width / 2
            color: helpArea.containsMouse ? root.selectedBackground : "transparent"
            border.width: 1
            border.color: Util.alpha(root.foreground, helpArea.containsMouse ? 0.45 : 0.22)

            Text {
              anchors.centerIn: parent
              text: "?"
              color: helpArea.containsMouse ? root.selectedText : root.foreground
              opacity: helpArea.containsMouse ? 1 : 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: helpArea
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.helpOpen = !root.helpOpen

              PanelToolTip {
                visible: helpArea.containsMouse
                text: "Keyboard shortcuts (F1)"
              }
            }
          }

          Text {
            id: countText
            anchors.right: helpButton.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.loading ? "…"
              : (displayModel.count === root.entries.length
                 ? root.entries.length + " entries"
                 : displayModel.count + " of " + root.entries.length)
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // body: list + detail
        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2
          opacity: root.helpVisible ? 0 : 1
          enabled: !root.helpVisible

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: Math.round(parent.width * 0.55)
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: entryRow
                  required property int index
                  required property string path
                  required property string name
                  required property string folder

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Column {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)

                    Item { width: 1; height: Style.space(6) }

                    Text {
                      width: parent.width
                      text: entryRow.name
                      color: entryRow.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      visible: entryRow.folder.length > 0
                      text: entryRow.folder
                      color: root.foreground
                      opacity: 0.45
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideLeft
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) {
                      root.cursorActive = true
                      root.selectedIndex = entryRow.index
                    }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = entryRow.index
                      root.copyPassword()
                    }
                  }
                }
              }

              // empty states
              Column {
                anchors.centerIn: parent
                width: parent.width - root.contentMargin * 2
                spacing: Style.space(8)
                visible: displayModel.count === 0 && !root.loading

                Text {
                  width: parent.width
                  text: "󰌾"
                  color: root.selectedText
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  width: parent.width
                  text: root.entries.length === 0
                    ? "No passwords yet — press Ctrl+N to add one"
                    : "No matches for “" + root.filterText + "”"
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }
            }

            // detail pane
            Item {
              width: parent.width - Math.round(parent.width * 0.55)
              height: parent.height
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Column {
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                spacing: Style.space(10)
                visible: root.currentRow !== null

                Text {
                  width: parent.width
                  text: root.currentPath
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.WrapAnywhere
                }

                // password line
                Column {
                  width: parent.width
                  spacing: Style.space(2)

                  Text {
                    text: "password"
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    width: parent.width
                    text: root.revealedPassword ? root.revealedPassword : "••••••••••••"
                    color: root.revealedPassword ? root.selectedText : root.foreground
                    opacity: root.revealedPassword ? 1 : 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WrapAnywhere
                  }

                  Text {
                    visible: root.revealedPassword.length > 0
                    text: "hides automatically"
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Repeater {
                  model: root.selectedFields

                  Column {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                      text: modelData.key
                      color: root.foreground
                      opacity: 0.45
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      width: parent.width
                      text: modelData.value
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WrapAnywhere
                    }
                  }
                }

                Text {
                  visible: root.selectedHasOtp
                  text: "󰯄  one-time code — Ctrl+O copy, Ctrl+Shift+O type"
                  color: root.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: !root.unlocked && root.fieldsForPath !== root.currentPath
                  width: parent.width
                  text: "Locked — press Tab to unlock and show details"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }

        // footer: key hints / errors
        Item {
          width: parent.width
          height: root.footerHeight

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.errorText.length > 0
            text: root.errorText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          ActionHints {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.errorText.length === 0
            foreground: root.foreground
            accent: root.selectedText
            fontFamily: root.fontFamily
            actions: [
              { key: "⏎",  label: "copy",       action: function () { root.copyPassword() } },
              { key: "⇧⏎", label: "type",       action: function () { root.typePassword() } },
              { key: "⌥⏎", label: "user",       action: function () { root.copyUser() } },
              { key: "⌥N", label: "name",       action: function () { root.copyName() } },
              { key: "^U", label: "open url",   action: function () { root.openUrl() },
                visible: root.hasUrlSupport && root.selectedHasUrl },
              { key: "^L", label: "fill login", action: function () { root.typeLogin() } },
              { key: "^O", label: "otp",        action: function () { root.copyOtp() },
                visible: root.hasOtpSupport },
              { key: "^Q", label: "scan qr",    action: function () { root.scanOtp() },
                visible: root.hasOtpSupport },
              { key: "^R", label: "reveal",     action: function () { root.toggleReveal() } },
              { key: "^N", label: "new",        action: function () { root.newEntry() } },
              { key: "^E", label: "edit",       action: function () { root.editEntry() } },
              { key: "⌦",  label: "delete",     action: function () { root.requestDelete() } },
              { key: "^S", label: "sync",       action: function () { root.sync() },
                visible: root.hasGit },
              { key: "F1", label: "help",       action: function () { root.helpOpen = true } }
            ]
          }
        }
      }

      // --- overlays ----------------------------------------------------------

      EntryEditor {
        id: editor
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        z: 10
        opened: root.mode === "editor"
        // Out of the way while the sheet is over it, exactly as the list is:
        // the sheet is drawn above the editor, and the card's own footer —
        // hints and the (?) — comes back underneath it. (#32)
        opacity: root.helpVisible ? 0 : 1
        enabled: !root.helpVisible
        helpUp: root.helpVisible
        service: pass
        background: root.background
        foreground: root.foreground
        accent: root.selectedText
        selectedBackground: root.selectedBackground
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onCancelled: root.closeEditor()
        onSaved: function (payload) { root.saveEntry(payload) }
        onHelpRequested: root.helpOpen = true
      }

      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        z: 20
        opened: root.mode === "confirm"
        message: "Delete “" + root.pendingDelete + "” from the store?"
        confirmText: "Delete"
        background: root.background
        foreground: root.foreground
        scrim: root.scrim
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onCanceled: root.cancelDelete()
        onConfirmed: root.confirmDelete()
      }
    }
  }
}
