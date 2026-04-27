# IDE (Phases 1-3)

Standalone Phoenix LiveView app for the Elm-Pebble IDE shell and early workflows.

Implemented in this phase:

- Project CRUD and active project switching (`Ide.Projects`)
- Project-local source roots (`watch`, `protocol`, `phone`) with file operations
- Multi-file editor basics (tree, tabs, open/edit/save/create/rename/delete)
- Project templates on create (`starter`, `smoke-demo`)
- Existing local project import flow with automatic root mapping (`watch/protocol/phone`)
- Tokenizer seam for parser-backed editing groundwork (`POST /api/tokenize`) and editor token diagnostics
- Shell panes/routes for Projects, Editor, Build, Emulator
- Phase-ready boundaries: `Ide.Compiler`, `Ide.PebbleToolchain`, `Ide.Screenshots`
- Diagnostics placeholder seam for parser-backed integration in later phases
- Build/Emulator baseline actions through `Ide.PebbleToolchain` (`pebble build`, `pebble install --emulator`)

## Run locally

```bash
cd ide
mix setup
mix phx.server
```

Open [http://localhost:4000/projects](http://localhost:4000/projects).

## Test

```bash
cd ide
mix test
```

## Data model and storage

- Metadata is stored via Ecto in SQLite (`config/dev.exs` / `config/test.exs`).
- Project files are stored on disk under `ide/workspace_projects/<project-slug>/`.
- Source roots are created automatically for each project.

## Pebble toolchain and screenshots

- Build and emulator actions currently target the IDE template app at `ide/priv/pebble_app_template/`.
- Configure in `ide/config/config.exs` via `Ide.PebbleToolchain`:
  - `template_app_root`
  - `emulator_target`
  - optional `pebble_bin`
- Emulator screenshots are captured and displayed in the IDE, grouped by watch model/emulator.
- Screenshot assets are stored under `ide/priv/static/screenshots/<project-slug>/<emulator-target>/` and can be reused later in publish flows.
- Emulator pane supports one-click capture for all configured watch models.
- Build pane includes publish prep: PBW artifact generation plus screenshot coverage checklist per model.
- Build pane can export `publish-bundle-*.json` metadata linking the PBW artifact and per-model screenshot sets.
- Build pane validates app metadata (`build/appinfo.json`) and can export a release notes draft markdown.

## Formatter groundwork

- Editor pane now includes a `Format` button for `.elm` files.
- `Ide.Formatter` runs with parser-backed semantic pipeline/edit ops enabled (`config/config.exs`: `semantics_pipeline`, `semantic_edit_ops`).
- Formatter parity tooling is available through `mix formatter.parity` with phased gates (`A/B/C`), baselines, and sharding support for CI.
- Formatter parity harness against upstream `elm-format` fixtures is available via:

```bash
cd ide
mix formatter.parity --limit 25
mix formatter.parity --json-output tmp/formatter-parity-report.json
mix formatter.parity --baseline tmp/formatter-parity-baseline.json --update-baseline
mix formatter.parity --baseline tmp/formatter-parity-baseline.json
mix formatter.certify --phase B --baseline tmp/formatter-parity-baseline.json
```

- `comparable_parity_pct` excludes reference formatter failures.
- `actionable_parity_pct` excludes known fixture limitations (recommended CI gate metric).
- If a shard contains no actionable fixtures, phase gating is skipped for that shard.

## MCP capability map

- `read`: project/file/package read operations, compiler cache/history context, debugger state/export/cursor inspection, trace/audit summaries.
- `edit`: file writes, package mutation, debugger control (`start/reset/reload/step/tick/auto_tick_start/auto_tick_stop/replay_recent/import_trace`), trace maintenance, project mutation (`projects.create`, `projects.delete`).
- `build`: compiler execution (`check/compile/manifest`), Pebble package/install workflows (`pebble.package`, `pebble.install`), and screenshot capture (`screenshots.capture`).

### Debugger MCP polling flags

For lower-overhead agent polling, debugger read tools support replay metadata controls:

- `debugger.state`:
  - `replay_metadata_only: true` returns `{slug, event_window, replay_metadata?, runtime_fingerprint_digest}` (no full `state` payload).
  - `include_replay_metadata: false` skips replay metadata extraction entirely.
  - `compare_cursor_seq: <non-negative integer>` (optional) adds `runtime_fingerprint_compare` against that baseline cursor.
  - Full payloads include `runtime_fingerprints` and `runtime_fingerprint_digest` for latest-snapshot runtime provenance (including protocol ingress digest fields: `protocol_inbound_count`, `protocol_message_count`, `protocol_last_inbound_message`).
- `debugger.cursor_inspect`:
  - `replay_metadata_only: true` returns only `{slug, cursor_seq, event_window, replay_metadata?}`.
  - `include_replay_metadata: false` omits `replay_metadata` from the inspect payload.
  - `compare_cursor_seq: <non-negative integer>` (optional) adds `runtime_fingerprint_compare` for selected-cursor drift checks.
  - Full payloads include `runtime_fingerprints` and `runtime_fingerprint_digest` at the selected cursor, including protocol ingress digest fields when present.
- `debugger.replay_recent`:
  - `replay_mode: "frozen" | "live"` (optional) tags replay telemetry mode for MCP-driven replay calls.
  - `replay_drift_seq: <non-negative integer>` (optional) records live-drift distance in telemetry (`drift_seq` / `drift_band`).
- `debugger.tick`:
  - `target: watch | companion | protocol | phone` (optional) scopes deterministic subscription-style tick ingress to a single surface.
  - `count: 1..50` (optional) injects multiple sequential ticks in one call.
- `debugger.auto_tick_start` / `debugger.auto_tick_stop`:
  - `debugger.auto_tick_start` accepts optional `target`, `count`, and `interval_ms` (100..60000) to begin periodic deterministic tick ingress.
  - `debugger.auto_tick_stop` halts periodic tick ingress.
- `debugger.export_trace`:
  - `compare_cursor_seq: <non-negative integer>` and `baseline_cursor_seq: <non-negative integer>` (optional) anchor export `runtime_fingerprint_compare` summaries for offline drift analysis.

Typical lightweight polling examples:

```json
{ "name": "debugger.state", "arguments": { "slug": "my-project", "replay_metadata_only": true } }
```

```json
{ "name": "debugger.cursor_inspect", "arguments": { "slug": "my-project", "include_replay_metadata": false } }
```

```json
{ "name": "debugger.cursor_inspect", "arguments": { "slug": "my-project", "replay_metadata_only": true } }
```

```json
{ "name": "debugger.replay_recent", "arguments": { "slug": "my-project", "target": "watch", "count": 1, "replay_mode": "live", "replay_drift_seq": 4 } }
```

```json
{ "name": "debugger.tick", "arguments": { "slug": "my-project", "target": "watch", "count": 2 } }
```

```json
{ "name": "debugger.auto_tick_start", "arguments": { "slug": "my-project", "target": "watch", "interval_ms": 1000 } }
```

```json
{ "name": "debugger.export_trace", "arguments": { "slug": "my-project", "event_limit": 200, "compare_cursor_seq": 120, "baseline_cursor_seq": 80 } }
```
