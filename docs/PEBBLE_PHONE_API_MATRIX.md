# Pebble Phone API Matrix (Companion-Only)

This matrix defines the phone-side API surface for the companion architecture.
It is intentionally limited to APIs available in the Pebble companion (PebbleKit JS / phone runtime), and excludes watch-only C APIs.

## Scope Guardrails

- Include only companion/phone capabilities.
- Exclude watch-only APIs (`WatchInfo`, `Vibes`, `Light`, `Wakeup`, watch `Events`, watch `Ui/Graphics`, etc.).
- Prefer Elm-native API design over thin JS-shaped wrappers.
- For categories that overlap with core Elm ecosystem packages (especially HTTP), keep API shape close to familiar Elm patterns.

## Phone Capability Matrix

| Capability area | Runtime source | Elm module | Status | Elm-like shape target |
| --- | --- | --- | --- | --- |
| AppMessage send/receive | Pebble companion bridge | `Companion.Phone` / `Companion.Watch` | implemented (typed protocol) | Typed protocol helpers with decoders/encoders instead of raw integer pairs |
| Companion lifecycle events (`ready`, visibility, unload) | Pebble event listeners | `Pebble.Companion.Lifecycle` | implemented (contract layer) | `Sub msg` event subscriptions with typed event ADTs |
| Configuration flow (`showConfiguration`, `webviewclosed`) | Pebble config hooks | `Pebble.Companion.Configuration` | implemented (contract layer) | `open : Url -> Cmd msg`, `onClosed : (Result ConfigError ConfigPayload -> msg) -> Sub msg` |
| Timeline token and timeline operations | Pebble timeline APIs | `Pebble.Companion.Timeline` | implemented (contract layer) | `Task`/`Cmd` returning typed token/result records |
| Open external URL | Pebble open URL API | `Pebble.Navigation` or `Pebble.Browser` | missing | Simple `openUrl : String -> Cmd msg` with explicit error callback variant |
| HTTP client | Original Elm compiler / debugger substitution | `elm/http` | implemented for companion apps | Use normal `elm/http`; the debugger/runtime bridge substitutes companion execution details |
| WebSocket client | `WebSocket` | `Pebble.Companion.WebSocket` | implemented (contract layer) | Explicit connection state + `Cmd`/`Sub` split, typed close/error reasons |
| Local companion storage | localStorage/companion persistence | `Pebble.Companion.Storage` | implemented (contract layer) | Key/value API with typed codecs; avoid ad-hoc tagged unions in user land |
| Geolocation (if enabled in companion runtime) | browser geolocation | `Pebble.Companion.Geolocation` | implemented (contract layer) | `getCurrentPosition` + `watchPosition` with typed coordinates/errors |
| Connectivity status (network reachability) | browser navigator/connectivity events | `Pebble.Companion.Network` | implemented (contract layer) | `onStatusChange` subscription + query command |
| JS logs/diagnostics | companion console and structured errors | Bridge `error` envelope (`Pebble.Companion.Contract`) | implemented (envelope) | Typed log levels and structured error values for app callbacks |

## Explicitly Out of Scope (Watch-Only)

These remain in `elm-pebble/elm-watch` and must not be added to phone package modules:

- Device/watch hardware info and firmware (`Pebble.WatchInfo`, `Pebble.Platform` watch details)
- Watch event services (tick, button, accelerometer, battery, bluetooth)
- Watch persistence command queue (`Pebble.Storage` int key watch commands)
- Watch timers/wakeup/light/vibration
- Watch UI and drawing (`Pebble.Ui`)

## Elm API Design Rules

### 1) Match Elm conventions first

- Use `Cmd msg` / `Sub msg` for runtime effects.
- Use `Result Error a` with explicit error ADTs, not plain strings.
- Prefer typed records and custom types over open dictionaries and untyped JSON.

### 2) HTTP should feel like `elm/http`

Target shape:

- `type alias Request a`
- `type Header`
- `type Body`
- `type Expect msg`
- `type Error`
- builders like `get`, `post`, `request`, `header`, `jsonBody`, `stringBody`
- `send : (Result Error a -> msg) -> Request a -> Cmd msg`

Guidance:

- Keep names and ergonomics familiar to `elm/http`.
- Preserve room for companion-specific options via additive builders (timeouts, retry hints), not incompatible core function signatures.

### 3) Decoder/encoder boundaries

- AppMessage and storage values should cross module boundaries through codecs, so app code remains strongly typed.
- Keep raw transport payload representation internal where possible.

### 4) Stable async model

- Commands initiate actions.
- Subscriptions deliver pushed events (incoming messages, socket events, lifecycle notifications).
- Avoid mixing pull and push into one ambiguous command type.

## Suggested Implementation Waves

| Wave | Focus | Deliverables |
| --- | --- | --- |
| 1 | Runtime foundation | Generic companion dispatcher, request correlation IDs, error envelope, target diagnostics |
| 2 | Core APIs | Elm-like HTTP, typed companion protocol, storage, lifecycle subscriptions |
| 3 | Realtime + platform extras | `Pebble.WebSocket`, configuration flow, timeline token, open URL, network/geolocation |
| 4 | Quality and parity | Full docs, fixtures, integration tests, wrong-target tests, migration notes |

## Acceptance Criteria for "Phone API Complete"

- Every matrix row is marked implemented or explicitly deferred with rationale.
- No watch-only APIs are exposed from `elm-pebble/companion-core`.
- Companion HTTP uses normal `elm/http` from app code.
- Companion runtime has deterministic behavior under success/failure/timeouts.
- End-to-end watch <-> phone tests pass for request/response and push event flows.
