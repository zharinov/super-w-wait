local options = rawget(_G, "super_w_wait") or {}
local close_confirmation_timeout = math.floor(assert(tonumber(options.timeout), "super_w_wait.timeout is required"))
close_confirmation_timeout = math.max(250, math.min(10000, close_confirmation_timeout))

local close_confirmation_session = tostring({}):gsub("[^%w]", "")
local close_confirmation_sequence = 0
local close_confirmation_focus_generation = 0
local close_confirmation_ipc_target = "super-w-wait"

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
end

local function send_close_confirmation(method, arguments)
  close_confirmation_sequence = close_confirmation_sequence + 1
  local command = {
    "omarchy-shell",
    "-q",
    close_confirmation_ipc_target,
    method,
    shell_quote(close_confirmation_session),
    tostring(close_confirmation_sequence),
  }

  for _, argument in ipairs(arguments or {}) do
    table.insert(command, shell_quote(argument))
  end

  hl.exec_cmd(table.concat(command, " "))
end


send_close_confirmation("begin", { close_confirmation_focus_generation })

local function cancel_close_confirmation()
  send_close_confirmation("cancel", { close_confirmation_focus_generation })
end

hl.on("window.active", function()
  close_confirmation_focus_generation = close_confirmation_focus_generation + 1
  cancel_close_confirmation()
end)

local function cancel_closed_window(window)
  if window ~= nil and window.address ~= nil then
    send_close_confirmation("cancelTarget", { window.address })
  end
end

hl.on("window.close", cancel_closed_window)
hl.on("window.destroy", cancel_closed_window)
hl.on("monitor.layout_changed", cancel_close_confirmation)
hl.on("monitor.removed", cancel_close_confirmation)

hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window (press twice)", function()
  local active_window = hl.get_active_window()

  if active_window == nil or active_window.monitor == nil then
    cancel_close_confirmation()
    return
  end

  local monitor = active_window.monitor
  send_close_confirmation("press", {
    close_confirmation_focus_generation,
    active_window.address,
    monitor.name,
    math.floor(active_window.at.x - monitor.x),
    math.floor(active_window.at.y - monitor.y),
    math.floor(active_window.size.x),
    math.floor(active_window.size.y),
    close_confirmation_timeout,
  })
end)

hl.layer_rule({
  match = { namespace = "^super-w-wait$" },
  no_anim = true,
  animation = "none",
})

return true
