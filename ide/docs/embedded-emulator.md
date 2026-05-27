# Embedded Pebble emulator

The **embedded emulator** runs Pebble QEMU on the IDE host and exposes it to the browser for display, install, and simulator controls. It is distinct from the **WASM emulator** (`/wasm-emulator`), which runs firmware in the browser without QEMU.

Use this document when operating the emulator from the UI, calling HTTP APIs, writing automation, or debugging display/handshake issues.

## Architecture

```mermaid
flowchart LR
  subgraph browser [Browser]
    UI[EmbeddedEmulatorHost]
    noVNC[noVNC RFB client]
    PhoneWS[Phone WebSocket]
    Phoenix[Phoenix /socket]
  end

  subgraph ide [IDE host]
    API[EmulatorController HTTP]
    VncCh[EmulatorVncChannel]
    VncProxy[EmulatorProxySocket]
  end

  subgraph session [Emulator.Session]
    QEMU[QEMU Pebble]
    Router[Pebble protocol router]
    Pypkjs[pypkjs phone bridge]
  end

  UI --> API
  UI --> Phoenix
  Phoenix --> VncCh
  VncCh -->|TCP VNC| QEMU
  UI --> noVNC
  noVNC -->|frame events b64| VncCh
  UI --> PhoneWS
  PhoneWS --> VncProxy
  VncProxy --> Pypkjs
  API --> session
  UI -->|control JSON| API
  API --> Router
  Router --> QEMU
```

| Component | Role |
|-----------|------|
| `Ide.Emulator.Session` | One GenServer per session: QEMU, VNC port, phone WS port, PBW artifact, flash image |
| `IdeWeb.EmulatorController` | Launch, ping, install, control, kill; serves PBW artifact |
| `IdeWeb.EmulatorVncChannel` | Relays RFB bytes between browser and QEMU over Phoenix channel `emulator_vnc:<session_id>` |
| `IdeWeb.EmulatorProxySocket` | Raw WebSocket proxy to local TCP (used for `/ws/phone` and legacy `/ws/vnc`) |
| `embedded_emulator.js` | Thin browser orchestrator (toolbar, state, feedback) |
| `emulator_http.js` | Shared `postJSON`, CSRF, WebSocket URL helpers |
| `emulator_session_client.js` | Launch, stop, ping, install HTTP session API |
| `emulator_vnc.js` | Phoenix VNC channel + noVNC display |
| `emulator_simulator_delivery.js` | Simulator settings → QEMU batch API, phone bridge, weather |
| `qemu_control.js` | QEMU protocol encoders (shared with WASM emulator) |
| `install_prep.ex` | Install pacing, reuse settle, reset-needed checks |

### Elixir types (server)

| Module | Role |
|--------|------|
| `Ide.WatchModels` / `Ide.WatchModels.Profile` | Canonical watch catalog (`profile_for/1`, `profile_screen/1`); string-key maps at runtime |
| `Ide.Emulator.Types` | Session API contracts: `session_info`, `runtime_status`, `simulator_settings`, `pbw_install_result`, errors |
| `Ide.Emulator.QemuControl` | QEMU `command/0` and `external_cli_command/0` encoders |
| `Ide.Debugger.Types.SimulatorSettings` | Normalized simulator settings (shared with debugger; used by `apply_simulator_settings`) |

## Prerequisites

On the machine running the IDE:

1. **Pebble SDK / QEMU** — same dependencies as the IDE emulator health check (Settings → emulator setup, or server logs at boot via `Ide.Emulator.StartupCheck`).
2. **Environment** (see `config/config.exs`, `Ide.Emulator.Session`):
   - `ELM_PEBBLE_EMBEDDED_EMULATOR` — default `true`; set `false` to disable backend QEMU.
   - `ELM_PEBBLE_QEMU_BIN`, `ELM_PEBBLE_QEMU_IMAGE_ROOT`, `ELM_PEBBLE_PYPKJS_BIN` — optional overrides.
3. **Auth** — embedded APIs require a logged-in IDE user (session cookie). POST requests need the CSRF meta tag (`x-csrf-token`).

Run the IDE:

```bash
cd ide
mix setup
mix phx.server
```

Open a project emulator page: `http://localhost:4000/projects/<slug>/emulator`.

After frontend changes: `mix assets.build` and hard-refresh the page. The event log includes a **UI build** string (e.g. `v22-refactor`) to confirm the loaded client bundle.

## Browser workflow

