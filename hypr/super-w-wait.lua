local configured_options = rawget(_G, "super_w_wait")
local options = configured_options == nil and {} or configured_options
local close_confirmation_timeout = 1500

assert(type(options) == "table", "super_w_wait must be a table")
if options.timeout ~= nil then
  local configured_timeout = assert(tonumber(options.timeout),
    "super_w_wait.timeout must be a number")
  assert(configured_timeout == configured_timeout
    and configured_timeout ~= math.huge and configured_timeout ~= -math.huge,
    "super_w_wait.timeout must be finite")
  close_confirmation_timeout = math.floor(configured_timeout)
  close_confirmation_timeout = math.max(250, math.min(10000, close_confirmation_timeout))
end

local immediate_close_tag = "io.github.zharinov.super-w-wait.immediate-close"
local immediate_close_rules = {
  { class = "^org\\.omarchy\\.btop$" },
  { class = "^org\\.omarchy\\.about$" },
  { class = "^omacalc$" },
  { class = "^mpv$" },
  { class = "^imv$" },
  { class = "^org\\.gnome\\.NautilusPreviewer$" },
  { class = "^1[Pp]assword$", title = "^Quick Access — 1Password$" },
  { class = "^xdg-desktop-portal-gtk$" },
  {
    class = "^(sublime_text|DesktopEditors|org\\.gnome\\.Nautilus)$",
    title = "^(Open.*Files?|Open [Ff]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to (open|save).*|[Cc]hoose.*)$",
  },
  { tag = "pip" },
  { tag = "chromium-based-browser", title = "^Meet - .+" },
}

local close_confirmation_ipc_target = "super-w-wait"
-- IPC only controls presentation; close authority stays in this Lua state.
local runtime_directory = assert(os.getenv("XDG_RUNTIME_DIR"), "XDG_RUNTIME_DIR is required")
local instance = assert(os.getenv("HYPRLAND_INSTANCE_SIGNATURE"),
  "HYPRLAND_INSTANCE_SIGNATURE is required"):gsub("[^%w_.-]", "_")
local presentation_generation_path = runtime_directory
  .. "/super-w-wait-presentation-generation-" .. instance
local presentation_generation_file = io.open(presentation_generation_path, "r")
local previous_presentation_generation = 0
if presentation_generation_file then
  previous_presentation_generation = tonumber(presentation_generation_file:read("*l"))
  presentation_generation_file:close()
end
assert(previous_presentation_generation and previous_presentation_generation >= 0
  and previous_presentation_generation <= 9007199254740990
  and previous_presentation_generation == math.floor(previous_presentation_generation),
  "invalid super-w-wait presentation generation")
local close_confirmation_presentation_generation = previous_presentation_generation + 1
local pending_generation_path = presentation_generation_path .. ".new"
presentation_generation_file = assert(io.open(pending_generation_path, "w"),
  "cannot persist super-w-wait presentation generation")
assert(presentation_generation_file:write(close_confirmation_presentation_generation, "\n"))
assert(presentation_generation_file:close())
assert(os.rename(pending_generation_path, presentation_generation_path))
local close_confirmation_sequence = 0
local close_confirmation_generation = 0
local close_confirmation_target = nil
local close_confirmation_ready = false

local dismissible_layer_namespaces = {
  ["omarchy-menu"] = true,
  ["omarchy-image-selector"] = true,
  ["omarchy-emojis"] = true,
  ["omarchy-clipboard"] = true,
  ["omarchy-reminders"] = true,
  ["omarchy-network-qr"] = true,
  ["omarchy-network-speedtest"] = true,
  ["omarchy-disk-speedtest"] = true,
  ["omarchy-keyboard-panel"] = true,
  ["omarchy-polkit"] = true,
  ["omarchy-lock-preview"] = true,
}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
end

local function send_ipc(method, arguments)
  local command = {
    "omarchy-shell",
    "-q",
    close_confirmation_ipc_target,
    method,
  }

  for _, argument in ipairs(arguments or {}) do
    table.insert(command, shell_quote(argument))
  end

  hl.exec_cmd(table.concat(command, " "))
end

local function send_close_confirmation(method, arguments)
  close_confirmation_sequence = close_confirmation_sequence + 1
  local ordered_arguments = {
    close_confirmation_presentation_generation,
    close_confirmation_sequence,
  }
  for _, argument in ipairs(arguments or {}) do
    table.insert(ordered_arguments, argument)
  end
  send_ipc(method, ordered_arguments)
end

local function cancel_close_confirmation()
  close_confirmation_generation = close_confirmation_generation + 1
  close_confirmation_target = nil
  close_confirmation_ready = false
  send_close_confirmation("hide")
end

