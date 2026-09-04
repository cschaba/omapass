import QtQuick
import qs.Commons
import qs.Ui

// Every shortcut OmaPass has, on one page. The app is keyboard-first by design,
// which is only a virtue while you can find out what the keys are — and the
// footer hints can only ever carry the handful that fit. (#32)
//
// It documents both surfaces at once. A key that works in the pulldown but not
// in the manager is exactly the kind of thing a reader needs told, so the rows
// that differ say where they apply rather than leaving it to be discovered.
Item {
  id: root

  property color background: Color.menu.background
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property bool hasOtpSupport: true
  property bool hasUrlSupport: true
  property bool hasGit: false
  property string openKey: "Super + Alt + P"

  signal dismissed()
  signal aboutRequested()

  // Written once, laid out twice: the columns are split by height below, so
  // adding a row here never means rebalancing them by hand.
  readonly property var groups: [
    { title: "Anywhere", rows: [
      { key: root.openKey, text: "Open or close the manager" },
      { key: "Click the lock", text: "Open the bar pulldown" },
      { key: "Right-click it", text: "Open the manager instead" }
    ] },
    { title: "Finding an entry", rows: [
      { key: "type", text: "Filter the list" },
      { key: "↑  ↓", text: "Move the cursor" },
      { key: "PgUp  PgDn", text: "Move a page" },
      { key: "Home  End", text: "First, last — manager only" },
      { key: "Esc", text: "Clear the search, then close" }
    ] },
    { title: "Using an entry", rows: [
      { key: "⏎", text: "Copy the password" },
      { key: "Shift + ⏎", text: "Type it into the window underneath" },
      { key: "Alt + ⏎", text: "Copy the username" },
      { key: "Alt + N", text: "Copy the entry's own name" },
      { key: "Alt + U", text: "Copy the URL" },
      { key: "Ctrl + U", text: "Open the URL", when: root.hasUrlSupport },
      { key: "Ctrl + L", text: "Fill a login form" },
      { key: "Ctrl + O", text: "Copy the one-time code", when: root.hasOtpSupport },
      { key: "Ctrl + Shift + O", text: "Type the one-time code", when: root.hasOtpSupport }
    ] },
    { title: "Managing the store", rows: [
      { key: "Ctrl + N", text: "New entry" },
      { key: "Ctrl + E", text: "Edit the selected entry" },
      { key: "Ctrl + R", text: "Reveal the password — manager only" },
      { key: "Ctrl + Q", text: "Scan a QR code into it — manager only", when: root.hasOtpSupport },
      { key: "Del  ·  Ctrl + D", text: "Delete it — manager only" },
      { key: "Ctrl + S", text: "git pull --rebase && git push — manager only", when: root.hasGit },
      { key: "Tab", text: "Unlock, or load the details" }
    ] },
    { title: "In the editor", rows: [
      { key: "Ctrl + ⏎", text: "Save" },
      { key: "Esc", text: "Cancel, and discard the draft" },
      { key: "Tab", text: "Next field" }
    ] },
    { title: "This sheet", rows: [
      { key: "F1", text: "Show or hide" },
      { key: "Esc", text: "Hide" }
    ] }
  ]

  // Split so the two columns come out roughly level. Counting rows rather than
  // groups, because "Using an entry" is three times the size of "This sheet".
  readonly property var shownGroups: {
    var out = []
    for (var i = 0; i < root.groups.length; i++) {
      var g = root.groups[i]
      var rows = []
      for (var j = 0; j < g.rows.length; j++)
        if (g.rows[j].when === undefined || g.rows[j].when === true) rows.push(g.rows[j])
      if (rows.length) out.push({ title: g.title, rows: rows })
    }
    return out
  }

  readonly property int splitAt: {
    var total = 0
    for (var i = 0; i < root.shownGroups.length; i++)
      total += root.shownGroups[i].rows.length + 1
    var run = 0
    for (var k = 0; k < root.shownGroups.length; k++) {
      run += root.shownGroups[k].rows.length + 1
      if (run >= total / 2) return k + 1
    }
    return root.shownGroups.length
  }

  function columnGroups(second) {
    var out = []
    for (var i = 0; i < root.shownGroups.length; i++)
      if ((i >= root.splitAt) === second) out.push(root.shownGroups[i])
    return out
  }

  // One delegate, used by both columns. A Loader with sourceComponent cannot
  // initialise a required property, so the columns are plain Repeaters — the
  // shape QML expects, and one less thing to be clever about.
  Component {
    id: groupDelegate

    Column {
      required property var modelData
      width: parent ? parent.width : 0
      spacing: Style.space(3)

      Text {
        text: parent.modelData.title.toUpperCase()
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        bottomPadding: Style.space(4)
      }

      Repeater {
        model: parent.modelData.rows

        Row {
          required property var modelData
          spacing: Style.space(10)

          Text {
            width: Style.space(140)
            text: parent.modelData.key
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            text: parent.modelData.text
            color: root.accent
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  // Its own background, rather than trusting whatever is underneath to get out
  // of the way. It was transparent once, over a list that stayed put, and the
  // two sets of text sat on top of each other. A sheet that is only readable
  // while every sibling cooperates is one refactor from being unreadable. (#32)
  Rectangle {
    anchors.fill: parent
    color: root.background
  }

  // Nothing below is clickable through it either — hover included, or rows
  // light up under a sheet that is covering them.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: {}
  }

  Flickable {
    anchors.fill: parent
    contentHeight: sheet.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: sheet
      width: parent.width
      spacing: Style.space(16)

      Text {
        width: parent.width
        text: "Keyboard shortcuts"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Row {
        width: parent.width
        spacing: Style.space(28)

        Column {
          width: (parent.width - Style.space(28)) / 2
          spacing: Style.space(14)
          Repeater { model: root.columnGroups(false); delegate: groupDelegate }
        }

        Column {
          width: (parent.width - Style.space(28)) / 2
          spacing: Style.space(14)
          Repeater { model: root.columnGroups(true); delegate: groupDelegate }
        }
      }

      PanelSeparator { width: parent.width }

      Row {
        width: parent.width
        spacing: Style.space(16)

        Text {
          text: "About OmaPass"
          color: aboutArea.containsMouse ? root.accent : root.foreground
          opacity: aboutArea.containsMouse ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            id: aboutArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.aboutRequested()
          }
        }

        Text {
          text: "Close"
          color: closeArea.containsMouse ? root.accent : root.foreground
          opacity: closeArea.containsMouse ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            id: closeArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismissed()
          }
        }
      }
    }
  }
}
