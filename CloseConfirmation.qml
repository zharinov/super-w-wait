import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property bool opened: false
  property bool closeAuthorized: false
  property string session: ""
  property real lastSequence: -1
  property real focusGeneration: -1
  property string windowAddress: ""
  property string monitorName: ""
  property real windowX: 0
  property real windowY: 0
  property real windowWidth: 0
  property real windowHeight: 0
  property string message: "SUPER + W again to close"
  property int duration: 0

  function disarm() {
    opened = false
    closeAuthorized = false
    windowAddress = ""
    readyTimer.stop()
    hideTimer.stop()
  }

  function hasScreen(name) {
    for (var index = 0; index < Quickshell.screens.length; index++) {
      if (Quickshell.screens[index].name === name) return true
    }
    return false
  }

  function validNumber(value) {
    return !isNaN(value) && isFinite(value)
  }

  function acceptSequence(candidateSession, candidateSequence) {
    var sequence = Number(candidateSequence)
    if (candidateSession !== session || !validNumber(sequence) || sequence <= lastSequence) return false
    lastSequence = sequence
    return true
  }

  function begin(candidateSession, candidateSequence, candidateFocusGeneration) {
    var sequence = Number(candidateSequence)
    var generation = Number(candidateFocusGeneration)
    if (!candidateSession || !validNumber(sequence) || !validNumber(generation)) return "invalid"

    disarm()
    session = candidateSession
    lastSequence = sequence
    focusGeneration = generation
    return "ready"
  }

  function cancel(candidateSession, candidateSequence, candidateFocusGeneration) {
    if (!acceptSequence(candidateSession, candidateSequence)) return "stale"
    var generation = Number(candidateFocusGeneration)
    if (!validNumber(generation)) return "invalid"
    focusGeneration = generation
    disarm()
    return "cancelled"
  }

  function cancelTarget(candidateSession, candidateSequence, address) {
    if (!acceptSequence(candidateSession, candidateSequence)) return "stale"
    if (address === windowAddress) disarm()
    return "ok"
  }

  function press(candidateSession, candidateSequence, candidateFocusGeneration,
                 address, monitor, x, y, width, height, timeout) {
    var sequence = Number(candidateSequence)
    var generation = Number(candidateFocusGeneration)
    var parsedX = Number(x)
    var parsedY = Number(y)
    var parsedWidth = Number(width)
    var parsedHeight = Number(height)
    var parsedTimeout = Number(timeout)
    var validAddress = /^0x[0-9a-fA-F]+$/.test(address)
    var validGeometry = validNumber(parsedX) && validNumber(parsedY)
                     && validNumber(parsedWidth) && parsedWidth > 0
                     && validNumber(parsedHeight) && parsedHeight > 0
    if (!candidateSession || !validNumber(sequence) || !validNumber(generation)
        || !validAddress || !validGeometry
        || !validNumber(parsedTimeout) || !hasScreen(monitor)) {
      disarm()
      return "invalid"
    }

    if (session !== candidateSession) {
      disarm()
      session = candidateSession
      lastSequence = sequence
    } else if (!acceptSequence(candidateSession, sequence)) {
      return "stale"
    }

    var sameTarget = opened && windowAddress === address
                  && focusGeneration === generation
                  && monitorName === monitor
                  && windowX === parsedX && windowY === parsedY
                  && windowWidth === parsedWidth && windowHeight === parsedHeight

    if (sameTarget && closeAuthorized) {
      var targetAddress = address
      disarm()
      Quickshell.execDetached([
        "hyprctl",
        "dispatch",
        "hl.dsp.window.close({ window = \"address:" + targetAddress + "\" })"
      ])
      return "closed"
    }

    if (sameTarget) return "presenting"

    focusGeneration = generation
    windowAddress = address
    monitorName = monitor
    windowX = parsedX
    windowY = parsedY
    windowWidth = parsedWidth
    windowHeight = parsedHeight
    duration = Math.max(250, Math.min(10000, Math.round(parsedTimeout)))
    closeAuthorized = false
    opened = true
    readyTimer.restart()
    hideTimer.restart()
    return "armed"
  }

  function close() {
    disarm()
  }

  IpcHandler {
    target: "super-w-wait"

    function begin(session: string, sequence: string, focusGeneration: string): string {
      return root.begin(session, sequence, focusGeneration)
    }

    function press(session: string, sequence: string, focusGeneration: string,
                   address: string, monitor: string, x: string, y: string,
                   width: string, height: string, timeout: string): string {
      return root.press(session, sequence, focusGeneration, address, monitor,
                        x, y, width, height, timeout)
    }

    function cancel(session: string, sequence: string, focusGeneration: string): string {
      return root.cancel(session, sequence, focusGeneration)
    }

    function cancelTarget(session: string, sequence: string, address: string): string {
      return root.cancelTarget(session, sequence, address)
    }

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        closeAuthorized: root.closeAuthorized,
        session: root.session,
        lastSequence: root.lastSequence,
        focusGeneration: root.focusGeneration,
        windowAddress: root.windowAddress
      })
    }
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.disarm()
  }

  Timer {
    id: readyTimer
    interval: 75
    onTriggered: {
      if (root.opened) root.closeAuthorized = true
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel

      required property var modelData
      screen: modelData
      visible: root.opened && modelData.name === root.monitorName
      anchors {
        top: true
        right: true
        bottom: true
        left: true
      }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      WlrLayershell.namespace: "super-w-wait"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Rectangle {
        id: card

        readonly property real desiredX: root.windowX + (root.windowWidth - width) / 2
        readonly property real desiredY: root.windowY + (root.windowHeight - height) / 2

        x: Math.round(Math.max(12, Math.min(panel.width - width - 12, desiredX)))
        y: Math.round(Math.max(12, Math.min(panel.height - height - 12, desiredY)))
        width: Math.min(panel.width - 24, label.implicitWidth + 48)
        height: 56
        radius: 9
        color: "#3b3b3b"
        border.width: 1
        border.color: "#666666"

        Text {
          id: label

          anchors.centerIn: parent
          width: Math.min(implicitWidth, parent.width - 32)
          text: root.message
          color: "#f2f2f2"
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }
}
