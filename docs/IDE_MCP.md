# IDE MCP Server

This document describes the experimental MCP server shipped with `ide/`.

For the complementary agent session integration, see `docs/IDE_ACP.md`. ACP is
used for IDE-to-agent conversations; this MCP server remains the IDE tool
surface that those agents can attach to.

## Run

From `ide/`:

```bash
mix ide.mcp --capabilities read,edit,build
```

The server speaks JSON-RPC over stdio using `Content-Length` framing.

## HTTP Endpoint

The Phoenix app also exposes the same MCP dispatcher over HTTP:

```text
POST /api/mcp
```

Example Zed remote MCP configuration:

```json
{
  "context_servers": {
    "elm-pebble-ide-remote": {
      "url": "http://localhost:4000/api/mcp"
    }
  }
}
```

Configure the remote endpoint from **Settings → MCP / ACP access**:

- enable/disable `POST /api/mcp`
- set the HTTP port used by deployed IDE instances
- select remote MCP access rights (`read`, `edit`, `build`)

Port changes apply after restarting the IDE server. In production, `PORT` still
has precedence; when `PORT` is not set, the IDE reads the persisted MCP HTTP
port from the settings file.

Clients may pass `?capabilities=read` to narrow the configured scope, but cannot
escalate beyond the server-side settings.

## Capability Scopes

- `read`:
  - `projects.list`
  - `projects.tree`
  - `projects.graph`
  - `files.read`
  - `packages.search`
  - `packages.details`
  - `packages.versions`
  - `packages.readme`
  - `audit.recent`
  - `compiler.check_cached`
  - `compiler.check_recent`
  - `compiler.compile_cached`
  - `compiler.compile_recent`
  - `compiler.manifest_cached`
  - `compiler.manifest_recent`
  - `sessions.recent_activity`
  - `sessions.summary`
  - `sessions.trace_health`
  - `traces.bundle`
  - `traces.summary`
  - `traces.export`
  - `traces.exports_list`
  - `traces.policy`
  - `traces.policy_validate`
  - `debugger.state`
  - `debugger.export_trace`
  - `debugger.cursor_inspect`
- `edit`:
  - `files.write`
  - `packages.add_to_elm_json`
  - `packages.remove_from_elm_json`
  - `traces.export_write`
  - `traces.exports_prune`
  - `traces.maintenance`
  - `debugger.start`
  - `debugger.reset`
  - `debugger.reload`
  - `debugger.step`
  - `debugger.tick`
  - `debugger.auto_tick_start`
  - `debugger.auto_tick_stop`
  - `debugger.replay_recent`
  - `debugger.continue_from_snapshot`
  - `debugger.import_trace`
- `build`:
  - `pebble.package`
  - `pebble.install`
  - `screenshots.capture`
  - `compiler.check`
  - `compiler.compile`
  - `compiler.manifest`

Capability scope is deny-by-default. Calling a tool outside scope returns an
error.

## Tool Response Format

`tools/call` returns:

- `content` with a JSON-encoded payload string for tool output.
- `isError` boolean.
- `_meta.trace_id` for deterministic action tracing.

`tools/list` also returns:

- `_meta.catalog_version` to support client-side cache invalidation.

## Package Catalog Tools

Package tools expose a provider-agnostic package browsing flow:

- `packages.search` supports `query`, optional `page` / `per_page`, and optional `source`.
- `packages.details` returns package metadata, latest version, and available versions.
- `packages.versions` returns known versions for a package.
- `packages.readme` returns markdown README (`version` defaults to `latest`).
- `packages.add_to_elm_json` writes a package dependency into project `elm.json` using
  compatibility-based auto-version selection.
- `packages.remove_from_elm_json` removes a **direct** dependency, re-resolves indirect
  dependencies, and refuses removal for required runtime packages such as
  `elm/core`, `elm/json`, `elm/time`, and Pebble platform packages.

Provider selection:

