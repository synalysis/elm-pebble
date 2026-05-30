# Debugger: UI and MCP

The debugger has two surfaces that share the same runtime (`Ide.Debugger`) but different ergonomics.

## Human UI (Debugger pane)

The LiveView pane focuses on day-to-day inspection:

- **Timeline** — update messages (watch / companion / mixed). Click a row to move the cursor; **j** / **k** step older/newer when the pane is focused.
- **Models** — watch and companion JSON at the cursor.
- **Rendered view** — live watch tree preview; hover highlights nodes.
- **Start / profile** — session controls and watch profile selection.
- **Subscriptions** — trigger buttons, auto-fire toggles, configuration modal.
- **Copy for agent** (IDE debug mode only) — markdown export of visible timeline + models + rendered view (`DebuggerSupport.debugger_agent_state_markdown/1`).

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

AppMessage delivery (`FromWatch` / `FromPhone` subscription steps) is deferred the same way by default: only `protocol_tx` is logged when the watch sends; `protocol_rx` and the recipient `update` run after the phone/watch surface has finished `init` (queued in `AppMessageQueue` until then, then delivered in a background task when async). Set `config :ide, :debugger_async_protocol_delivery, false` for synchronous delivery (tests). LiveView subscribes to `debugger:runtime:<scope_key>` and refreshes when background HTTP or protocol work completes.

Watch bootstrap clears the main “Starting debugger…” busy state immediately when async companion loading is enabled. Async companion reload uses parser-only init (`RuntimeExecutor.execute_introspect_only`, no `ElmExecutorAdapter`) and defers `InitSurfaceEffects` plus protocol queue drain to `DeferredCompanionInit` so reload returns before the companion banner times out. A second blocking compile during reload is skipped while `debugger_skip_blocking_compile` is set. Optional phone `elmc` runs in a separate background task only when needed (`config :ide, :debugger_lazy_elmc`, default `true`): companion lacks Core IR and the parser view still needs evaluation. It does not hold the companion bootstrap banner or block reload. HTTP and protocol follow-ups continue in the background; LiveView refreshes on `debugger:runtime:<scope_key>` PubSub with a short debounce (`config :ide, :debugger_runtime_refresh_debounce_ms`, default `100`) so timeline/models update as each step completes. Synchronous companion bootstrap (`config :ide, :debugger_async_companion_bootstrap, false`) still compiles phone before reload (tests). Set `config :ide, :debugger_lazy_elmc, false` to schedule compile whenever Core IR is missing. Set `config :ide, :debugger_companion_reload_await_idle, true` to block companion reload on the full HTTP/protocol idle queue even when async bootstrap is enabled. **Copy for agent** re-reads the debugger Agent snapshot so the exported timeline is not stale socket assigns.

## Template corpus tests (MCP)

`mix test test/ide/mcp/debugger_template_corpus_test.exs --only template_corpus` exercises every project template via MCP:

1. `projects.create` with the template key
2. `debugger.start`, `debugger.set_watch_profile`, `debugger.set_simulator_settings`
3. `debugger.reload` for phone (when the template ships a companion app) then watch `Main.elm`
4. Snapshot via `debugger.models`, `debugger.render_tree`, `debugger.preview_diagnostics`, and canonical preview SVG ops (`DebuggerPreview.svg_ops/2`)

Golden fixtures live under `ide/test/fixtures/debugger_template_corpus/<template>.json`. Refresh them after intentional preview changes:

```bash
UPDATE_DEBUGGER_TEMPLATE_SNAPSHOTS=1 mix test test/ide/mcp/debugger_template_corpus_test.exs --only template_corpus
```

## Visual preview pipeline

The debugger watch SVG preview is **view-only**: it does not re-run `init` or `update` when refreshing layout. Given the surface `model` at the timeline cursor:

1. **Core IR (preferred)** — When `elm_executor_core_ir` is present on the execution model, `SemanticExecutor.derive_view_output_for_runtime_model/2` evaluates `Main.view(model)` through Core IR, normalizes the result tree, then derives drawable rows (`fillRect`, `text`, vectors, etc.). This matches step execution semantics for `if`, `case`, `let`, and qualified calls.
2. **Parser tree fallback** — If Core IR is missing or view evaluation yields no drawable rows, the introspected parser `view_tree` is evaluated via `derive_view_output_preview/3` (integer ops, `if`/`let` nodes, field access). Full `case` pattern matching without Core IR is not supported (branch patterns are not in the parser tree).

