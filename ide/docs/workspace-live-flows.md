# WorkspaceLive flow modules

`IdeWeb.WorkspaceLive` is a thin LiveView facade: mount/params, `render/1`, and delegation guards. Project load and navigation call `*Flow` / `EditorSupport` modules directly (no `defdelegate` re-exports on the LiveView). Pane behavior lives in `IdeWeb.WorkspaceLive.*Flow` modules.

## Event routing

| Guard | Module |
|-------|--------|
| `@editor_flow_events` | `EditorFlow` |
| `@resource_flow_events` (`ResourcesFlow.resource_events/0`) | `ResourcesFlow` |
| `@build_flow_events` (`BuildFlow.build_events/0`) | `BuildFlow` |
| `"debugger-" <> _` / `simulator-save-settings` | `DebuggerFlow` |
| `"packages-" <> _` | `PackagesFlow` |
| `@emulator_flow_events` | `EmulatorFlow` |
| `@project_settings_events` | `ProjectSettingsFlow` |
| `@publish_pane_events` | `PublishPaneFlow` |

Event lists are defined on each flow (`editor_events/0`, `build_events/0`, etc.) and referenced from `WorkspaceLive` module attributes.

## Async routing

`WorkspaceLive` uses compile-time module attributes (`@editor_flow_asyncs`, etc.) copied from each flow’s `*_asyncs/0` registry (same pattern as events).

| Registry | Module |
|----------|--------|
| (single) `:debugger_bootstrap` | `DebuggerFlow` |
| `BuildFlow.build_asyncs/0` | `BuildFlow` |
| `EditorFlow.editor_asyncs/0` | `EditorFlow` |
| `EmulatorFlow.emulator_asyncs/0` | `EmulatorFlow` |
| `PublishPaneFlow.publish_asyncs/0` | `PublishPaneFlow` |
| `ProjectSettingsFlow.settings_asyncs/0` | `ProjectSettingsFlow` |
| `PackagesFlow.packages_asyncs/0` | `PackagesFlow` |

## `handle_info` routing

Non-LiveView messages are dispatched through `route_info/2` in `WorkspaceLive` to `DebuggerFlow`, `EmulatorFlow` (`:capture_all_progress`), or `PackagesFlow` (`:packages_search_progress`).

## Business logic vs LiveView handlers

- **`PublishFlow`** — publish readiness, manifest metadata, submit attrs (no `handle_event`).
- **`EditorSupport`** — editor/tab/tree helpers used by `EditorFlow` and `WorkspaceLive` delegates.
- **`*Page`** — HEEx for each pane; no event handlers.

## Regenerating delegations

`ide/scripts/apply_workspace_flow_delegations.py` can strip inline handlers from a monolithic `workspace_live.ex`. It must not remove `render/1` or `handle_info` blocks. Prefer editing delegations by hand once the facade is in place.

## Tests

`test/ide_web/live/workspace_live/flow_delegation_test.exs` checks that flow event registries do not overlap.
