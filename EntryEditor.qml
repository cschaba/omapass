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
  property var service: null

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius

  // Useful limits rather than arbitrary ones. A pass entry is a file path, so
  // the name is bounded by what a filesystem will hold; the rest are generous
  // enough never to be met in normal use but small enough to stop a paste from
  // a wrong buffer becoming an unopenable entry. (#9)
  readonly property int nameLimit: 255
  readonly property int userLimit: 255
  readonly property int urlLimit: 1024
  readonly property int otpLimit: 1024
  readonly property int notesLimit: 4096

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

  // Shows "1234/4096" only as the limit comes into view: a counter on every
  // field all the time is noise, but hitting a silent cap is worse.
  component FieldLabel: Item {
    id: fieldLabel
    property string label: ""
    property var field: null
    property int limit: 0
    readonly property int used: field ? field.text.length : 0

    implicitHeight: labelText.implicitHeight

    Text {
      id: labelText
      anchors.left: parent.left
      text: fieldLabel.label
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: parent.right
      visible: fieldLabel.limit > 0 && fieldLabel.used > fieldLabel.limit * 0.8
      text: fieldLabel.used + "/" + fieldLabel.limit
      color: fieldLabel.used >= fieldLabel.limit ? Color.urgent : root.foreground
      opacity: fieldLabel.used >= fieldLabel.limit ? 1 : 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

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

    // The whole body, not reveal + fields: reconstructing an entry from its
    // parsed fields silently drops the otpauth line and any free-form text,
    // which then vanishes on save.
    root.loadingEntry = true
    if (root.service) root.service.loadBody(path)

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

  function applyBody(raw) {
    root.loadingEntry = false
    var parsed = PassStore.parseBody(raw)
    passwordField.text = parsed.password
    userField.text = parsed.login
    urlField.text = parsed.url
    otpField.text = parsed.otp
    notesArea.text = parsed.notes.join("\n")
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

  Connections {
    target: root.service
    function onBodyLoaded(path, body) {
      if (path !== root.originalPath) return
      root.applyBody(body)
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

      FieldLabel {
        width: parent.width
        label: "Name"
        field: nameField
        limit: root.nameLimit
      }

      TextField {
        id: nameField
        width: parent.width
        maximumLength: root.nameLimit
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

        FieldLabel {
          width: parent.width
          label: "Username"
          field: userField
          limit: root.userLimit
        }

        TextField {
          id: userField
          width: parent.width
          maximumLength: root.userLimit
          placeholderText: "you@example.com"
          foreground: root.foreground
          accent: root.accent
          KeyNavigation.tab: urlField
        }
      }

      Column {
        width: (parent.width - Style.space(10)) / 2
        spacing: Style.space(3)

        FieldLabel {
          width: parent.width
          label: "URL"
          field: urlField
          limit: root.urlLimit
        }

        TextField {
          id: urlField
          width: parent.width
          maximumLength: root.urlLimit
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

      FieldLabel {
        width: parent.width
        label: "OTP secret (otpauth:// URI — or save, then Ctrl+Q to scan a QR code)"
        field: otpField
        limit: root.otpLimit
      }

      TextField {
        id: otpField
        width: parent.width
        maximumLength: root.otpLimit
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

      FieldLabel {
        width: parent.width
        label: "Other lines"
        field: notesArea
        limit: root.notesLimit
      }

      Rectangle {
        width: parent.width
        height: Style.space(78)
        radius: root.cornerRadius
        color: Util.alpha(root.foreground, 0.05)
        border.width: Style.normalBorderWidth
        border.color: Util.alpha(root.foreground, notesArea.activeFocus ? 0.4 : 0.15)
        clip: true

        // A plain TextArea in a fixed-height Rectangle just runs off the
        // bottom: past three lines the rest was invisible and unreachable.
        // ScrollView gives it somewhere to go. (#9)
        QQC.ScrollView {
          anchors.fill: parent
          anchors.margins: Style.spacing.controlPaddingX
          clip: true
          QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded
          QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff

          QQC.TextArea {
            id: notesArea
            placeholderText: "recovery-code: …"
            color: root.foreground
            placeholderTextColor: Qt.darker(root.foreground, 1.6)
            selectionColor: Util.alpha(root.accent, 0.35)
            selectedTextColor: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: TextEdit.Wrap
            background: null
            padding: 0

            // TextArea has no maximumLength, so hold the line by hand rather
            // than letting a stray paste through.
            onTextChanged: {
              if (text.length > root.notesLimit) {
                var at = cursorPosition
                text = text.slice(0, root.notesLimit)
                cursorPosition = Math.min(at, text.length)
              }
            }
          }
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
