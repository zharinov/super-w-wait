import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "CloseConfirmationLogic.js" as Logic

Item {
  id: root

  property var shell: null
  property bool opened: false
  property real presentationGeneration: -1
  property real lastPresentationSequence: -1
  property string monitorName: ""
  property real windowX: 0
  property real windowY: 0
  property real windowWidth: 0
  property real windowHeight: 0
  property string message: "SUPER + W again to close"
  property int duration: 0

  function hideNow() {
    opened = false
    hideTimer.stop()
  }

  function acceptPresentation(candidateGeneration, candidateSequence) {
    var result = Logic.acceptPresentation(presentationGeneration, lastPresentationSequence,
                                          candidateGeneration, candidateSequence)
    if (!result.accepted) return false
    presentationGeneration = result.generation
    lastPresentationSequence = result.sequence
    return true
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

  function show(candidateGeneration, candidateSequence, monitor, x, y, width, height, timeout) {
    if (!acceptPresentation(candidateGeneration, candidateSequence)) return "stale"

    var parsedX = Number(x)
    var parsedY = Number(y)
    var parsedWidth = Number(width)
    var parsedHeight = Number(height)
    var parsedTimeout = Number(timeout)
    var validGeometry = validNumber(parsedX) && validNumber(parsedY)
                     && validNumber(parsedWidth) && parsedWidth > 0
                     && validNumber(parsedHeight) && parsedHeight > 0
    if (!validGeometry || !validNumber(parsedTimeout) || !hasScreen(monitor)) {
      hideNow()
      return "invalid"
    }

    monitorName = monitor
    windowX = parsedX
    windowY = parsedY
    windowWidth = parsedWidth
    windowHeight = parsedHeight
    duration = Math.max(250, Math.min(10000, Math.round(parsedTimeout)))
    opened = true
    hideTimer.restart()
    return "shown"
  }

  function hidePresentation(candidateGeneration, candidateSequence) {
    if (!acceptPresentation(candidateGeneration, candidateSequence)) return "stale"
    hideNow()
    return "hidden"
  }

  function dismissLayer(namespace) {
    return Logic.dismissLayer(shell, namespace)
  }

  function close() {
    hideNow()
  }

  IpcHandler {
    target: "super-w-wait"

    function show(generation: string, sequence: string, monitor: string, x: string, y: string,
                  width: string, height: string, timeout: string): string {
      return root.show(generation, sequence, monitor, x, y, width, height, timeout)
    }

    function hide(generation: string, sequence: string): string {
      return root.hidePresentation(generation, sequence)
    }

    function dismissLayer(namespace: string): string {
      return root.dismissLayer(namespace)
    }

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        monitorName: root.monitorName,
        presentationGeneration: root.presentationGeneration,
        lastPresentationSequence: root.lastPresentationSequence
      })
    }
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.hideNow()
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
