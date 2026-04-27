# Pebble Phone Bridge Protocol (v1)

This document defines the versioned envelope contract used by generated Elm/JS bridge code for phone companion apps compiled with the original Elm compiler.

## Envelope Types

- `command`: Elm -> JS request.
- `result`: JS -> Elm response for a prior command.
- `event`: JS -> Elm pushed notification.
- `error`: structured error object embedded in failed `result` payloads.

## Canonical Shapes

### `command`

```json
{
  "id": "req_123",
  "api": "http",
  "op": "send",
  "payload": { "method": "GET", "url": "https://example.com" }
}
```

### `result`

```json
{
  "id": "req_123",
  "ok": false,
  "error": {
    "type": "timeout",
    "message": "Request timed out",
    "retryable": true
  }
}
```

### `event`

```json
{
  "event": "lifecycle.ready",
  "payload": {}
}
```

## Delivery Rules

- `id` must be unique per in-flight command.
- `result.id` must match the originating `command.id`.
- `ok = true` implies `payload` is present and `error` is absent.
- `ok = false` implies `error` is present.
- Unknown events must be ignored by default.

## API Namespaces

The v1 schema includes:

- `http`
- `appMessage`
- `storage`
- `lifecycle`
- `configuration`
- `timeline`
- `geolocation`
- `network`
- `webSocket`

Schema source:

- `shared/companion-protocol/phone_bridge_v1.json`