Preview output is not patched after the fact (no clock-string heuristics or model-field guessing). If evaluation cannot produce drawable rows, the preview stays empty or shows unresolved nodes until Core IR or parser evaluation succeeds.

The evaluated or parser tree is attached to the surface as `:view_tree` when introspection marks it usable, for hover bounds in `DebuggerPreview`.

## Subscription steps vs timeline rows

A subscription trigger (for example `MinuteChanged`) is not always a single timeline row:

1. **Ingress** — `SubscriptionPayload` builds the wire message (for example `MinuteChanged 42` from simulator clock fields). The model at this row reflects only what Elm `update` returned for that message (for example Tangram leaves `now` unchanged and schedules `getCurrentDateTime`).
2. **Elm step** — The primary `update` row shows the returned model and any `Cmd` calls introspect lists for that branch (for example `getCurrentDateTime`).
3. **Device follow-up** — `DeviceDataResponses` matches those cmds via `DeviceRequest.from_cmd_call/1` (by `name` or qualified `target`, such as `PebbleCmd.getCurrentDateTime`). Simulator clock fields from the triggering subscription are used only to build the synthetic device **response** value, not to patch the model before Elm handles the callback. A second `apply_step_once` with `message_source: "device_data"` adds a **`CurrentDateTime`** (or other callback) row when the branch declares the callback constructor.
4. **Preview refresh** — `RuntimePreview` re-derives `Main.view(model)` from the cursor model for SVG output; it does not re-run `update`. Clock text on a `MinuteChanged` row therefore stays at the previous `now` until the `CurrentDateTime` row runs.

If a device callback row is missing, check that introspect lists the cmd on that branch and that delivery is not still queued (`:debugger_async_protocol_delivery`).

## Step pipeline modules

When a subscription or init message is applied, the debugger runtime walks these modules in order (egress before ingress for protocol; preview is view-only):

| Stage | Module | Role |
|-------|--------|------|
| Step entry | `Ide.Debugger.StepApply` | Chooses surface, normalizes message value, calls runtime executor |
| Step context | `Ide.Debugger.StepApplyContext`, `StepApplyCallbacks` | Host callbacks, protocol events ctx, device/cmd followups |
| Runtime step | `Ide.Debugger.RuntimeExecutor`, `RuntimeFollowups` | Elm/Core IR `update`, model patch, followup queue |
| Protocol egress | `Ide.Debugger.ProtocolEvents` (facade), `.CmdCall`, `.Subscription` | `Cmd` → timeline `protocol_tx` / `protocol_rx` rows |
| Protocol ingress | `Ide.Debugger.ProtocolRx`, `ProtocolRuntimePatch` | Companion/watch delivery, model patch from wire |
| Device data | `Ide.Debugger.DeviceDataResponses`, `DeviceRequest` | Simulated or introspect-matched device callbacks |
| Introspect | `Ide.Debugger.ElmIntrospect`, `ElmIntrospectSnapshot` | Parser outlines, cmd/subscription lists for branches |
| Preview | `Ide.Debugger.RuntimePreview`, `RuntimeArtifacts` | `Main.view` / Core IR drawable rows at cursor (no re-run of `update`) |
| Timeline | `Ide.Debugger.TimelineMessage`, `EventLog` | Row labels, cursor metadata, export |

Configuration and bootstrap (`BootstrapInit`, `InitCmdFollowups`, `DeferredCompanionInit`, `PendingProtocolDelivery`) run around reload; they use the same protocol and introspect modules but are not part of every single step.

## Code map

| Layer | Module |
|-------|--------|
| Runtime | `Ide.Debugger`, `ide/lib/ide/debugger/*` |
| LiveView UI | `IdeWeb.WorkspaceLive.DebuggerPage`, `DebuggerFlow` (debugger `handle_event`s), `DebuggerSupport` (facade) |
| DebuggerSupport | `Types`, `Live`, `Timeline`, `Rendered`, `Replay`, `Export`, `Diagnostics`, `Util` under `debugger_support/` |
| MCP | `Ide.Mcp.Handlers.Debugger` |

`DebuggerSupport` keeps the public API (`defdelegate` from the facade). Regenerate the split from the monolith backup with `mix run --no-compile --no-start scripts/split_debugger_support.exs` (source: `/tmp/debugger_support.monolith.ex`).

When adding behavior, prefer extending `Ide.Debugger` and MCP tools; add LiveView UI only when humans need the same control in the pane.
