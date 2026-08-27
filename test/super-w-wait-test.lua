local source = debug.getinfo(1, "S").source
local test_directory = source:sub(1, 1) == "@" and source:sub(2):match("^(.*[/\\])") or "test/"
local module_path = test_directory .. "../hypr/super-w-wait.lua"
local immediate_close_tag = "io.github.zharinov.super-w-wait.immediate-close"
local generation_path = "/test/runtime/super-w-wait-presentation-generation-test-instance"
local generation_files = {}

local function generation_file(path, mode)
  if mode == "r" then
    local value = generation_files[path]
    if value == nil then return nil end
    return {
      close = function() return true end,
      read = function() return value end,
    }
  end

  if mode == "w" then
    local value = ""
    return {
      close = function()
        generation_files[path] = value
        return true
      end,
      write = function(_, ...)
        for index = 1, select("#", ...) do
          value = value .. tostring(select(index, ...))
        end
        return true
      end,
    }
  end

  error("unexpected generation file mode: " .. tostring(mode))
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function assert_contains(value, fragment, message)
  if value == nil or not value:find(fragment, 1, true) then
    error((message or "string does not contain expected text") .. ": " .. tostring(value), 2)
  end
end

local function window(address, tags)
  local resolved_address = address or "0xabc"
  return {
    accepts_input = true,
    address = resolved_address,
    at = { x = 110, y = 220 },
    hidden = false,
    mapped = true,
    monitor = { name = "eDP-1", x = 10, y = 20 },
    size = { x = 800, y = 600 },
    stable_id = resolved_address,
    tags = tags or {},
    visible = true,
  }
end

local function new_environment(options, active_window, layers)
  local state = {
    active_window = active_window,
    layers = layers or {},
    bindings = {
      ["SUPER + W"] = {
        description = "Stock close window",
        handler = function()
          error("stock close binding was not replaced")
        end,
      },
    },
    dispatches = {},
    events = {},
    exec_commands = {},
    layer_rules = {},
    timers = {},
    unbound = {},
    window_rules = {},
  }

  _G.super_w_wait = options
  _G.hl = {
    dispatch = function(dispatcher)
      table.insert(state.dispatches, dispatcher)
    end,
    dsp = {
      window = {
        close = function(close_options)
          return { kind = "close", options = close_options }
        end,
      },
    },
    exec_cmd = function(command)
      table.insert(state.exec_commands, command)
    end,
    get_active_window = function()
      return state.active_window
    end,
    get_layers = function()
      if state.layers == "error" then
        error("layer query failed")
      end
      return state.layers
    end,
    layer_rule = function(rule)
      table.insert(state.layer_rules, rule)
    end,
    on = function(event, callback)
      state.events[event] = callback
    end,
    timer = function(callback, options_)
      local timer = { callback = callback, options = options_ }
      table.insert(state.timers, timer)
      return timer
    end,
    unbind = function(keys)
      table.insert(state.unbound, keys)
      state.bindings[keys] = nil
    end,
    window_rule = function(rule)
      table.insert(state.window_rules, rule)
    end,
  }
  _G.o = {
    bind = function(keys, description, handler)
      state.bindings[keys] = { description = description, handler = handler }
    end,
  }

  local real_io = _G.io
  local real_os = _G.os
  _G.io = setmetatable({ open = generation_file }, { __index = real_io })
  _G.os = setmetatable({
    getenv = function(name)
      if name == "XDG_RUNTIME_DIR" then return "/test/runtime" end
      if name == "HYPRLAND_INSTANCE_SIGNATURE" then return "test-instance" end
      return real_os.getenv(name)
    end,
    rename = function(old_path, new_path)
      if generation_files[old_path] == nil then return nil, "missing source" end
      generation_files[new_path] = generation_files[old_path]
      generation_files[old_path] = nil
      return true
    end,
  }, { __index = real_os })
  local chunk, load_error = loadfile(module_path)
  assert(chunk, load_error)
  state.load_ok, state.load_result = pcall(chunk)
  _G.io = real_io
  _G.os = real_os
  return state
end

local function clear_runtime(state)
  state.dispatches = {}
  state.exec_commands = {}
end

local function press(state)
  state.bindings["SUPER + W"].handler()
end

local function fire_timer(state, timeout, latest)
  local first = latest and #state.timers or 1
  local last = latest and 1 or #state.timers
  local step = latest and -1 or 1

  for index = first, last, step do
    local timer = state.timers[index]
    if timer.options.timeout == timeout then
      timer.callback()
      return
    end
  end

  error("timer with timeout " .. timeout .. " not found", 2)
