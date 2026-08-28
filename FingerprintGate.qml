import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons
import qs.Ui

// Fingerprint unlock in front of the vault, using the same PAM service and the
// same enrolment test as Omarchy's lock screen (`omarchy-lock-fingerprint`).
//
// It re-arms after every failed scan, because fprintd ends the conversation on
// a bad read and a gate you can only fail once is a gate that locks you out.
// There is always a way past it that does not involve the reader: Escape closes
// the surface, `pass` on the command line is untouched, and the opt-out file
// disables the gate entirely.
Item {
  id: root

  property bool armed: false
  property string userName: Quickshell.env("USER")
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property bool compact: false

  property int attempts: 0
  property bool scanning: false
  property string statusText: ""

  // "fingerprint" or "password". The password path is a real check against the
  // same PAM service Omarchy's lock screen uses, not a way around the gate — a
  // gate with a skip button is decoration.
  property string mode: "fingerprint"
  property bool checkingPassword: false

  // Whether omarchy-lock-password exists. Without it there is nothing to fall
  // back to, and pretending otherwise would send the user to a dead end.
  property bool passwordAvailable: true

  // A reader that errors is not the same as a finger that does not match: the
  // first means the device is unreachable, and no amount of touching it will
  // help. Both give up eventually rather than looping forever. (#8)
  property int readerErrors: 0
  readonly property int maxScanFailures: 3
  readonly property int maxReaderErrors: 2
  property bool fellBack: false

  signal authenticated()

  function toggleMode() {
    if (root.mode === "password") root.useFingerprint()
    else root.usePassword()
  }

  readonly property string optOutPath: "~/.config/omapass/no-fingerprint"

  onArmedChanged: {
    if (armed) start()
    else stop()
  }

  function start() {
    root.attempts = 0
    root.readerErrors = 0
    root.fellBack = false
    root.statusText = ""
    root.mode = "fingerprint"
    passwordField.text = ""
    beginScan()
  }

  // Hand over to the password prompt without the user having to notice a link.
  // `reason` is shown so it is clear why the reader stopped being asked.
  function fallBackToPassword(reason) {
    if (!root.passwordAvailable) {
      // Nothing to fall back to. Say what will actually get them in.
      root.statusText = reason + " — no password service to fall back on"
      return
    }
    root.fellBack = true
    root.usePassword()
    root.statusText = reason
  }

  function usePassword() {
    root.mode = "password"
    root.statusText = ""
    // fprintd holds the reader for the length of a conversation; let it go
    // rather than leaving a scan running behind a password prompt.
    retry.stop()
    root.scanning = false
    if (pam.active) pam.abort()
    Qt.callLater(function () { passwordField.forceActiveFocus() })
  }

  function useFingerprint() {
    root.mode = "fingerprint"
    root.statusText = ""
    // An explicit switch back is a request to try the reader again, so the
    // counters that gave up on it start over.
    root.attempts = 0
    root.readerErrors = 0
    root.fellBack = false
    passwordField.text = ""
    if (passwordPam.active) passwordPam.abort()
    beginScan()
  }

  function submitPassword() {
    if (root.checkingPassword || !passwordField.text) return
    root.checkingPassword = true
    root.statusText = ""
    if (!passwordPam.start()) {
      root.checkingPassword = false
      root.statusText = "Could not start the password check"
    }
  }

  function beginScan() {
    if (!root.armed || pam.active || root.mode !== "fingerprint") return
    root.scanning = true
    if (!pam.start()) {
      root.scanning = false
      root.readerErrors += 1
      if (root.readerErrors >= root.maxReaderErrors) {
        root.fallBackToPassword("Fingerprint reader is not available")
        return
      }
      root.statusText = "Could not reach the fingerprint reader"
      retry.restart()
    }
  }

  function stop() {
    retry.stop()
    root.scanning = false
    root.checkingPassword = false
    passwordField.text = ""
    if (pam.active) pam.abort()
    if (passwordPam.active) passwordPam.abort()
  }

  PamContext {
    id: pam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function (result) {
      root.scanning = false
      if (!root.armed || root.mode !== "fingerprint") return

      if (result === PamResult.Success) {
        root.statusText = ""
        root.attempts = 0
        root.authenticated()
        return
      }

      root.attempts += 1
      if (root.attempts >= root.maxScanFailures) {
        root.fallBackToPassword("Fingerprint not recognised")
        return
      }
      root.statusText = "Not recognised — try again"
      retry.restart()
    }

    onError: function (error) {
      root.scanning = false
      if (!root.armed || root.mode !== "fingerprint") return
      root.readerErrors += 1
      if (root.readerErrors >= root.maxReaderErrors) {
        root.fallBackToPassword("Fingerprint reader is not available")
        return
      }
      root.statusText = "Reader error — retrying"
      retry.restart()
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    // PAM asks for the password through the conversation rather than up front,
    // so the answer is handed over when it is requested.
    onResponseRequiredChanged: if (responseRequired && root.checkingPassword) respond(passwordField.text)
    onPamMessage: if (responseRequired && root.checkingPassword) respond(passwordField.text)

    onCompleted: function (result) {
      root.checkingPassword = false
      if (!root.armed) return

      if (result === PamResult.Success) {
        passwordField.text = ""
        root.statusText = ""
        root.authenticated()
        return
      }
      passwordField.text = ""
      root.attempts += 1
      root.statusText = "Wrong password"
    }

    onError: function (error) {
      root.checkingPassword = false
      passwordField.text = ""
      if (root.armed) root.statusText = "Password check failed"
    }
  }

  // fprintd needs a beat before it will accept another conversation.
  Timer {
    id: retry
    interval: 400
    repeat: false
    onTriggered: root.beginScan()
  }

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width, Style.space(400))
    spacing: root.compact ? Style.space(6) : Style.space(12)

    Text {
      width: parent.width
      visible: root.mode === "fingerprint"
      text: "󰈷"
      color: root.accent
      opacity: root.scanning ? 1 : 0.55
      font.family: root.fontFamily
      font.pixelSize: root.compact ? Style.font.display : Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter

      // A slow pulse, so it is obvious the reader is waiting on a finger.
      SequentialAnimation on opacity {
        running: root.scanning
        loops: Animation.Infinite
        NumberAnimation { from: 0.5; to: 1; duration: 900; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 1; to: 0.5; duration: 900; easing.type: Easing.InOutQuad }
      }
    }

    Text {
      width: parent.width
      text: root.mode === "password"
        ? (root.checkingPassword ? "Checking…" : "Enter your password")
        : "Touch the fingerprint reader"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.compact ? Style.font.body : Style.font.heading
      horizontalAlignment: Text.AlignHCenter
    }

    TextField {
      id: passwordField
      width: parent.width
      visible: root.mode === "password"
      enabled: !root.checkingPassword
      password: true
      placeholderText: "Password"
      foreground: root.foreground
      accent: root.accent
      onAccepted: root.submitPassword()
    }

    Text {
      width: parent.width
      visible: root.statusText.length > 0
      text: root.statusText
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    // The way out. Without it the reader is the only door, and a reader that
    // will not read you is a locked one. (#6)
    Text {
      width: parent.width
      visible: root.passwordAvailable
      text: (root.mode === "password" ? "Use fingerprint instead" : "Use password instead")
            + "   (Tab)"
      color: switchArea.containsMouse ? root.accent : root.foreground
      opacity: switchArea.containsMouse ? 1 : 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter

      MouseArea {
        id: switchArea
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.mode === "password" ? root.useFingerprint() : root.usePassword()
      }
    }

    Text {
      width: parent.width
      visible: !root.compact
      text: "Esc to close"
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }

    // After a few bad reads, say how to get past a reader that is not working.
    Text {
      width: parent.width
      visible: root.fellBack || (root.attempts >= 3 && root.mode === "fingerprint")
      text: "Reader not cooperating? Create " + root.optOutPath + " to turn this off.\nYour passwords stay reachable with the pass command either way."
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }
}