- `source: "official"` resolves through [package.elm-lang.org](https://package.elm-lang.org/).
- `source: "mirror"` resolves through [dark.elm.dmy.fr](https://dark.elm.dmy.fr/).
- Omitting `source` uses configured provider order/fallback.

## Audit Log

All tool calls append trace entries to:

`ide/priv/mcp/audit.log`

Each line is JSON containing at least:

- `at`
- `trace_id`
- `action`
- `status`
- `arguments`

For `files.write`, `arguments.content` is redacted and replaced by:

- `content_redacted`
- `content_bytes`

Failed calls also include `error`.

Read recent entries through `audit.recent`.
Most read-context tools also support an optional `since` ISO8601 filter to
bound results to a recent iteration window.

Use `traces.bundle` for reproducible trace workflows. It correlates:

- audit entries (filterable by `trace_id`, `slug`, `since`)
- latest compiler cache entries (`check`, `compile`, `manifest`)
- recent compiler cache history for the same slug

Use `traces.summary` when prompt budget is tight. It returns:

- compact window counters (`audit_entries`, `checks`, `compiles`, `manifests`)
- latest status snapshot (`check`, `compile`, `manifest`, `manifest_strict`)
- per-action totals with ok/error counts

Use `traces.export` for deterministic replay artifacts. It returns:

- canonical JSON (`export_json`) with stable key ordering
- `export_sha256` checksum for integrity/reproducibility checks

Use `traces.export_write` to persist that deterministic export to disk under:

- `ide/priv/mcp/trace_exports/`

It returns file metadata (`path`, `file_name`, `bytes`) plus trace identifiers and
checksum.

Use `traces.exports_list` to inspect persisted exports (with optional `limit`), and
`traces.exports_prune` to keep only the newest N exports (`keep_latest`).

Use `traces.maintenance` for one-call housekeeping:

- evaluates health against configurable thresholds (`warn_count`, `warn_bytes`)
- supports dry-run (`apply: false`) and mutation mode (`apply: true`)
- when needed, prunes toward `target_keep_latest` and returns before/after health
- includes `policy_validation` findings/status to surface risky policy defaults

## Compiler Context Cache

`compiler.check` writes its result into an in-memory cache for low-latency
context access.

Use:

- `compiler.check_cached` to read the latest result for a specific project.
- `compiler.check_recent` to read recent check history (optionally filtered by
  project slug), with optional `since` filtering.

`compiler.compile` also writes compile results into an in-memory cache.

Use:

- `compiler.compile_cached` to read the latest compile result for a project.
- `compiler.compile_recent` to read recent compile history (optionally filtered
  by project slug), with optional `since` filtering.

`compiler.manifest` also writes manifest results into an in-memory cache.

Use:

- `compiler.manifest_cached` to read the latest manifest result for a project.
- `compiler.manifest_recent` to read recent manifest history (optionally
  filtered by project slug), with optional `since` filtering.

`compiler.manifest` accepts optional `strict: true`:

- when `strict` is `false` (default), manifest normalization issues are emitted
  as warnings in diagnostics.
- when `strict` is `true`, any manifest normalization warning promotes manifest
  status to `error` and appends a strict-mode failure diagnostic.

Manifest payloads are normalized to a stable shape:

- `schema_version`
- `supported_packages`
- `excluded_packages`
- `modules_detected`

If payload fields are missing or malformed, warnings are emitted in diagnostics
and fallback empty lists are used.

## Session Context

Use `sessions.recent_activity` to get per-project context for AI agents:

- project metadata
- screenshot counts
- latest and recent cached checks
- latest manifest strict-mode flag (`latest_manifest_strict`)
- recent audited tool actions tied to the same project slug

The tool accepts `limit`, optional `slug`, and optional `since` (ISO8601).

Use `sessions.summary` when prompt budget is tight and you only need compact
status/count fields per project.

When manifest runs are present, summary also includes:

- `latest_manifest_status`
- `latest_manifest_strict` (true when the latest manifest run used strict mode)

Use `sessions.trace_health` to monitor trace export storage health. It provides:

- aggregate count/bytes plus oldest/newest export timestamps
- warning status based on configurable thresholds (`warn_count`, `warn_bytes`)
- cleanup guidance and a `suggested_keep_latest` value for pruning
- `policy_validation` findings/status for policy-risk visibility

If thresholds are omitted, defaults come from `config/config.exs`:

- `config :ide, Ide.Mcp.Tools, trace_policy: [...]`
- keys: `warn_count`, `warn_bytes`, `keep_latest`, `target_keep_latest`

Use `traces.policy` to read both configured values and effective defaults as seen
by the running MCP process.

Use `traces.policy_validate` to run policy sanity checks and get structured
findings before enabling autonomous maintenance workflows.

Debugger MCP tools:

- `debugger.state` reads runtime snapshots and recent timeline state.
- `debugger.cursor_inspect` reads cursor-scoped update/protocol/render/lifecycle
  rows plus diagnostics and runtime fingerprint comparisons.
- `debugger.export_trace` exports deterministic debugger traces.
- `debugger.start`, `debugger.reset`, and `debugger.reload` manage sessions and
  source-root-scoped reloads.
- `debugger.step`, `debugger.tick`, `debugger.auto_tick_start`, and
  `debugger.auto_tick_stop` drive deterministic runtime events.
- `debugger.replay_recent`, `debugger.continue_from_snapshot`, and
  `debugger.import_trace` support replay, snapshot continuation, and trace
  restoration workflows.
