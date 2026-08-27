import QtQuick
import QtTest
import "../CloseConfirmationLogic.js" as Logic

TestCase {
  name: "CloseConfirmationLogic"

  function shellWithOpenPlugins(openPlugins) {
    return {
      hidden: [],
      openPlugins: openPlugins || [],
      isPluginOpen: function(id) { return this.openPlugins.indexOf(id) !== -1 },
      hide: function(id) { this.hidden.push(id) }
    }
  }

  function test_presentationOrdering() {
    var accepted = Logic.acceptPresentation(-1, -1, 10, 1)
    verify(accepted.accepted)
    compare(accepted.generation, 10)
    compare(accepted.sequence, 1)

    verify(!Logic.acceptPresentation(10, 1, 9, 99).accepted)
    verify(!Logic.acceptPresentation(10, 1, 10, 1).accepted)
    verify(Logic.acceptPresentation(10, 1, 10, 2).accepted)
    verify(Logic.acceptPresentation(10, 99, 11, 1).accepted)
  }

  function test_pluginNamespaces() {
    var routes = {
      "omarchy-menu": "omarchy.menu",
      "omarchy-image-selector": "omarchy.image-picker",
      "omarchy-emojis": "omarchy.emojis",
      "omarchy-clipboard": "omarchy.clipboard",
      "omarchy-reminders": "omarchy.reminders",
      "omarchy-network-qr": "omarchy.wifiqr",
      "omarchy-network-speedtest": "omarchy.speedtest",
      "omarchy-disk-speedtest": "omarchy.disk-speedtest"
    }

    for (var namespace in routes) {
      var shell = shellWithOpenPlugins([routes[namespace]])
      compare(Logic.dismissLayer(shell, namespace), "dismissed")
      compare(shell.hidden.length, 1)
      compare(shell.hidden[0], routes[namespace])
    }
  }

  function test_pluginMustStillBeOpen() {
    var shell = shellWithOpenPlugins([])
    compare(Logic.dismissLayer(shell, "omarchy-menu"), "stale")
    compare(shell.hidden.length, 0)
  }

  function test_keyboardPanel() {
    var shell = shellWithOpenPlugins(["panel.one"])
    shell.barWidgetRegistry = { availableIds: function() { return ["panel.one", "other"] } }
    shell.isBarWidgetPanelPlugin = function(id) { return id.indexOf("panel.") === 0 }
    compare(Logic.dismissLayer(shell, "omarchy-keyboard-panel"), "dismissed")
    compare(shell.hidden[0], "panel.one")

    shell = shellWithOpenPlugins(["panel.one", "panel.two"])
    shell.barWidgetRegistry = { availableIds: function() { return ["panel.one", "panel.two"] } }
    shell.isBarWidgetPanelPlugin = function() { return true }
    compare(Logic.dismissLayer(shell, "omarchy-keyboard-panel"), "ambiguous")
    compare(shell.hidden.length, 0)
  }

  function test_polkit() {
    var cancelled = false
    var shell = {
      serviceFor: function() {
        return { dialogVisible: true, cancelRequest: function() { cancelled = true } }
      }
    }
    compare(Logic.dismissLayer(shell, "omarchy-polkit"), "dismissed")
    verify(cancelled)
  }

  function test_lockPreview() {
    var lock = { previewVisible: true }
    var shell = { serviceFor: function() { return lock } }
    compare(Logic.dismissLayer(shell, "omarchy-lock-preview"), "dismissed")
    verify(!lock.previewVisible)
  }

  function test_unknownLayer() {
    compare(Logic.dismissLayer(shellWithOpenPlugins([]), "third-party"), "unsupported")
  }
}
