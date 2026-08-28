#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy plugin validate "$plugin_dir"
bash -n "$plugin_dir/scripts/bounded-output"
bash -n "$plugin_dir/scripts/install-cli"
qmllint --max-warnings 0 -I "$OMARCHY_PATH/shell" \
  "$plugin_dir/VpnState.qml" \
  "$plugin_dir/WindscribeIcon.qml" \
  "$plugin_dir/BarWidget.qml" \
  "$plugin_dir/Panel.qml"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck \
    "$plugin_dir/scripts/bounded-output" \
    "$plugin_dir/scripts/install-cli" \
    "$plugin_dir/scripts/validate.sh"
fi

if command -v node >/dev/null 2>&1; then
  node --test "$plugin_dir"/tests/*.test.js
fi
