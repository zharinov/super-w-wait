#!/bin/bash

set -euo pipefail

ipc_target="super-w-wait"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hypr_dir="$HOME/.config/hypr"
bindings="$hypr_dir/bindings.lua"
module="$hypr_dir/super-w-wait.lua"
start_marker="-- super-w-wait:start"
end_marker="-- super-w-wait:end"
require_line='require("super-w-wait")'

for command in omarchy omarchy-shell hyprctl luac; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -f "$bindings" ]] || {
  echo "Hyprland bindings file not found: $bindings" >&2
  exit 1
}

[[ ! -L "$bindings" ]] || {
  echo "Symlinked Hyprland bindings are not supported: $bindings" >&2
  exit 1
}

integration_state=$(awk -v start="$start_marker" -v require="$require_line" -v end="$end_marker" '
  $0 == start && state == 0 { starts++; state = 1; next }
  $0 == require && state == 1 { requires++; state = 2; next }
  $0 == end && state == 2 { ends++; state = 0; complete++; next }
  $0 == start || $0 == require || $0 == end { malformed = 1 }
  END {
    if (starts == 0 && requires == 0 && ends == 0 && !malformed) print "absent"
    else if (starts == 1 && requires == 1 && ends == 1 && complete == 1 && state == 0 && !malformed) print "managed"
    else print "malformed"
  }
' "$bindings")

[[ "$integration_state" != "malformed" ]] || {
  echo "The managed bindings block in $bindings is incomplete or duplicated." >&2
  exit 1
}

source_module="$script_dir/hypr/super-w-wait.lua"
[[ -f "$source_module" ]] || {
  echo "Hyprland module not found: $source_module" >&2
  exit 1
}

luac -p "$source_module"
omarchy plugin validate "$script_dir"

for ((attempt = 0; attempt < 200; attempt++)); do
  if omarchy-shell "$ipc_target" state >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

omarchy-shell "$ipc_target" state >/dev/null || {
  echo "The plugin is not enabled or Omarchy Shell is unavailable." >&2
  exit 1
}

if [[ -e "$module" ]] && ! cmp -s "$source_module" "$module"; then
  if [[ "$integration_state" != "managed" ]]; then
    echo "Refusing to overwrite an unmanaged file: $module" >&2
    exit 1
  fi
  module_backup="$module.bak.$(date -u +%Y%m%d%H%M%S)"
  cp -- "$module" "$module_backup"
  echo "Backed up the previous Hyprland module to $module_backup"
fi

install -m 0644 "$source_module" "$module"

if [[ "$integration_state" == "absent" ]]; then
  backup="$bindings.bak.super-w-wait.$(date -u +%Y%m%d%H%M%S)"
  cp -- "$bindings" "$backup"
  printf '\n%s\n%s\n%s\n' "$start_marker" "$require_line" "$end_marker" >>"$bindings"
  echo "Updated $bindings (backup: $backup)"
fi

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
[[ -z "$errors" ]] || {
  echo "$errors" >&2
  exit 1
}

echo "Installed the integration."
