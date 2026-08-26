#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy plugin validate "$plugin_dir"
qmllint -I "$OMARCHY_PATH/shell" \
  "$plugin_dir/VpnState.qml" \
  "$plugin_dir/WindscribeIcon.qml" \
  "$plugin_dir/WorldMap.qml" \
  "$plugin_dir/Traffic.qml" \
  "$plugin_dir/BarWidget.qml" \
  "$plugin_dir/Panel.qml"

if command -v node >/dev/null 2>&1; then
  node --test "$plugin_dir/tests/model.test.js"
fi
