pragma Singleton
import QtQuick

// One gate for the whole plugin, rather than one per window.
//
// The manager and the bar pulldown are separate surfaces with separate roots,
// and each used to keep its own `fingerprintPassed`. Nothing connected them,
// so a scan at the pulldown left the manager locked — and `Ctrl+E` there does
// not open an editor in the pulldown, it summons the manager. Authenticating
// and then being asked again a second later, for the same store on the same
// desktop, reads as the first scan having failed. (#50)
//
// Sharing it is not a weakening. The grace window already lets a surface be
// closed and reopened without a second scan, so "recently authenticated
// counts" is already the policy; this only stops it being scoped to whichever
// window happened to ask. The gate defends against someone reaching an
// unattended unlocked desktop, and that threat does not change with which of
// the user's own surfaces they came through — anyone who can press `Ctrl+E` in
// an authenticated pulldown can already read the entries in the pulldown.
//
// It lives in its own directory with its own qmldir on purpose. A qmldir in
// the plugin root would turn that directory into a module and take the other
// components out of implicit reach of the files that reference them.
//
// `keepLoaded: true` means both surfaces share one shell process, so this is
// memory only: never written down, and gone when the shell stops.
QtObject {
  id: root

  // Whether a scan is still good. Both surfaces read this instead of each
  // holding their own answer.
  property bool passed: false

  function markPassed() {
    grace.stop()
    root.passed = true
  }

  // An explicit re-lock, rather than an expiry.
  function lock() {
    grace.stop()
    root.passed = false
  }

  // A surface opened, so a countdown started by some earlier close no longer
  // applies — something is on screen again.
  function hold() {
    grace.stop()
  }

  // A surface closed. The countdown runs from the close rather than from the
  // scan, so a window left open does not expire under the user. A zero grace
  // still fires on the next tick rather than synchronously, which is what
  // keeps it from re-locking a surface that is in the middle of opening.
  function startGrace(ms) {
    if (!root.passed) return
    grace.interval = Math.max(0, ms)
    grace.restart()
  }

  property Timer __grace: Timer {
    id: grace
    onTriggered: root.passed = false
  }
}
