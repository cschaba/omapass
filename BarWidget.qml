import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "PassStore.js" as PassStore

// Bar icon with a search pulldown: a field on top, matching entries below.
//
// This is the quick path — find a password and copy it without leaving the
// keyboard. Anything that manages the store (new, edit, delete) hands off to
// the full overlay, so there is one editor rather than two.
Panel {
  id: root
  moduleName: "cschaba.omapass"
  ipcTarget: "cschaba.omapass.widget"

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property string bin: pluginDir + "bin/omapass"

  property string filterText: ""
  property int selectedIndex: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // The bar sizes a slot from its widget's implicit size — a root that does
  // not publish one gets a 0x0 slot and renders nothing at all, silently.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool fingerprintRequired: pass.fingerprintRequired
  property bool fingerprintPassed: false
  readonly property bool vaultLocked: pass.ready && root.fingerprintRequired && !root.fingerprintPassed

  // A per-widget setting in shell.json wins; the config file supplies the
  // default so both surfaces can be tuned from one place.
  readonly property int visibleRows: Math.max(1, setting("rows", pass.setting("pulldownRows", 7)))
  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.controlPaddingY)

  property bool selectedHasOtp: false
  property string fieldsForPath: ""

  readonly property var currentRow: resultModel.count > 0 && selectedIndex >= 0 && selectedIndex < resultModel.count
    ? resultModel.get(selectedIndex) : null
  readonly property string currentPath: currentRow ? currentRow.path : ""

  // --- lifecycle ------------------------------------------------------------

  onOpenedChanged: {
    if (opened) {
      root.filterText = ""
      root.selectedIndex = 0
      pass.refresh()
      searchField.text = ""
    } else if (root.fingerprintPassed) {
      // The pulldown is its own surface, so it keeps its own grace window.
      graceTimer.restart()
    }
  }

  Timer {
    id: graceTimer
    interval: pass.setting("fingerprintGrace", 120) * 1000
    onTriggered: root.fingerprintPassed = false
  }

  function rebuild() {
    var rows = PassStore.filterEntries(pass.entries, root.filterText, 60)

    resultModel.clear()
    for (var i = 0; i < rows.length; i++)
      resultModel.append({ path: rows[i].path, name: rows[i].name, folder: rows[i].folder })

    if (resultModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= resultModel.count) root.selectedIndex = resultModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function () {
      if (resultModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.rebuild()
  }

  function move(delta) {
    if (resultModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + resultModel.count) % resultModel.count
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // Managing entries belongs to the overlay; the pulldown just hands over.
  // The payload says what to do on arrival, so Ctrl+N from here lands on the
  // new-entry form rather than the list with the form one more keystroke away.
  function openManager(action) {
    var payload = { }
    if (action === "new") payload.action = "new"
    else if (action === "edit" && root.currentPath) {
      payload.action = "edit"
      payload.entry = root.currentPath
    }
    root.close()
    Util.execArgv(["omarchy-shell", "shell", "summon", "cschaba.omapass",
                   JSON.stringify(payload)])
  }

  function activate(action) {
    if (root.vaultLocked || !root.currentPath) return
    var path = root.currentPath
    root.close()
    if (action === "type") pass.typePassword(path)
    else if (action === "user") pass.copyUser(path)
    else if (action === "login") pass.typeLogin(path)
    else if (action === "otp") pass.copyOtp(path)
    else if (action === "otp-type") pass.typeOtp(path)
    else pass.copyPassword(path)
  }

  onCurrentPathChanged: {
    if (root.currentPath !== root.fieldsForPath) root.selectedHasOtp = false
    fieldsDebounce.restart()
  }

  // The unlock probe usually finishes after the list does, so the first
  // selection is decided while still locked. Retry when the answer arrives,
  // or the hint never appears for the row that was picked first.
  Connections {
    target: pass
    function onUnlockedChanged() { if (pass.unlocked) fieldsDebounce.restart() }
  }

  // Same rule as the overlay: never decrypt just to draw a hint. Until
  // gpg-agent is warm the OTP action simply is not offered.
  function loadFields() {
    if (!root.opened || !pass.unlocked || root.vaultLocked) return
    if (!root.currentPath || root.currentPath === root.fieldsForPath) return
    pass.loadFields(root.currentPath)
  }

  Timer {
    id: fieldsDebounce
    interval: 180
    onTriggered: root.loadFields()
  }

  ListModel { id: resultModel }

  PassService {
    id: pass
    bin: root.bin
    onListReloaded: root.rebuild()
    onFieldsLoaded: function (path, fields, otp) {
      if (path !== root.currentPath) return
      root.selectedHasOtp = otp
      root.fieldsForPath = path
    }
  }

  Component.onCompleted: pass.refresh()

  // --- bar button -----------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌾"
    tooltipText: pass.ready
      ? (pass.entries.length + (pass.entries.length === 1 ? " password" : " passwords")
         + "  ·  right-click to manage")
      : "omapass needs setting up"
    // Right-click goes straight to the full manager, so the editor is one
    // gesture away from the bar rather than a pulldown and then a link. (#7)
    onPressed: function (b) {
      if (b === Qt.RightButton) root.openManager("")
      else root.toggle()
    }
  }

  // --- pulldown -------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // Focus whatever is actually on screen: forceActiveFocus() on a hidden item
    // quietly does nothing, which left Esc dead on the setup and locked screens
    // — the two states with nothing else to press. (#1)
    focusTarget: (pass.ready && !root.vaultLocked) ? searchField : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The search field is always focused, so it owns the keyboard; this
      // catcher would otherwise eat every letter as a navigation shortcut.
      // Also blocked while the password field is up, or typing a password would
      // be read as navigation.
      blocked: searchField.activeFocus || fingerprintGate.mode === "password"
      onCloseRequested: root.close()
      onTabRequested: if (root.vaultLocked) fingerprintGate.toggleMode()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        // --- search ---------------------------------------------------------

        TextField {
          id: searchField
          width: parent.width
          visible: pass.ready && !root.vaultLocked
          placeholderText: "Search passwords…"
          foreground: root.foreground
          accent: Color.accent
          verticalPadding: Style.spacing.controlPaddingY

          onTextChanged: root.setFilter(text)

          // Navigation has to be intercepted before the field consumes it:
          // Up/Down would move the caret and Return would just be swallowed.
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            var shift = (event.modifiers & Qt.ShiftModifier) !== 0
            var alt = (event.modifiers & Qt.AltModifier) !== 0

            if (event.key === Qt.Key_Escape) {
              if (searchField.text) searchField.text = ""
              else root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.move(1); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.move(-1); event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              root.move(root.visibleRows); event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              root.move(-root.visibleRows); event.accepted = true
            } else if (ctrl && event.key === Qt.Key_O) {
              root.activate(shift ? "otp-type" : "otp"); event.accepted = true
            } else if (ctrl && event.key === Qt.Key_L) {
              root.activate("login"); event.accepted = true
            } else if (ctrl && event.key === Qt.Key_N) {
              root.openManager("new"); event.accepted = true
            } else if (ctrl && event.key === Qt.Key_E) {
              root.openManager("edit"); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activate(alt ? "user" : (shift ? "type" : "copy"))
              event.accepted = true
            }
          }
        }

        // --- results --------------------------------------------------------

        ListView {
          id: resultList
          width: parent.width
          visible: pass.ready && !root.vaultLocked && resultModel.count > 0
          height: visible ? Math.min(resultModel.count, root.visibleRows) * root.rowHeight : 0
          model: resultModel
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: row
            required property int index
            required property string path
            required property string name
            required property string folder

            readonly property bool hasCursor: index === root.selectedIndex

            width: ListView.view.width
            height: root.rowHeight
            radius: Style.cornerRadius
            color: hasCursor ? root.selectedFill : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, row.width - Style.space(24))
                text: row.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - x)
                visible: row.folder.length > 0
                text: row.folder
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideLeft
                horizontalAlignment: Text.AlignRight
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.selectedIndex = row.index
              onClicked: {
                root.selectedIndex = row.index
                root.activate("copy")
              }
            }
          }
        }

        // --- empty / unready states -----------------------------------------

        Text {
          width: parent.width
          visible: pass.ready && !root.vaultLocked && resultModel.count === 0
          text: pass.entries.length === 0 ? "No passwords in your store yet"
                                          : "No matches"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          visible: !pass.ready && !root.vaultLocked
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: "omapass isn’t set up yet"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            text: PassStore.missingRequirements(pass.status)
                    .map(function (r) { return r.label }).join(", ")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }

        FingerprintGate {
          id: fingerprintGate
          width: parent.width
          height: visible ? Style.space(110) : 0
          visible: root.vaultLocked
          armed: root.opened && root.vaultLocked
          passwordAvailable: pass.passwordAuthAvailable
          maxScanFailures: Math.max(1, pass.setting("fingerprintRetries", 1))
          compact: true
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onAuthenticated: {
            root.fingerprintPassed = true
            root.rebuild()
            Qt.callLater(function () { searchField.forceActiveFocus() })
          }
        }

        PanelSeparator { width: parent.width }

        // --- footer ---------------------------------------------------------

        Item {
          width: parent.width
          height: Style.font.caption + Style.space(4)

          ActionHints {
            id: hintLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: pass.ready && !root.vaultLocked
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            spacing: Style.space(10)
            actions: [
              { key: "⏎",  label: "copy", action: function () { root.activate("copy") } },
              { key: "⇧⏎", label: "type", action: function () { root.activate("type") } },
              // Only when this entry actually has one — an action that usually
              // fails is worse than one that is not offered. (#5)
              { key: "^O", label: "otp",  action: function () { root.activate("otp") },
                visible: pass.hasOtpSupport && root.selectedHasOtp }
            ]
          }

          // A way out that does not depend on knowing about Esc. Without this
          // the setup screen is a dead end for anyone reaching for the mouse.
          Text {
            id: closeLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: !hintLabel.visible
            text: "Close"
            color: closeArea.containsMouse ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              id: closeArea
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }

          Text {
            id: manageLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.vaultLocked ? "" : (pass.ready ? "Manage…" : "Set up…")
            color: manageArea.containsMouse ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              id: manageArea
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openManager("")
            }
          }
        }
      }
    }
  }
}
