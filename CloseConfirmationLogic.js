.pragma library

function acceptPresentation(currentGeneration, lastSequence, candidateGeneration, candidateSequence) {
  var generation = Number(candidateGeneration)
  var sequence = Number(candidateSequence)
  if (!isFinite(generation) || !isFinite(sequence) || generation < currentGeneration)
    return { accepted: false }

  if (generation > currentGeneration) lastSequence = -1
  if (sequence <= lastSequence) return { accepted: false }
  return { accepted: true, generation: generation, sequence: sequence }
}

function hideOpenPlugin(shell, pluginId) {
  if (!shell || typeof shell.isPluginOpen !== "function"
      || typeof shell.hide !== "function" || !shell.isPluginOpen(pluginId)) return false
  shell.hide(pluginId)
  return true
}

function dismissLayer(shell, namespace) {
  var plugins = ({
    "omarchy-menu": "omarchy.menu",
    "omarchy-image-selector": "omarchy.image-picker",
    "omarchy-emojis": "omarchy.emojis",
    "omarchy-clipboard": "omarchy.clipboard",
    "omarchy-reminders": "omarchy.reminders",
    "omarchy-network-qr": "omarchy.wifiqr",
    "omarchy-network-speedtest": "omarchy.speedtest",
    "omarchy-disk-speedtest": "omarchy.disk-speedtest"
  })

  if (plugins[namespace])
    return hideOpenPlugin(shell, plugins[namespace]) ? "dismissed" : "stale"

  if (namespace === "omarchy-keyboard-panel") {
    if (!shell || !shell.barWidgetRegistry
        || typeof shell.barWidgetRegistry.availableIds !== "function") return "unavailable"
    var openPanels = []
    var ids = shell.barWidgetRegistry.availableIds()
    for (var index = 0; index < ids.length; index++) {
      var id = ids[index]
      if (shell.isBarWidgetPanelPlugin(id) && shell.isPluginOpen(id)) openPanels.push(id)
    }
    if (openPanels.length !== 1) return "ambiguous"
    shell.hide(openPanels[0])
    return "dismissed"
  }

  if (namespace === "omarchy-polkit") {
    var polkit = shell && shell.serviceFor ? shell.serviceFor("omarchy.polkit") : null
    if (!polkit || !polkit.dialogVisible || typeof polkit.cancelRequest !== "function") return "stale"
    polkit.cancelRequest()
    return "dismissed"
  }

  if (namespace === "omarchy-lock-preview") {
    var lock = shell && shell.serviceFor ? shell.serviceFor("omarchy.lock") : null
    if (!lock || !lock.previewVisible) return "stale"
    lock.previewVisible = false
    return "dismissed"
  }

  return "unsupported"
}
