import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Shown once on first run, and on demand from the overlay afterwards. The same
// panel serves both: a welcome is just an About that nobody has read yet. (#14)
Item {
  id: root

  property var service: null
  property bool firstRun: false

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal dismissed()

  readonly property string appName: service ? service.setting("name", "omapass") : "omapass"
  readonly property string appVersion: service && service.status ? (service.status.version || "") : ""
  readonly property string homepage: service ? service.setting("homepage", "") : ""
  readonly property int entryCount: service && service.status ? (service.status.entries || 0) : 0

  // Only offered while logging is on. A link to a file that does not exist is
  // worse than no link.
  readonly property bool logging: service ? service.setting("log", false) === true : false
  readonly property string logPath: service ? service.setting("logPath", "") : ""

  function openHomepage() {
    if (root.homepage) Util.execArgv(["xdg-open", root.homepage])
  }

  function openLog() {
    if (root.logPath) Util.execArgv(["xdg-open", root.logPath])
  }

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width, Style.space(460))
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
      text: root.appName
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      visible: root.appVersion.length > 0
      text: "version " + root.appVersion
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      text: root.firstRun
        ? "Your passwords, kept by pass and reachable from the bar."
        : "A password manager for Omarchy, backed by the pass command."
      color: root.foreground
      opacity: 0.75
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    // The three things worth knowing before the first search.
    Column {
      width: parent.width
      spacing: Style.space(5)

      Repeater {
        model: [
          { key: "type", label: "to search" },
          { key: "⏎", label: "copies the password" },
          { key: "^N", label: "adds a new entry" }
        ]

        Row {
          required property var modelData
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Text {
            width: Style.space(34)
            text: modelData.key
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
          }

          Text {
            text: modelData.label
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: root.entryCount > 0
      text: root.entryCount === 1 ? "1 password in your store"
                                  : root.entryCount + " passwords in your store"
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }

    // Debug log, when the user has turned it on.
    Column {
      width: parent.width
      visible: root.logging
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: "󰈙  Open debug log"
        color: logArea.containsMouse ? root.accent : root.foreground
        opacity: logArea.containsMouse ? 1 : 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter

        MouseArea {
          id: logArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openLog()
        }
      }

      Text {
        width: parent.width
        text: "no passwords or entry names are written to it"
        color: root.foreground
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
      radius: Style.cornerRadius
      color: Util.alpha(root.accent, continueArea.containsMouse ? 0.24 : 0.16)

      Text {
        anchors.centerIn: parent
        text: root.firstRun ? "⏎   Get started" : "⏎   Close"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      MouseArea {
        id: continueArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismissed()
      }
    }

    Text {
      width: parent.width
      visible: root.homepage.length > 0
      text: root.homepage.replace(/^https:\/\//, "")
      color: linkArea.containsMouse ? root.accent : root.foreground
      opacity: linkArea.containsMouse ? 1 : 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter

      MouseArea {
        id: linkArea
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openHomepage()
      }
    }
  }
}
