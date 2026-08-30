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
  signal quitRequested()

  // Quitting takes the bar icon away and makes the hotkey inert, so it asks
  // first and shows the one command that brings it back. A quit whose undo is
  // undiscoverable is a trap, not a feature.
  property bool confirmingQuit: false
  readonly property string pluginId: service ? service.setting("id", "cschaba.omapass") : "cschaba.omapass"

  readonly property string appName: service ? service.setting("name", "OmaPass") : "OmaPass"
  readonly property string appVersion: service && service.status ? (service.status.version || "") : ""
  readonly property string homepage: service ? service.setting("homepage", "") : ""
  readonly property int entryCount: service && service.status ? (service.status.entries || 0) : 0

  // Only offered while logging is on. A link to a file that does not exist is
  // worse than no link.
  readonly property bool logging: service ? service.setting("log", false) === true : false
  readonly property string logPath: service ? service.setting("logPath", "") : ""

  // What the tooltips say before anyone clicks: the action, and where it goes.
  readonly property string homepageLabel: root.homepage.replace(/^https:\/\//, "")
  readonly property string homepageHint: "Open " + root.homepageLabel + " in your browser"

  function openHomepage() {
    // Through the helper, which sends http(s) to omarchy-launch-browser and
    // everything else to xdg-open. One answer to "how does omapass open a
    // link", wherever the link is.
    if (root.homepage && root.service) root.service.openLink(root.homepage)
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

    // The version is the thing people reach for when they want to know what
    // this is and where it came from, so it is the thing that takes them
    // there. The tooltip names the destination first — a link that only tells
    // you where it went after you followed it is not much of an offer. (#36)
    Text {
      width: parent.width
      visible: root.appVersion.length > 0
      text: "version " + root.appVersion
      color: versionArea.containsMouse ? root.accent : root.foreground
      opacity: versionArea.containsMouse ? 1 : 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter

      MouseArea {
        id: versionArea
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        enabled: root.homepage.length > 0
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openHomepage()

        PanelToolTip {
          visible: versionArea.containsMouse
          text: root.homepageHint
        }
      }
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

    // Says so either way. "I turned logging on and got nothing" is answered
    // fastest by the app admitting whether it thinks logging is on at all.
    Text {
      width: parent.width
      visible: !root.logging
      text: "Debug log off — set  log = on  in ~/.config/omapass/config"
      color: root.foreground
      opacity: 0.4
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
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

    // Quit
    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        visible: !root.confirmingQuit
        text: "󰗼  Quit OmaPass"
        color: quitArea.containsMouse ? Color.urgent : root.foreground
        opacity: quitArea.containsMouse ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter

        MouseArea {
          id: quitArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.confirmingQuit = true
        }
      }

      Column {
        width: parent.width
        visible: root.confirmingQuit
        spacing: Style.space(4)

        Text {
          width: parent.width
          text: "Stop OmaPass? The bar icon and the hotkey stop working."
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "It stays installed. Start it again with:\nomarchy plugin enable " + root.pluginId
          color: root.foreground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(16)

          Text {
            text: "Cancel"
            color: cancelArea.containsMouse ? root.accent : root.foreground
            opacity: cancelArea.containsMouse ? 1 : 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              id: cancelArea
              anchors.fill: parent
              anchors.margins: -Style.space(5)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.confirmingQuit = false
            }
          }

          Text {
            text: "Quit"
            color: Color.urgent
            opacity: confirmArea.containsMouse ? 1 : 0.85
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              id: confirmArea
              anchors.fill: parent
              anchors.margins: -Style.space(5)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.confirmingQuit = false
                root.quitRequested()
              }
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: root.homepage.length > 0
      text: root.homepageLabel
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

        PanelToolTip {
          visible: linkArea.containsMouse
          text: root.homepageHint
        }
      }
    }
  }
}