1. **Launch** — builds/uses a PBW for the project and platform, starts `Emulator.Session`, waits until `display_ready` (QEMU up + VNC banner captured).
2. **Display** — connects noVNC through Phoenix channel `emulator_vnc:<id>` (production path). Raw `/api/emulator/:id/ws/vnc` is for tools, tests, and local proxy only — do not point the embedded browser host at it without re-validation (see **VNC policy** below).
3. **Install** — pushes the PBW to the running watch via native installer (`POST .../install`) or phone-bridge fallback when pypkjs is available.
4. **Controls** — buttons and simulator sliders send QEMU control packets via `POST .../control`.
5. **Phone bridge** — optional WebSocket to `/api/emulator/:id/ws/phone` for AppLog, storage debug, companion-style messages.
6. **Stop** — `POST .../kill` or leaving the page; sessions also idle-timeout (default 5 minutes).

The in-page **event log** and **Copy feedback report** capture session state, VNC diagnostics, and timestamps for bug reports.

## Session lifecycle

### 1. Launch

**HTTP:** `POST /api/emulator/launch`

```json
{
  "slug": "digital",
  "platform": "diorite"
}
```

**Response** (public session map, abbreviated):

| Field | Meaning |
|-------|---------|
| `id` | Session id (use in all subsequent URLs) |
| `platform` | Watch model id (`diorite`, `basalt`, …) |
| `screen` | `{width, height}` from watch profile |
| `artifact_path` | `GET` PBW built for this session |
| `install_path`, `ping_path`, `kill_path` | POST endpoints |
| `vnc_path` | Legacy raw VNC WebSocket path (see Display) |
| `phone_path` | Phone-bridge WebSocket path |
| `controls` | Supported control names |
| `display_ready` | `true` when VNC is accepting connections |
| `phone_bridge_ready` | `true` when pypkjs phone port is up |
| `backend_enabled` | `false` if embedded emulator disabled in config |

**Elixir:**

```elixir
{:ok, info} =
  Ide.Emulator.launch(
    project_slug: "users/1/digital",
    platform: "diorite",
    artifact_path: "/path/to/app.pbw",  # optional; launch usually sets this
    has_phone_companion: false,
    has_companion_preferences: false
  )
```

Launch acquires a slot (`Ide.Emulator.SlotLimiter`, default max 8 concurrent sessions).

### 2. Keep-alive / status

**HTTP:** `POST /api/emulator/:id/ping`

Returns the same public map as launch, plus `alive: true`, refreshed `display_ready`, `installing`, etc. The browser pings after display connect.

### 3. Display (VNC / noVNC)

Current client path (v21+):

1. Open shared Phoenix socket: `GET /socket` (WebSocket or long-poll fallback).
2. Join channel topic: `emulator_vnc:<session_id>`.
3. Join reply includes `initial`: base64-encoded RFB data (server banner, typically 12 bytes `RFB 003.008\n`).
4. Client holds `initial` until noVNC attaches, then feeds it into the receive queue and starts the handshake.
5. noVNC sends client frames with channel event `frame` and payload `{b64: "<base64>"}`.
6. Server relays to QEMU; server pushes `{b64: "..."}` `frame` events for outbound bytes.

**Legacy / alternate:** `GET /api/emulator/:id/ws/vnc` upgrades to `EmulatorProxySocket` → QEMU VNC TCP. This still works for host-local tools and tests; the browser uses the channel path because raw `/ws/vnc` upgrades were unreliable in some environments.

**Readiness:** wait for `display_ready: true` on ping/launch before expecting a picture.

### 4. Install PBW

**HTTP:** `POST /api/emulator/:id/install`

Installs the session’s `artifact_path` PBW through the Pebble protocol router into QEMU (same path as the IDE “Install” button). Response:

```json
{ "status": "ok", "result": { ... } }
```

The browser may fall back to **phone-bridge install** if the native install path fails and `phone_path` is connected.

**Artifact:** `GET /api/emulator/:id/artifact` — raw PBW bytes.

### 5. QEMU controls

**HTTP:** `POST /api/emulator/:id/control`

```json
{
  "protocol": 8,
  "payload": [0, 4]
}
```

`protocol` is `0..255`. `payload` is a JSON array of byte values `0..255`; the server validates via `Ide.Emulator.QemuControl` and forwards through `Ide.Emulator.PebbleProtocol.Router`.

**Canonical mapping** (shared by `assets/js/emulator/qemu_control.js` and `lib/ide/emulator/qemu_control.ex`):

| UI / API name | `protocol` | `payload` (typical) |
|---------------|------------|---------------------|
| Buttons (bitmask) | `8` | `[buttonState]` — bits: back=1, up=2, select=4, down=8 |
| Tap | `2` | `[0, 1]` press, `[0, 0]` release |
| Battery | `5` | `[percent, charging_flag]` |
| Bluetooth | `3` | `[connected]` — `0` or `1` |
| 24h time format | `9` | `[enabled]` — `0` or `1` |
| Timeline peek | `10` | `[enabled]` — `0` or `1` |
| Accelerometer | `11` | 6 bytes: int16 x, y, z big-endian |
| Compass | `12` | 3 bytes: heading high/low, valid flag |

