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
  // Set by the overlay when it hands a kept draft back, so the form can say
  // that this is work you left rather than something it invented. (#37)
  property bool resumed: false
  property string loadError: ""

  signal cancelled()
  signal saved(var payload)

  // The shortcut sheet can be opened from in here, and it is drawn by the
  // overlay above this form rather than by the form itself. All this side
  // needs to know is that it is up, so it stops acting on keys. (#32)
  property bool helpUp: false
  signal helpRequested()

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

  function startNew() {
    root.isNew = true
    root.resumed = false
    root.originalPath = ""
    root.loadError = ""
    root.loadingEntry = false
    root.generate = true
    root.generateLength = 24
    root.generateSymbols = true
    root.revealPassword = false

    // Empty, always. Pre-filling the selected entry's folder meant a typed
    // name landed inside it — the save succeeded and the entry appeared
    // somewhere the user was not looking. (#21)
    nameField.text = ""
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
    root.resumed = false
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

  // --- drafts ---------------------------------------------------------------
  //
  // Everything the form is holding, as plain data, so the overlay can put an
  // unfinished entry down and pick it up again. Closing omapass to go and copy
  // a password out of another application is the ordinary way to fill this
  // form in, and it used to cost you everything you had typed. (#37)
  function captureDraft() {
    if (!root.opened) return null
    var draft = {
      isNew: root.isNew,
      originalPath: root.originalPath,
      generate: root.generate,
      generateLength: root.generateLength,
      generateSymbols: root.generateSymbols,
      name: nameField.text,
      password: passwordField.text,
      user: userField.text,
      url: urlField.text,
      otp: otpField.text,
      notes: notesArea.text
    }
    // A form still waiting for its own entry to decrypt has nothing in it that
    // the user put there, and restoring it would hold an empty body over the
    // real one — worse than not remembering at all.
    if (root.loadingEntry) return null
    if (!draft.name && !draft.password && !draft.user && !draft.url
        && !draft.otp && !draft.notes)
      return null
    return draft
  }

  function restoreDraft(draft) {
    if (!draft) return
    root.resumed = true
    root.isNew = draft.isNew === true
    root.originalPath = String(draft.originalPath || "")
    root.generate = draft.generate === true
    root.generateLength = Number(draft.generateLength) || 24
    root.generateSymbols = draft.generateSymbols === true
    root.revealPassword = false
    root.loadError = ""
    // Deliberately not re-reading the entry: the body that matters is the one
    // in the draft, and loadBody would land on top of it a moment later.
    root.loadingEntry = false

    nameField.text = String(draft.name || "")
    passwordField.text = String(draft.password || "")
    userField.text = String(draft.user || "")
    urlField.text = String(draft.url || "")
    otpField.text = String(draft.otp || "")
    notesArea.text = String(draft.notes || "")

    Qt.callLater(function () {
      nameField.forceActiveFocus()
      nameField.cursorPosition = nameField.text.length
    })
  }

  // Wipe every field that could still be holding a secret.
  function clearForm() {
    passwordField.text = ""
    notesArea.text = ""
    otpField.text = ""
    root.revealPassword = false
    root.loadError = ""
  }

  // Disabling the form to put the sheet over it takes active focus off the
  // field that had it, and re-enabling does not reliably hand it back. So the
  // overlay says when to take it again. The name field rather than wherever
  // the caret was: a form that ignores typing is the failure worth avoiding,
  // and remembering the exact field is not worth the bookkeeping. (#32)
  function refocus() {
    if (root.opened) nameField.forceActiveFocus()
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
    if (root.service) root.service.logEvent("editor: submit pressed")
    var name = PassStore.normalizeName(nameField.text)
    // Show the tidied name, so what is saved is what is on screen.
    if (name !== nameField.text) nameField.text = name
    var problem = PassStore.nameProblem(name)
    if (problem) {
      if (root.service) root.service.logEvent("editor: refused (name)")
      root.loadError = problem
      nameField.forceActiveFocus()
      return
    }
    if (!root.generate && !passwordField.text) {
      if (root.service) root.service.logEvent("editor: refused (password)")
      root.loadError = "Enter a password, or switch on Generate"
      passwordField.forceActiveFocus()
      return
    }
    // The entry list is already loaded, so a clash can be caught here — the
    // editor stays open with the name selected instead of closing on a save
    // that the store is going to refuse anyway.
    if (root.isNew && root.service && PassStore.entryExists(root.service.entries, name)) {
      if (root.service) root.service.logEvent("editor: refused (duplicate)")
      root.loadError = "“" + name + "” already exists — edit it, or pick another name"
      nameField.forceActiveFocus()
      nameField.selectAll()
      return
    }
    // Repaired where it can be, rejected where it cannot — and never dropped on
    // the way to the store, so a mistyped secret does not vanish silently. A
    // bare secret and a URI with no label are both things other password
    // managers hand out, and both are things `pass otp` refuses to read until
    // they have a label on them. (#40)
    var otp = PassStore.normalizeOtp(otpField.text, name)
    if (otp === null) {
      if (root.service) root.service.logEvent("editor: refused (otp)")
      root.loadError = "That is not a one-time-code secret. Paste the otpauth:// URI, "
        + "or just the secret key on its own."
      otpField.forceActiveFocus()
      otpField.selectAll()
      return
    }
    // Show what will actually be stored rather than saving something other than
    // what is on screen.
    if (otp !== otpField.text) otpField.text = otp

    var extras = []
    if (userField.text.trim()) extras.push({ key: "login", value: userField.text })
    if (urlField.text.trim()) extras.push({ key: "url", value: urlField.text })

    var body = PassStore.composeBody(passwordField.text, extras, otp)
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

    if (root.service) root.service.logEvent("editor: handing over to save")
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
    enabled: root.opened && !root.helpUp
    context: Qt.WindowShortcut
    onActivated: root.submit()
  }

  // Esc is the reflex that closes a help window, and in here it is also the
  // key that throws the draft away. Both of these stand down while the sheet
  // is up and the overlay's own pair takes over, so exactly one side of the
  // pane owns Esc at any moment — a shortcut list is not worth losing work
  // over, and two enabled Shortcuts on one sequence fire neither. (#32)
  Shortcut {
    sequence: "Esc"
    enabled: root.opened && !root.helpUp
    context: Qt.WindowShortcut
    onActivated: root.cancel()
  }

  Shortcut {
    sequence: "F1"
    enabled: root.opened && !root.helpUp
    context: Qt.WindowShortcut
    onActivated: root.helpRequested()
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: titleRow.implicitHeight

      Row {
        id: titleRow
        anchors.left: parent.left
        anchors.right: editorHelpButton.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)

        Text {
          text: root.isNew ? "New password" : "Edit password"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.resumed && !root.loadingEntry
          text: "· picked up where you left off"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
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

      // The corner, not the button row. Down there it would have been a third
      // thing to aim at beside Cancel and Save, on the one line of this form
      // that already has something to do. (#32)
      Rectangle {
        id: editorHelpButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(20)
        height: width
        radius: width / 2
        color: editorHelpArea.containsMouse ? root.selectedBackground : "transparent"
        border.width: 1
        border.color: Util.alpha(root.foreground, editorHelpArea.containsMouse ? 0.45 : 0.22)

        Text {
          anchors.centerIn: parent
          text: "?"
          color: editorHelpArea.containsMouse ? root.accent : root.foreground
          opacity: editorHelpArea.containsMouse ? 1 : 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: editorHelpArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.helpRequested()

          PanelToolTip {
            visible: editorHelpArea.containsMouse
            text: "Keyboard shortcuts (F1)"
          }
        }
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
            onClicked: {
              root.generate = !root.generate
              // Switching it off is a decision to type a password, so the
              // cursor goes where that happens.
              if (!root.generate) Qt.callLater(function () { passwordField.forceActiveFocus() })
            }
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

      // Always on screen, even when generating. Hiding it made the form
      // reshuffle every time the checkbox was touched, and left the field the
      // whole section is named after missing from it. Generating disables it
      // rather than removing it — there is nothing to type, but there is still
      // something to look at. (#33)
      TextField {
        id: passwordField
        width: parent.width
        enabled: !root.generate
        opacity: root.generate ? 0.5 : 1
        password: !root.revealPassword
        placeholderText: root.generate ? "generated when you save" : "the password"
        foreground: root.foreground
        accent: root.accent
        KeyNavigation.tab: userField

        // A visible field you cannot type into is an invitation with nothing
        // behind it. Clicking it is a clear enough statement of intent to
        // switch generation off and let the user get on with typing.
        MouseArea {
          anchors.fill: parent
          visible: root.generate
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.generate = false
            Qt.callLater(function () { passwordField.forceActiveFocus() })
          }
        }
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
        label: "OTP secret (otpauth:// URI or the bare key — or save, then Ctrl+Q to scan a QR code)"
        field: otpField
        limit: root.otpLimit
      }

      TextField {
        id: otpField
        width: parent.width
        maximumLength: root.otpLimit
        password: true
        placeholderText: "otpauth://totp/… or just the secret key"
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

      Row {
        anchors.left: parent.left
        anchors.right: saveRow.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        // Caption-sized grey was too easy to walk past — a refused save that
        // goes unnoticed is indistinguishable from a save that did nothing.
        Text {
          visible: root.loadError.length > 0
          text: "⚠"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width - (root.loadError ? Style.space(20) : 0)
          text: root.loadError ? root.loadError : "Ctrl+⏎ save   Esc cancel"
          color: root.loadError ? Color.urgent : root.foreground
          opacity: root.loadError ? 1 : 0.45
          font.family: root.fontFamily
          font.pixelSize: root.loadError ? Style.font.body : Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: saveRow
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
