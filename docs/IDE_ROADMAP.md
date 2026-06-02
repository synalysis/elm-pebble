# IDE Roadmap

This document describes the current IDE architecture and the remaining work that
matters for publishing and day-to-day Elm Pebble development. It intentionally
avoids preserving old phase plans or historical implementation logs.

## Current Product Shape

The repository now contains a Phoenix LiveView IDE for building Pebble watch
apps and watchfaces in Elm. The IDE supports:

- project creation from app/watchface/tutorial templates
- multi-root editing for `watch`, `protocol`, and `phone` source trees
- CodeMirror editing with LSP-backed formatting, completions, diagnostics,
  hover, document links, and folding
- package browsing, documentation, compatibility badges, and dependency edits
- `elmc` check/compile/manifest integration
- Pebble packaging, install, emulator targeting, screenshots, and release
  readiness checks
- a debugger tab with runtime state, timeline events, model/view inspection,
  replay, snapshots, tick controls, and MCP access
- dark/light/system theming across the IDE

## Repository Shape

Primary source areas:

- `ide/` - Phoenix LiveView IDE, MCP/ACP surfaces, editor integration, project
  templates, package docs, and Pebble publish orchestration
- `ide/priv/pebble_app_template/` - Pebble app shell copied into per-project
  publish builds
- `elmc/` - Elm-to-C compiler, Pebble backend, manifests, and runtime generator
- `elm_ex/` - Elm parser/tokenizer bridge used by editor/compiler features
- `elmx/` - compiled Elixir debugger/runtime execution path
- `packages/elm-pebble/elm-watch/` - watch-side Elm package
- `packages/elm-pebble-companion-core/` - companion bridge contracts/codecs
- `shared/` - generated/shared protocol modules and bridge schemas
- `elm_pebble_dev/` - public docs/site app and package documentation mirror

Generated build outputs should stay out of git. See
`docs/REPO_CLEANUP_AND_SCOPE.md` for repository hygiene rules.

## Current Architecture

The IDE has three major loops:

- **Editor loop:** CodeMirror sends document identity and text changes to an
  IDE LSP facade over Phoenix channels. The server reuses tokenizer/parser,
  formatter, package docs, and project dependency data to answer language
  requests.
- **Build loop:** IDE project files feed `elmc` check/compile/manifest and the
  Pebble toolchain. Publish builds copy `ide/priv/pebble_app_template/` into an
  isolated per-project build directory.
- **Debugger loop:** debugger state is event-sourced around reload, update,
  protocol, view render, replay, tick, snapshot, and runtime execution events.
  MCP exposes the same state and control surface for agent-driven workflows.

The debugger uses contracts for structure (messages, cmds, subscriptions) and
compiled `elmx` execution for `init`, `update`, and watch preview. Parser-only
model/view mutation and preview fallbacks are removed; missing runtime artifacts
or eval failures surface as timeline errors or `previewUnavailable`. See
`ide/docs/debugger.md`.

## Package Model

Required packages are treated as platform/runtime dependencies and cannot be
removed from project `elm.json` files:

- `elm-pebble/elm-watch`
- `elm-pebble/companion-core`
- `elm/core`
- `elm/json`
- `elm/time`

Catalog search is filtered for Pebble watch compatibility, and dependency rows
surface supported/blocked status. The current companion package shape is
`elm-pebble/companion-core`.

## Roadmap

### 1. Publish Readiness

- Keep local paths, generated artifacts, and machine-specific files out of git.
- Confirm Docker/local startup paths after the template move into `ide/priv/`.
- Re-run a clean project create -> edit -> package -> install flow before public
  release.
- Make release checks explicit about required metadata, screenshots, package
  artifacts, and target platforms.

### 2. Debugger Runtime Fidelity

- **Shipped baseline:** `:compiled_elixir` (`elmx`) is the default debugger backend.
- **Zero-gap compile policy:** `ELMX_TEMPLATE_COMPILE_GATE=1` requires every shipped template
  watch + phone root to elmx-compile with no smoke exceptions; see
  `docs/ELMX_DEBUGGER_FIDELITY_MATRIX.md`.
- Harden remaining `elmx` gaps as new templates surface (cross-module partial application,
  rare stdlib corners) — driven by compile gate failures, not one-off app hacks.
- Keep snapshot continuation, replay, tick, protocol, and subscription follow-up rows
  deterministic (`subscription_command`, device, HTTP, companion bridge).
- Preserve trace export/import and MCP cursor inspection as stable contracts.
- **Release gate:** `scripts/debugger_release_gate.sh` plus
  `.github/workflows/debugger-strict.yml` on every PR.

### 3. Editor and Language Server

- Keep LSP-backed editor features as the default path for formatting,
  diagnostics, completion, hover, links, and folding.
- Reduce remaining LiveView-only language feature fallbacks where the LSP path
  is mature.
- Keep formatting cursor/scroll behavior stable.
- Continue tightening parser/tokenizer diagnostics where compiler feedback is
  not yet precise enough for live editing.

### 4. Formatter

- Use `elm-format` as the default user formatter.
- Keep the built-in formatter clearly labeled experimental until parity is
  strong enough to revisit that status.
- Maintain formatter regression tests for specific editor bugs, but avoid
  expanding a bespoke formatter roadmap unless it becomes a release goal again.

### 5. Package Compatibility

- Keep required runtime packages undeletable in both backend and UI paths.
- Expand compatibility diagnostics from package-family blocking toward
  dependency-graph explanations.
- Keep package docs and editor docs aligned with `elm-pebble/elm-watch`,
  `elm-pebble/companion-core`, `elm/core`, `elm/json`, and `elm/time`.

### 6. MCP and Agent Workflows

- Keep MCP tool docs in sync with the actual tool catalog.
- Harden capability boundaries for read/edit/build/debug/publish operations.
- Preserve audit redaction for file writes and mutating actions.
- Keep trace exports deterministic enough for bug reports and agent handoff.

### 7. Companion Bridge

- Keep `shared/companion-protocol/phone_bridge_v1.json`,
  `elmc/scripts/generate_phone_bridge.py`, and
  `packages/elm-pebble-companion-core/` aligned.
- Maintain docs in `docs/PEBBLE_PHONE_PROTOCOL.md` and
  `docs/PEBBLE_PHONE_API_MATRIX.md`.
- Keep the companion package topology explicit if it changes again.

## Release Gates

Before publishing a cleaned public repository:

- Run the focused IDE/package/debugger tests touched by recent work.
- Run `.github/workflows/debugger-strict.yml` suites (executor + IDE debugger + template corpus).
- Run `mix test` in `ide/` if time permits and document any known unrelated
  failures.
- Run `mix test` in `elmx/` for runtime executor changes.
- Verify `./start-ide-local.sh` starts the IDE and serves `/projects`.
- Search for local absolute paths and generated artifacts.
- Confirm docs do not refer to removed directories or old package identities.
