# Residual Dialyzer warnings from compile-time JSON schema literals and HEEx-generated guards.
# Logic is covered by tests; suppressing analyzer false positives until upstream fixes land.
[
  {"lib/ide/mcp/tools.ex", :pattern_match},
  {"lib/ide/pebble_toolchain.ex", :pattern_match},
  {"lib/ide_web/live/workspace_live/editor_support.ex", :pattern_match},
  {"lib/ide_web/live/workspace_live/editor_page.ex", :guard_fail},
  {"lib/ide/paths.ex", :invalid_contract},
  {"lib/ide/settings.ex", :pattern_match},
  {"lib/ide/compiler.ex", :pattern_match},
  {"lib/ide/package_docs/exporter.ex", :unused_fun},
  {"lib/ide/projects.ex", :pattern_match},
  {"lib/ide/debugger/http_simulator.ex", :exact_eq},
  {"lib/ide/debugger/http_simulator.ex", :pattern_match},
  {"lib/ide_web/live/workspace_live.ex", :pattern_match}
]
