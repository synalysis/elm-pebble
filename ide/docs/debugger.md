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

## Debugger start performance

Clicking **Start** in the Debugger pane:

1. Starts the session and warms compile artifacts for watch and protocol roots (phone is deferred when async companion bootstrap is enabled).
2. Hot-reloads watch `Main.elm` (parser introspect + optional Elm executor + init follow-ups).
3. In a background task (default): compiles the phone root, ingests artifacts, then hot-reloads `CompanionApp.elm` (parser + external Elm executor + init/protocol follow-ups; can exceed 30s on templates such as Tangram).

The UI returns after the watch bootstrap; companion configuration, phone-side state, and persisted auto-fire subscription settings are applied when the background task finishes. Set `config :ide, :debugger_async_companion_bootstrap, false` to compile phone and reload companion inline with watch bootstrap (used in tests).

`Agent.get/3` on the debugger store uses the same long timeout as reloads (not the 5s Agent default), so snapshot reads wait behind an in-flight companion bootstrap instead of crashing the LiveView process.

Elm introspection parses in-memory sources via `GeneratedParser.parse_source/2` (no temp files). `elm/http` follow-ups from init/update are queued and started in background tasks by default so the companion model is visible immediately; HTTP requests run concurrently and each response is applied via `update` when it completes (completion order, not request order). Set `config :ide, :debugger_async_http_followups, false` for synchronous, in-order HTTP inside the Agent (tests).

## Code map

| Layer | Module |
|-------|--------|
| Runtime | `Ide.Debugger`, `ide/lib/ide/debugger/*` |
| LiveView UI | `IdeWeb.WorkspaceLive.DebuggerPage`, `DebuggerSupport` (assigns + shared query helpers) |
| MCP | `Ide.Mcp.Handlers.Debugger` |

When adding behavior, prefer extending `Ide.Debugger` and MCP tools; add LiveView UI only when humans need the same control in the pane.
