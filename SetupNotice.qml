import QtQuick
import qs.Commons
import qs.Ui

// First-run gate. omapass needs three things it cannot conjure from inside the
// shell process — a package install, a GPG key, and an initialised store — so
// this shows what is missing and hands off to bin/omapass-setup in a terminal.
Item {
  id: root

  property var steps: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily

  signal startSetup()

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width, Style.space(420))
    spacing: Style.space(14)

    Text {
      width: parent.width
      text: "󰌾"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      text: "omapass isn’t set up yet"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      horizontalAlignment: Text.AlignHCenter
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.steps

        Row {
          required property var modelData
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: modelData.done ? "✓" : "✗"
            color: modelData.done ? root.accent : root.foreground
            opacity: modelData.done ? 1 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            text: modelData.label
            color: root.foreground
            opacity: modelData.done ? 0.75 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
      radius: Style.cornerRadius
      color: Util.alpha(root.accent, 0.16)

      Text {
        anchors.centerIn: parent
        text: "⏎   Set up now"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.startSetup()
      }
    }

    Text {
      width: parent.width
      text: "Opens a terminal and walks through installing pass, creating a GPG key, and initialising your store."
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }
}