**Simulator settings → QEMU:** changing the emulator page “Simulator settings” form pushes `simulator_settings_applied` to the browser, which calls `applySimulatorSettingsToQemu/2`. Settings are re-applied automatically after **Launch** and when resuming a persisted session (so defaults reach QEMU even if the form was loaded before QEMU started).

**Simulated date/time** (`use_simulated_time`, `simulated_date`, `simulated_time`) is **debugger-only** on the emulator settings form (hidden in `:emulator` mode). It affects Elm debugger stepping via `Ide.Debugger.DeviceData`, not embedded QEMU watch-face time. There is no QEMU control protocol for set-time in embedded sessions; external SDK emulators receive `emu-set-time` via `QemuControl.external_cli_commands/1`.

**Batch apply:** `POST /api/emulator/:id/simulator-settings` with `{"settings": {...}}` applies all mapped QEMU controls in one request (`Ide.Emulator.apply_simulator_settings/2`). The browser delivery module uses this after launch/resume, with per-control `/control` fallback.

**External SDK emulator:** battery, Bluetooth, time format, timeline peek, compass, and simulated time (when enabled) map to `pebble emu-*` via `QemuControl.external_cli_commands/1`.

### Simulator delivery matrix

| Setting | Embedded QEMU | Phone bridge | Debugger runtime | External `pebble emu-*` |
|---------|---------------|--------------|------------------|-------------------------|
| Battery / charging | protocol 5 | settings JSON | DeviceData | `emu-battery` |
| Bluetooth | protocol 3 | settings JSON | DeviceData | `emu-bt-connection` |
| 24h format | protocol 9 | — | — | `emu-time-format` |
| Timeline peek | protocol 10 | — | — | `emu-set-timeline-quick-view` |
| Compass | protocol 12 | — | — | `emu-compass` |
| Simulated date/time | — | — | DeviceData | `emu-set-time` (when enabled) |
| Weather / companion | — | inject + JSON | subscriptions | — |

**Elixir:**

```elixir
:ok = Ide.Emulator.control(session_id, 8, <<0>>)  # release all buttons

commands = Ide.Emulator.QemuControl.commands_from_simulator_settings(settings)
```

### 6. Phone bridge WebSocket

**URL:** `ws://<host>/api/emulator/:id/ws/phone` (or `wss://`)

Requires auth cookies like other emulator routes. Used for:

- Pebble protocol frames (`0x01` + endpoint + payload) — AppLog, PutBytes, etc.
- JSON simulator settings (`0x0e` prefix)
- PBW install handoff to companion cache (`0x04` messages) when JS companion is in use

**Host-local test** (no browser):

```bash
cd ide
mix run scripts/test_emulator_phone_ws.exs
```

**Direct TCP** (from the same machine as the IDE):

```elixir
{:ok, pid} = Ide.Emulator.lookup(session_id)
port = Ide.Emulator.Session.local_port(pid, :phone)  # or :vnc
```

### 7. Kill session

**HTTP:** `POST /api/emulator/:id/kill`

Stops the session GenServer, releases the slot, and tears down QEMU/pypkjs.

**Elixir:** `Ide.Emulator.kill(session_id)`

## HTTP API summary

All routes under `/api` require authentication unless noted.

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/emulator/launch` | Start session (`slug`, `platform`) |
| `POST` | `/api/emulator/:id/ping` | Session status + `alive` |
| `POST` | `/api/emulator/:id/install` | Install PBW into QEMU |
| `POST` | `/api/emulator/:id/control` | QEMU control packet |
| `POST` | `/api/emulator/:id/simulator-settings` | Batch apply normalized simulator settings to QEMU |
| `POST` | `/api/emulator/:id/kill` | End session |
| `GET` | `/api/emulator/:id/artifact` | Download session PBW |
| `GET` | `/api/emulator/:id/ws/vnc` | Raw VNC WebSocket (proxy) |
| `GET` | `/api/emulator/:id/ws/phone` | Phone bridge WebSocket |
| `GET` | `/api/emulator/config-return` | Companion config popup return HTML |

Phoenix channel (browser):

| Topic | Events | Purpose |
|-------|--------|---------|
| `emulator_vnc:<session_id>` | join → `initial` (base64) | RFB banner |
| | `frame` / `{b64}` in & out | Full VNC byte stream |

Shared socket: `/socket` with CSRF param `_csrf_token` on connect (see `user_socket.js`).

## Programmatic examples

### curl (from a logged-in browser session)

Export cookies and CSRF from DevTools, then:

```bash
CSRF=...  # from meta[name=csrf-token]
COOKIE=...  # session cookie