end

local target = window()
local defaults = new_environment(nil, target)
assert(defaults.load_ok, defaults.load_result)
assert_equal(defaults.unbound[1], "SUPER + W", "default close binding must be replaced")

local expected_immediate_rules = {
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
assert_equal(#defaults.window_rules, #expected_immediate_rules,
  "the built-in immediate-close policy must be complete")
for index, match in ipairs(expected_immediate_rules) do
  local rule = defaults.window_rules[index]
  assert_equal(rule.name, nil, "built-in rules must be anonymous")
  assert_equal(rule.match.class, match.class, "built-in rule class")
  assert_equal(rule.match.title, match.title, "built-in rule title")
  assert_equal(rule.match.tag, match.tag, "built-in rule source tag")
  assert_equal(rule.match.float, nil, "floating alone must not imply immediate close")
  assert_equal(rule.match.fullscreen, nil, "fullscreen must not imply immediate close")
  assert_equal(rule.match.modal, nil, "modal alone must not imply immediate close")
  assert_equal(rule.match.pin, nil, "pinning alone must not imply immediate close")
  assert_equal(rule.match.xwayland, nil, "XWayland must not imply immediate close")
  assert_equal(rule.tag, "+" .. immediate_close_tag, "built-in rule tag")
end

clear_runtime(defaults)
press(defaults)
assert_equal(#defaults.dispatches, 0, "the first press must not close")
assert_contains(defaults.exec_commands[1], " show ", "the first press must show the warning")

press(defaults)
assert_equal(#defaults.dispatches, 0, "a premature second press must not close")

fire_timer(defaults, 75)
press(defaults)
assert_equal(#defaults.dispatches, 1, "a ready second press must close")
assert_equal(defaults.dispatches[1].kind, "close", "close must use the graceful dispatcher")
assert_equal(defaults.dispatches[1].options.window, target, "close must target the exact armed window")
local show_generation, show_sequence = defaults.exec_commands[1]:match(" show '([^']+)' '(%d+)'")
local hide_generation, hide_sequence = defaults.exec_commands[2]:match(" hide '([^']+)' '(%d+)'")
assert(show_generation and hide_generation, "presentation commands must include ordering metadata")
assert_equal(hide_generation, show_generation, "presentation commands must share one generation")
assert(tonumber(hide_sequence) > tonumber(show_sequence),
  "a later hide must supersede an earlier show")

local next_load = new_environment(nil, target)
local first_generation = tonumber(show_generation)
local next_generation = tonumber(next_load.exec_commands[1]:match(" hide '(%d+)'"))
assert(first_generation and next_generation and next_generation > first_generation,
  "a fresh Lua state must advance the persisted presentation generation")

local saved_generation = generation_files[generation_path]
for _, corrupt_generation in ipairs({ "invalid\n", "1e309\n", "9007199254740991\n" }) do
  generation_files[generation_path] = corrupt_generation
  local invalid_generation = new_environment(nil, target)
  assert_equal(invalid_generation.load_ok, false,
    "a corrupt persisted generation must fail safely")
  assert_equal(#invalid_generation.exec_commands, 0,
    "a corrupt persisted generation must fail before IPC")
  assert_equal(#invalid_generation.unbound, 0,
    "a corrupt persisted generation must fail before replacing the binding")
end
generation_files[generation_path] = saved_generation

local invalid_options = new_environment("invalid", target)
assert_equal(invalid_options.load_ok, false, "invalid options must fail before setup")
assert_equal(#invalid_options.exec_commands, 0, "invalid options must not send IPC")
assert_equal(#invalid_options.window_rules, 0, "invalid options must not register rules")
assert_equal(#invalid_options.unbound, 0, "invalid options must not replace the stock binding")
assert_equal(next(invalid_options.events), nil, "invalid options must not register events")

local expired = new_environment(nil, target)
clear_runtime(expired)
press(expired)
fire_timer(expired, 75)
fire_timer(expired, 1500)
clear_runtime(expired)
press(expired)
assert_equal(#expired.dispatches, 0, "a press after expiry must start a new confirmation")

local replacement = window("0xdef")
local stale_timers = new_environment(nil, target)
clear_runtime(stale_timers)
press(stale_timers)
stale_timers.active_window = replacement
stale_timers.events["window.active"]()
press(stale_timers)
fire_timer(stale_timers, 75)
fire_timer(stale_timers, 1500)
fire_timer(stale_timers, 75, true)
press(stale_timers)
assert_equal(#stale_timers.dispatches, 1, "the newer confirmation must remain closable")
assert_equal(stale_timers.dispatches[1].options.window, replacement,
  "stale timers must not change the exact target")

local reused_address = window(target.address)
reused_address.stable_id = "replacement-stable-id"
local stable_identity = new_environment(nil, target)
clear_runtime(stable_identity)
press(stable_identity)
fire_timer(stable_identity, 75)
stable_identity.active_window = reused_address
press(stable_identity)
assert_equal(#stable_identity.dispatches, 0,
  "a reused address with a new stable id must start a new confirmation")

local close_event = new_environment(nil, target)
clear_runtime(close_event)
press(close_event)
clear_runtime(close_event)
close_event.events["window.close"](window("0x999"))
assert_equal(#close_event.exec_commands, 0, "an unrelated close must not cancel the warning")
close_event.events["window.destroy"](target)
assert_contains(close_event.exec_commands[1], " hide", "target destruction must cancel the warning")

local immediate_window = window("0xeee", { immediate_close_tag })
local immediate = new_environment(nil, immediate_window)
assert(immediate.load_ok, immediate.load_result)
clear_runtime(immediate)
press(immediate)
assert_equal(#immediate.dispatches, 1, "an exception must close immediately")
assert_equal(immediate.dispatches[1].options.window, immediate_window,
  "an immediate-close window must close the exact active window")

local starred_window = window("0xfff", { immediate_close_tag .. "*" })
local starred = new_environment(nil, starred_window)
clear_runtime(starred)
press(starred)
assert_equal(#starred.dispatches, 1, "a dynamic immediate-close tag must close immediately")
assert_equal(starred.dispatches[1].options.window, starred_window,
  "a dynamic tag must close the exact active window")

local string_tag_window = window("0xaa1", immediate_close_tag .. "*")
local string_tag = new_environment(nil, string_tag_window)
clear_runtime(string_tag)
press(string_tag)
assert_equal(#string_tag.dispatches, 1, "a string-form dynamic tag must close immediately")

local suppressed = new_environment(nil, target, {
  { mapped = true, interactivity = 2, namespace = "third-party-layer" },
})
clear_runtime(suppressed)
press(suppressed)
press(suppressed)
assert_equal(#suppressed.dispatches, 0, "an interactive layer must suppress background closes")
assert_equal(#suppressed.timers, 0, "an interactive layer must not arm the guard")
assert_equal(#suppressed.exec_commands, 2,
  "an unknown layer must only cancel the current warning")

local dismissible_layer = new_environment(nil, nil, {
  { mapped = true, interactivity = 2, namespace = "omarchy-menu" },
})
clear_runtime(dismissible_layer)
press(dismissible_layer)
assert_equal(#dismissible_layer.timers, 0, "a dismissible layer must not arm the guard")
assert_contains(dismissible_layer.exec_commands[2], " dismissLayer ",
  "a known layer must use the shell dismissal path")
assert_contains(dismissible_layer.exec_commands[2], "omarchy-menu",
  "the shell dismissal must identify the mapped layer")

local multiple_layers = new_environment(nil, target, {
  { mapped = true, interactivity = 2, namespace = "omarchy-menu" },
  { mapped = true, interactivity = 1, namespace = "omarchy-polkit" },
})
clear_runtime(multiple_layers)
press(multiple_layers)
assert_equal(#multiple_layers.exec_commands, 1,
  "multiple interactive layers must suppress rather than guess")

local exclusive_layer = new_environment(nil, target, {
  { mapped = true, interactivity = 1, namespace = "selection" },
})
clear_runtime(exclusive_layer)
press(exclusive_layer)
assert_equal(#exclusive_layer.timers, 0, "an exclusive layer must not arm the guard")

local noninteractive_layer = new_environment(nil, target, {
  { mapped = true, interactivity = 0 },
})
clear_runtime(noninteractive_layer)
press(noninteractive_layer)
assert_equal(#noninteractive_layer.timers, 2,
  "a noninteractive layer must not suppress the active window")

local unmapped_layer = new_environment(nil, target, {
  { mapped = false, interactivity = 2 },
})
clear_runtime(unmapped_layer)
press(unmapped_layer)
assert_equal(#unmapped_layer.timers, 2, "an unmapped layer must not suppress the active window")

local layer_error = new_environment(nil, target, "error")
clear_runtime(layer_error)
press(layer_error)
assert_equal(#layer_error.dispatches, 0, "a failed layer query must fail closed")
assert_equal(#layer_error.timers, 0, "a failed layer query must not arm the guard")

print("super-w-wait tests passed")
