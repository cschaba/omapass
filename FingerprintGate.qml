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

  signal authenticated()

  readonly property string optOutPath: "~/.config/omapass/no-fingerprint"

  onArmedChanged: {
    if (armed) start()
    else stop()
  }

  function start() {
    root.attempts = 0
    root.statusText = ""
    beginScan()
  }

  function beginScan() {
    if (!root.armed || pam.active) return
    root.scanning = true
    if (!pam.start()) {
      root.scanning = false
      root.statusText = "Could not reach the fingerprint reader"
      retry.restart()
    }
  }

  function stop() {
    retry.stop()
    root.scanning = false
    if (pam.active) pam.abort()
  }

  PamContext {
    id: pam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function (result) {
      root.scanning = false
      if (!root.armed) return

      if (result === PamResult.Success) {
        root.statusText = ""
        root.attempts = 0
        root.authenticated()
        return
      }

      root.attempts += 1
      root.statusText = "Not recognised — try again"
      retry.restart()
    }

    onError: function (error) {
      root.scanning = false
      if (!root.armed) return
      root.attempts += 1
      root.statusText = "Reader error — try again"
      retry.restart()
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
      text: "Touch the fingerprint reader"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.compact ? Style.font.body : Style.font.heading
      horizontalAlignment: Text.AlignHCenter
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
      visible: root.attempts >= 3
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