curl -s -X POST http://localhost:4000/api/emulator/launch \
  -H "content-type: application/json" \
  -H "x-csrf-token: $CSRF" \
  -b "$COOKIE" \
  -d '{"slug":"digital","platform":"diorite"}' | jq .
```

### IEx (on IDE node)

```elixir
# Check dependencies
Ide.Emulator.runtime_status("diorite")

# Full session in test/dev with processes
Application.put_env(:ide, Ide.Emulator.Session, start_processes: true)

{:ok, info} =
  Ide.Emulator.launch(
    project_slug: "manual-test",
    platform: "diorite",
    artifact_path: nil,
    has_phone_companion: false,
    has_companion_preferences: false
  )

:ok = Ide.Emulator.control(info.id, 8, <<0>>)
{:ok, _} = Ide.Emulator.install(info.id)
Ide.Emulator.kill(info.id)
```

Integration tests use `Ide.TestSupport.EmulatorSessionEnv.run_live/1` and `EmulatorLaunch.launch/1` (see `test/ide_web/emulator_vnc_channel_handshake_test.exs`).

## Configuration and limits

| Setting | Location | Default |
|---------|----------|---------|
| Embedded emulator on/off | `ELM_PEBBLE_EMBEDDED_EMULATOR` | enabled |
| Idle timeout | `Ide.Emulator.Session` `:idle_timeout_ms` | 5 min |
| Max concurrent sessions | `Ide.Emulator.SlotLimiter` `:max_slots` | 8 |
| QEMU images | `ELM_PEBBLE_QEMU_IMAGE_ROOT` | `~/.pebble-sdk/.../pebble` |

Tests often set `start_processes: false` on `Ide.Emulator.Session` to avoid spawning QEMU during `mix test`.

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| Launch 422 / unavailable | `Ide.Emulator.runtime_status/1` missing components; Settings emulator check |
| Display timeout, 12 bytes only | Event log: join `initial`, “pushing N bytes”, `framesReceived` on feedback report; UI build string; server restarted after channel changes |
| `display_ready: false` | QEMU still booting; VNC banner not captured — wait and ping again |
| Install fails | `POST /install` error body; console logs in session; try phone bridge if companion app |
| Install progress stuck ~5% on watch | Early PutBytes/binary phase — Bluetooth may not be ready yet; wait a few seconds after launch (emery/flint) then install, or stop and relaunch; check server logs for `putbytes_failed` / timeout |
| Launch takes many seconds | Normal while QEMU boots to “Ready for communication” and VNC comes up (typically under ~10s); a duplicate console wait was removed in recent builds |
| Phone bridge not ready | `phone_bridge_ready: false` — pypkjs missing or not started; non-fatal for display-only apps |
| Stale session after refresh | Browser re-pings `ping_path`; may call `kill` and launch again |

**Feedback report** (in emulator UI): includes UI build, session ping JSON, `simulatorSettingsSource`, `simulatorSettingsAppliedAt`, `lastQemuSettingsApply`, VNC byte/frame counts, and ordered event log — paste when filing bugs.

## VNC policy

- **Browser (embedded emulator):** Phoenix channel `emulator_vnc:<session_id>` only (`EmulatorVncChannel` + `emulator_vnc.js`).
- **`GET /api/emulator/:id/ws/vnc`:** raw TCP↔WebSocket proxy for automation, `emulator_vnc_http_ws_test.exs`, and local tools — not the production browser path.
- Re-enabling direct browser VNC requires re-validating auth, buffering, and RFB handshake behavior end-to-end.

## Related code

| Path | Description |
|------|-------------|
| `assets/js/emulator/embedded_emulator.js` | Browser orchestrator |
| `assets/js/emulator/emulator_http.js` | HTTP + CSRF helpers |
| `assets/js/emulator/emulator_session_client.js` | Session launch/stop/ping/install |
| `assets/js/emulator/emulator_vnc.js` | VNC channel + noVNC |
| `assets/js/emulator/emulator_simulator_delivery.js` | Simulator settings delivery |
| `assets/js/user_socket.js` | Phoenix `/socket` client |
| `lib/ide_web/channels/emulator_vnc_channel.ex` | VNC channel relay |
| `lib/ide/emulator/install_prep.ex` | Install pacing and reuse settle |
| `lib/ide_web/controllers/emulator_controller.ex` | HTTP API |
| `lib/ide/emulator/session.ex` | Session GenServer |
| `lib/ide/emulator/qemu_control.ex` | QEMU protocol IDs, encoders, simulator-settings mapping |
| `assets/js/emulator/qemu_control.js` | Browser-side QEMU encoders (embedded + WASM) |
| `lib/ide_web/emulator_proxy_socket.ex` | TCP ↔ WebSocket proxy |
| `test/ide_web/emulator_vnc_channel_handshake_test.exs` | Channel + VNC handshake tests |
