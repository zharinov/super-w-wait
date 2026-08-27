#!/bin/bash

set -euo pipefail

hypr_dir="$HOME/.config/hypr"
bindings="$hypr_dir/bindings.lua"
module="$hypr_dir/super-w-wait.lua"
start_marker="-- super-w-wait:start"
end_marker="-- super-w-wait:end"
require_line='require("super-w-wait")'

if [[ -L "$bindings" ]]; then
  echo "Symlinked Hyprland bindings are not supported: $bindings" >&2
  exit 1
fi

if [[ -f "$bindings" ]]; then
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
else
  integration_state="absent"
fi

[[ "$integration_state" != "malformed" ]] || {
  echo "The managed bindings block in $bindings is incomplete or duplicated." >&2
  exit 1
}

if [[ "$integration_state" == "managed" ]]; then
  backup="$bindings.bak.super-w-wait-uninstall.$(date -u +%Y%m%d%H%M%S)"
  temporary=$(mktemp "$hypr_dir/.bindings.lua.super-w-wait.XXXXXX")
  cp -- "$bindings" "$backup"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$bindings" >"$temporary"
  chmod --reference="$bindings" "$temporary"
  mv -- "$temporary" "$bindings"
  echo "Updated $bindings (backup: $backup)"
fi

if [[ -f "$module" ]]; then
  rm -- "$module"
fi

if ! hyprctl reload >/dev/null; then
  echo "Hyprland did not reload, but uninstall still completed." >&2
else
  errors=$(hyprctl configerrors || true)
  [[ -z "$errors" ]] || printf 'Hyprland reports these configuration errors after removal:\n%s\n' "$errors" >&2
fi

echo "Removed the Hyprland module and key binding."
