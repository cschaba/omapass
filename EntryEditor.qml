import Quickshell.Io
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "PassStore.js" as PassStore

// Add / edit form for a single pass entry.
//
// Editing is the one place a decrypted password legitimately enters this
// process: pass stores an entry as one blob, so rewriting it means having the
// whole body. It is loaded only when the user opens the editor on an existing
// entry, and cleared the moment the form closes.
Item {
  id: root

  property bool opened: false
  property string bin: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius

  property string originalPath: ""
  property bool isNew: true
  property bool generate: false
  property int generateLength: 24
  property bool generateSymbols: true
  property bool revealPassword: false
  property bool loadingEntry: false
  property string loadError: ""

  signal cancelled()
  signal saved(var payload)

  visible: opened

  // --- lifecycle ------------------------------------------------------------

  function startNew(folder) {
    root.isNew = true
    root.originalPath = ""
    root.loadError = ""
    root.loadingEntry = false
    root.generate = true
    root.generateLength = 24
    root.generateSymbols = true
    root.revealPassword = false

    nameField.text = folder ? folder + "/" : ""
    passwordField.text = ""
    userField.text = ""
    urlField.text = ""
    otpField.text = ""
    notesArea.text = ""

    Qt.callLater(function () {
      nameField.forceActiveFocus()
      nameField.cursorPosition = nameField.text.length
    })
  }

  function startEdit(path) {
    root.isNew = false
    root.originalPath = path
    root.loadError = ""
    root.generate = false
    root.revealPassword = false

    nameField.text = path
    passwordField.text = ""
    userField.text = ""
    urlField.text = ""
    otpField.text = ""
    notesArea.text = ""

    root.loadingEntry = true
    loadProc.command = [root.bin, "reveal", path]
    loadProc.running = true
    fieldsProc.command = [root.bin, "fields", path]
    fieldsProc.running = true

    Qt.callLater(function () { nameField.forceActiveFocus() })
  }

  // Wipe every field that could still be holding a secret.
  function clearForm() {
    passwordField.text = ""
    notesArea.text = ""
    otpField.text = ""
    root.revealPassword = false
    root.loadError = ""
  }

  function cancel() {
    root.clearForm()
    root.cancelled()
  }

  function applyFields(raw) {
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) { return }
    if (!parsed || !parsed.fields) return

    var leftovers = []
    for (var i = 0; i < parsed.fields.length; i++) {
      var f = parsed.fields[i]
      var key = String(f.key || "").toLowerCase()
      if (!userField.text && (key === "login" || key === "username" || key === "user" || key === "email"))
        userField.text = f.value
      else if (!urlField.text && (key === "url" || key === "site" || key === "host"))
        urlField.text = f.value
      else
        leftovers.push(f.key + ": " + f.value)
    }
    notesArea.text = leftovers.join("\n")
  }

  function submit() {
    var name = nameField.text.trim()
    if (!PassStore.validName(name)) {
      root.loadError = "Enter a name like github.com/you"
      return
    }
    if (!root.generate && !passwordField.text) {
      root.loadError = "Enter a password, or switch on Generate"
      return
    }

    var extras = []
    if (userField.text.trim()) extras.push({ key: "login", value: userField.text })
    if (urlField.text.trim()) extras.push({ key: "url", value: urlField.text })

    var body = PassStore.composeBody(passwordField.text, extras, otpField.text.trim())
    var notes = notesArea.text.trim()
    if (notes) body += notes + "\n"

    var payload = {
      path: name,
      originalPath: root.originalPath,
      body: body,
      generate: root.generate,
      length: root.generateLength,
      symbols: root.generateSymbols
    }

    root.clearForm()
    root.saved(payload)
  }

  // --- data ----------------------------------------------------------------

  Process {
    id: loadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: passwordField.text = String(text).replace(/\n+$/, "")
    }
    onExited: function (exitCode) {
      root.loadingEntry = false
      if (exitCode !== 0) root.loadError = "Could not decrypt this entry"
    }
  }

  Process {
    id: fieldsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFields(text)
    }
  }

  // --- ui -------------------------------------------------------------------

  Rectangle {
    anchors.fill: parent
    color: root.background
  }

  MouseArea { anchors.fill: parent; onClicked: {} }

  // Focus lives in the text fields here, not in a key catcher, and a focused
  // TextField swallows Return before it can bubble up. Shortcuts see the key
  // regardless of which field has focus; `enabled` keeps them off the list
  // view's own bindings while the editor is closed.
  Shortcut {
    sequences: ["Ctrl+Return", "Ctrl+Enter"]
    enabled: root.opened
    context: Qt.WindowShortcut
    onActivated: root.submit()
  }

  Shortcut {
    sequence: "Esc"
    enabled: root.opened
    context: Qt.WindowShortcut
    onActivated: root.cancel()
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Row {
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: root.isNew ? "New password" : "Edit password"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.loadingEntry
        text: "decrypting…"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        text: "Name"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      TextField {
        id: nameField
        width: parent.width
        placeholderText: "github.com/you"
        foreground: root.foreground
        accent: root.accent
        KeyNavigation.tab: root.generate ? userField : passwordField
      }
    }

    // password: either typed, or generated on save
    Column {
      width: parent.width
      spacing: Style.space(3)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Password"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.generate ? "󰄲  generate" : "󰄱  generate"
          color: root.generate ? root.accent : root.foreground
          opacity: root.generate ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.generate = !root.generate
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.generate
          text: root.generateLength + " chars"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var steps = [12, 16, 20, 24, 32, 48]
              var next = steps.indexOf(root.generateLength) + 1
              root.generateLength = steps[next >= steps.length ? 0 : next]
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.generate
          text: root.generateSymbols ? "󰄲  symbols" : "󰄱  symbols"
          color: root.generateSymbols ? root.accent : root.foreground
          opacity: root.generateSymbols ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.generateSymbols = !root.generateSymbols
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.generate
          text: root.revealPassword ? "󰈈  hide" : "󰈉  show"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.revealPassword = !root.revealPassword
          }
        }
      }

      TextField {
        id: passwordField
        width: parent.width
        visible: !root.generate
        password: !root.revealPassword
        placeholderText: "the password"
        foreground: root.foreground
        accent: root.accent
        KeyNavigation.tab: userField
      }

      Text {
        visible: root.generate
        width: parent.width
        text: root.isNew
          ? "A new password is generated on save and copied to your clipboard."
          : "Saving replaces the current password with a freshly generated one."
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      Column {
        width: (parent.width - Style.space(10)) / 2
        spacing: Style.space(3)

        Text {
          text: "Username"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: userField
          width: parent.width
          placeholderText: "you@example.com"
          foreground: root.foreground
          accent: root.accent
          KeyNavigation.tab: urlField
        }
      }

      Column {
        width: (parent.width - Style.space(10)) / 2
        spacing: Style.space(3)

        Text {
          text: "URL"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: urlField
          width: parent.width
          placeholderText: "https://…"
          foreground: root.foreground
          accent: root.accent
          KeyNavigation.tab: otpField
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        text: "OTP secret (otpauth:// URI)"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      TextField {
        id: otpField
        width: parent.width
        password: true
        placeholderText: "otpauth://totp/…"
        foreground: root.foreground
        accent: root.accent
        KeyNavigation.tab: notesArea
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        text: "Other lines"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        width: parent.width
        height: Style.space(70)
        radius: root.cornerRadius
        color: Util.alpha(root.foreground, 0.05)
        border.width: Style.normalBorderWidth
        border.color: Util.alpha(root.foreground, notesArea.activeFocus ? 0.4 : 0.15)

        QQC.TextArea {
          id: notesArea
          anchors.fill: parent
          anchors.margins: Style.spacing.controlPaddingX
          placeholderText: "recovery-code: …"
          color: root.foreground
          placeholderTextColor: Qt.darker(root.foreground, 1.6)
          selectionColor: Util.alpha(root.accent, 0.35)
          selectedTextColor: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: TextEdit.Wrap
          background: null
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(20)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.loadError ? root.loadError : "Ctrl+⏎ save   Esc cancel"
        color: root.loadError ? Color.urgent : root.foreground
        opacity: root.loadError ? 1 : 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Rectangle {
          width: Style.space(70)
          height: Style.space(24)
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.centerIn: parent
            text: "Cancel"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cancel()
          }
        }

        Rectangle {
          width: Style.space(70)
          height: Style.space(24)
          radius: root.cornerRadius
          color: Util.alpha(root.accent, 0.18)

          Text {
            anchors.centerIn: parent
            text: "Save"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.submit()
          }
        }
      }
    }
  }
}
