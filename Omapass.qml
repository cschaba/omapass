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
  // is installed (~/.config/omarchy/plugins/omapass, a git worktree, ...).
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
  readonly property bool hasGit: pass.hasGit

  // A fingerprint is enrolled and the PAM service exists, so the vault sits
  // behind a scan. The grace window keeps a quick reopen from demanding a
  // second touch; closing the surface does not by itself re-lock.
  readonly property bool fingerprintRequired: pass.fingerprintRequired
  property bool fingerprintPassed: false
  readonly property int fingerprintGraceMs: pass.setting("fingerprintGrace", 120) * 1000
  readonly property bool vaultLocked: root.ready && root.fingerprintRequired && !root.fingerprintPassed
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

  readonly property var currentRow: displayModel.count > 0 && selectedIndex >= 0 && selectedIndex < displayModel.count
    ? displayModel.get(selectedIndex) : null
  readonly property string currentPath: currentRow ? currentRow.path : ""

  // --- lifecycle ------------------------------------------------------------

  function open(payloadJson) {
    root.opened = true
    root.mode = "list"
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    graceTimer.stop()
    root.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.mode = "list"
    root.forgetSecrets()
    // Re-lock after the grace window rather than immediately: opening the
    // picker twice in a row should not cost two scans.
    if (root.fingerprintPassed) graceTimer.restart()
  }

  function lockVault() {
    root.fingerprintPassed = false
    graceTimer.stop()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omapass")
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
    editor.startNew(root.currentRow ? root.currentRow.folder : "")
    root.mode = "editor"
  }

  function editEntry() {
    if (!root.currentPath) return
    editor.startEdit(root.currentPath)
    root.mode = "editor"
  }

  function closeEditor() {
    root.mode = "list"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function saveEntry(payload) {
    root.closeEditor()
    pass.save(payload)
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

    onListReloaded: root.rebuildDisplay()

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
          } else if (ctrl && event.key === Qt.Key_O) {
            if (shift) root.typeOtp()
            else root.copyOtp()
            event.accepted = true
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
        foreground: root.foreground
        accent: root.selectedText
        fontFamily: root.fontFamily
        onAuthenticated: {
          root.fingerprintPassed = true
          Qt.callLater(function () { keyCatcher.forceActiveFocus() })
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
        visible: root.ready && !root.vaultLocked

        // header: search line
        Item {
          width: parent.width
          height: root.headerHeight

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

          Text {
            id: countText
            anchors.right: parent.right
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
            text: root.errorText
              ? root.errorText
              : "⏎ copy   ⇧⏎ type   ⌥⏎ user   ^L fill login"
                + (root.hasOtpSupport ? "   ^O otp   ^Q scan qr" : "")
                + "   ^R reveal   ^N new   ^E edit   ⌦ delete"
                + (root.hasGit ? "   ^S sync" : "")
            color: root.errorText ? Color.urgent : root.foreground
            opacity: root.errorText ? 1 : 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
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
        service: pass
        background: root.background
        foreground: root.foreground
        accent: root.selectedText
        selectedBackground: root.selectedBackground
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onCancelled: root.closeEditor()
        onSaved: function (payload) { root.saveEntry(payload) }
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
