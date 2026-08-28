import QtQuick
import qs.Commons
import qs.Ui

// First-run gate. omapass checks its requirements every time it opens, and
// when something is missing this replaces the picker.
//
// Each unmet requirement shows the command that fixes it: the guided script
// covers the common path, but someone who would rather run three commands
// themselves should not have to go and find out what they are.
Item {
  id: root

  property var steps: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily

  signal startSetup()
  signal copyHint(string command)

  implicitHeight: layout.implicitHeight

  Column {
    id: layout
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(parent.width, Style.space(460))
    spacing: Style.space(12)

    Text {
      width: parent.width
      text: "󰌾"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
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
      spacing: Style.space(4)

      Repeater {
        model: root.steps

        Column {
          id: stepRow
          required property var modelData

          readonly property bool met: modelData.ok === true
          readonly property bool optional: modelData.optional === true

          width: parent.width
          spacing: Style.space(1)

          Row {
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: Style.space(12)
              text: stepRow.met ? "✓" : (stepRow.optional ? "–" : "✗")
              color: stepRow.met ? root.accent : root.foreground
              opacity: stepRow.met ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              text: modelData.label
              color: root.foreground
              opacity: stepRow.met ? 0.6 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: stepRow.optional
              text: "optional"
              color: root.foreground
              opacity: 0.35
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // the fix, verbatim — click to copy
          Rectangle {
            visible: !stepRow.met && modelData.hint
            width: parent.width
            height: hintText.implicitHeight + Style.spacing.controlPaddingY
            x: Style.space(22)
            radius: Style.cornerRadius
            color: hintArea.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"

            Text {
              id: hintText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.right: parent.right
              text: modelData.hint
              color: root.accent
              opacity: 0.85
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            MouseArea {
              id: hintArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyHint(modelData.hint)
            }
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
      radius: Style.cornerRadius
      color: Util.alpha(root.accent, setupArea.containsMouse ? 0.24 : 0.16)

      Text {
        anchors.centerIn: parent
        text: "⏎   Set up now"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      MouseArea {
        id: setupArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.startSetup()
      }
    }

    Text {
      width: parent.width
      text: "Opens a terminal and walks through the steps above — or run the commands yourself; click one to copy it."
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }
}
