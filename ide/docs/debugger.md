# Debugger: UI and MCP

The debugger has two surfaces that share the same runtime (`Ide.Debugger`) but different ergonomics.

## Human UI (Debugger pane)

The LiveView pane focuses on day-to-day inspection:

- **Timeline** — update messages (watch / companion / mixed). Click a row to move the cursor; **j** / **k** step older/newer when the pane is focused.
- **Models** — watch and companion JSON at the cursor.
- **Rendered view** — live watch tree preview; hover highlights nodes.
- **Start / profile** — session controls and watch profile selection.
- **Subscriptions** — trigger buttons, auto-fire toggles, configuration modal.
- **Copy for agent** — markdown export of visible timeline + models + rendered view (`DebuggerSupport.debugger_agent_state_markdown/1`).

Trace export/import, replay forms, fingerprint compare tables, and other agent-oriented workflows were removed from the UI. Use MCP (or “Copy for agent”) for those.

LiveView assigns are limited to what the pane renders. Helpers such as `replay_preview_rows/2`, `replay_metadata_at_cursor/2`, and `runtime_fingerprints_at_cursor/2` live in `IdeWeb.WorkspaceLive.DebuggerSupport` for tests and MCP, not for hidden form state.

## MCP (`debugger.*` tools)

Agents call `Ide.Mcp.Handlers.Debugger`, which talks to `Ide.Debugger` directly (no LiveView socket). Typical tools:

| Tool | Purpose |
|------|---------|
| `debugger.state` | Snapshot, optional replay metadata and runtime fingerprints |
| `debugger.cursor_inspect` | Diagnostics, introspect, tables at a cursor |
| `debugger.render_tree` | Flattened render nodes for a surface |
| `debugger.replay_recent` | Replay recent `update_in` messages |
| `debugger.continue_from_snapshot` | Resume live runtime from a cursor |
| `debugger.export_trace` / `debugger.import_trace` | Trace exchange (JSON) |
| `debugger.auto_tick_*`, triggers, simulator settings | Session control |

Pass explicit `cursor_seq`, `compare_cursor_seq`, and `baseline_cursor_seq` in MCP args; the IDE no longer mirrors those in LiveView assigns.

## Code map

| Layer | Module |
|-------|--------|
| Runtime | `Ide.Debugger`, `ide/lib/ide/debugger/*` |
| LiveView UI | `IdeWeb.WorkspaceLive.DebuggerPage`, `DebuggerSupport` (assigns + shared query helpers) |
| MCP | `Ide.Mcp.Handlers.Debugger` |

When adding behavior, prefer extending `Ide.Debugger` and MCP tools; add LiveView UI only when humans need the same control in the pane.