local function closes_immediately(window)
  local tags = window.tags
  if type(tags) == "string" then
    return tags == immediate_close_tag or tags == immediate_close_tag .. "*"
  end

  if type(tags) ~= "table" then
    return false
  end

  for _, tag in pairs(tags) do
    if tag == immediate_close_tag or tag == immediate_close_tag .. "*" then
      return true
    end
  end

  return false
end

local function mapped_interactive_layers()
  local ok, layers = pcall(hl.get_layers)
  if not ok or type(layers) ~= "table" then
    return nil
  end

  local interactive_layers = {}
  for _, layer in pairs(layers) do
    if layer.mapped ~= false then
      local interactivity = tonumber(layer.interactivity)
      if interactivity == nil then
        return nil
      end
      if interactivity ~= 0 then
        table.insert(interactive_layers, layer)
      end
    end
  end

  return interactive_layers
end

local function window_snapshot(window)
  local monitor = window and window.monitor
  local at = window and window.at
  local size = window and window.size
  if window == nil or window.mapped ~= true or window.hidden ~= false
    or window.visible ~= true or window.accepts_input ~= true
    or window.stable_id == nil or type(window.address) ~= "string" or monitor == nil
    or type(monitor.name) ~= "string" or at == nil or size == nil
    or tonumber(at.x) == nil or tonumber(at.y) == nil
    or tonumber(monitor.x) == nil or tonumber(monitor.y) == nil
    or tonumber(size.x) == nil or tonumber(size.y) == nil
    or tonumber(size.x) <= 0 or tonumber(size.y) <= 0 then
    return nil
  end

  return {
    window = window,
    stable_id = window.stable_id,
    address = window.address,
    monitor = monitor.name,
    x = math.floor(at.x - monitor.x),
    y = math.floor(at.y - monitor.y),
    width = math.floor(size.x),
    height = math.floor(size.y),
  }
end

local function same_target(first, second)
  return first ~= nil and second ~= nil
    and first.address == second.address
    and first.stable_id == second.stable_id
    and first.monitor == second.monitor
    and first.x == second.x and first.y == second.y
    and first.width == second.width and first.height == second.height
end

local function arm_close_confirmation(target)
  -- One-shot timers outlive disarm, so stale callbacks must not affect a newer target.
  close_confirmation_generation = close_confirmation_generation + 1
  local generation = close_confirmation_generation
  close_confirmation_target = target
  close_confirmation_ready = false

  send_close_confirmation("show", {
    target.monitor,
    target.x,
    target.y,
    target.width,
    target.height,
    close_confirmation_timeout,
  })

  hl.timer(function()
    if generation == close_confirmation_generation and close_confirmation_target ~= nil then
      close_confirmation_ready = true
    end
  end, { timeout = 75, type = "oneshot" })

  hl.timer(function()
    if generation == close_confirmation_generation then
      cancel_close_confirmation()
    end
  end, { timeout = close_confirmation_timeout, type = "oneshot" })
end

send_close_confirmation("hide")

hl.on("window.active", function()
  cancel_close_confirmation()
end)

local function cancel_closed_window(window)
  if close_confirmation_target ~= nil and window ~= nil
    and window.address == close_confirmation_target.address then
    cancel_close_confirmation()
  end
end

hl.on("window.close", cancel_closed_window)
hl.on("window.destroy", cancel_closed_window)
hl.on("monitor.layout_changed", cancel_close_confirmation)
hl.on("monitor.removed", cancel_close_confirmation)

hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window (press twice)", function()
  local interactive_layers = mapped_interactive_layers()
  if interactive_layers == nil then
    cancel_close_confirmation()
    return
  end

  if #interactive_layers > 0 then
    cancel_close_confirmation()
    if #interactive_layers == 1 then
      local namespace = interactive_layers[1].namespace
      if dismissible_layer_namespaces[namespace] then
        send_ipc("dismissLayer", { namespace })
      end
    end
    return
  end

  local active_window = hl.get_active_window()
  local active_target = window_snapshot(active_window)

  if active_target == nil then
    cancel_close_confirmation()
    return
  end

  if closes_immediately(active_window) then
    cancel_close_confirmation()
    hl.dispatch(hl.dsp.window.close({ window = active_window }))
    return
  end

  if same_target(close_confirmation_target, active_target) then
    if not close_confirmation_ready then
      return
    end

    cancel_close_confirmation()
    hl.dispatch(hl.dsp.window.close({ window = active_window }))
    return
  end

  arm_close_confirmation(active_target)
end)

for _, match in ipairs(immediate_close_rules) do
  hl.window_rule({
    match = match,
    tag = "+" .. immediate_close_tag,
  })
end

hl.layer_rule({
  match = { namespace = "^super-w-wait$" },
  no_anim = true,
  animation = "none",
})

return true
