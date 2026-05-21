# Residual Dialyzer warnings from compile-time JSON schema literals and HEEx-generated guards.
# Logic is covered by tests; suppressing analyzer false positives until upstream fixes land.
[
  {"lib/ide/mcp/tools.ex", :pattern_match},
  {"lib/ide/pebble_toolchain.ex", :pattern_match},
  {"lib/ide_web/live/workspace_live/editor_support.ex", :pattern_match},
  {"lib/ide_web/live/workspace_live/editor_page.ex", :guard_fail}
]
