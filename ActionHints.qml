import QtQuick
import qs.Commons

// The row of key hints along the bottom of a surface, with the keys actually
// wired up — reading "^L fill login" and not being able to click it is a small
// papercut that repeats every time. (#3)
//
// Each entry is { key, label, action, visible }. `action` is called on click;
// `visible` defaults to true.
Item {
  id: root

  property var actions: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property real restingOpacity: 0.45
  property int spacing: Style.space(14)

  implicitHeight: row.implicitHeight
  implicitWidth: row.implicitWidth

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.spacing

    Repeater {
      model: root.actions

      Item {
        id: hint
        required property var modelData

        readonly property bool shown: modelData.visible === undefined || modelData.visible === true

        visible: shown
        width: shown ? label.implicitWidth : 0
        height: label.implicitHeight

        Text {
          id: label
          text: hint.modelData.key + " " + hint.modelData.label
          color: area.containsMouse ? root.accent : root.foreground
          opacity: area.containsMouse ? 1 : root.restingOpacity
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          Behavior on opacity { NumberAnimation { duration: 90 } }
        }

        MouseArea {
          id: area
          anchors.fill: parent
          // A caption-sized target is a hard thing to hit; grow it past the
          // painted text so the pointer does not have to be precise.
          anchors.margins: -Style.space(5)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (typeof hint.modelData.action === "function") hint.modelData.action()
          }
        }
      }
    }
  }
}
