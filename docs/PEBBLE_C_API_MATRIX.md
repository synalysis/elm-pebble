# Pebble C API to Elm Matrix (App-Focused Wave)

This matrix tracks the app-focused subset for Foundation, Graphics, and User Interface APIs and how each area maps to the split Elm packages.

## Foundation

| C area | Elm module(s) | Status | Interop |
| --- | --- | --- | --- |
| App / Launch reason | `Pebble.Platform` | implemented | typed enum via `LaunchReason` |
| AppMessage (phone bridge) | `Companion.Watch` | implemented (typed protocol) | command encoding + dispatch tag/value hidden behind protocol helpers |
| Event Service (tick) | `Pebble.Events` | implemented | subscription bitmask |
| Button input | `Pebble.Button` | implemented | subscription bitmask + typed button/event selectors |
| Accelerometer | `Pebble.Accel` | implemented | subscription bitmask + typed sample dispatch |
| Frame loop | `Pebble.Frame` | implemented | subscription bitmask + typed frame dispatch |
| Event Service (battery/connection) | `Pebble.System` | implemented | subscription bitmask |
| Storage (watch int/string) | `Pebble.Storage` | implemented | command encoding |
| Timer | `Pebble.Cmd` | implemented | command encoding |
| Wakeup | `Pebble.Wakeup` | implemented | command encoding |
| Wall Time | `Pebble.Time` | implemented | command encoding + typed callbacks |
| WatchInfo | `Pebble.WatchInfo` | implemented | enum tags + typed record |
| Logging | `Pebble.Log` | implemented (integer payload) | command encoding |

## Graphics

| C area | Elm module(s) | Status | Interop |
| --- | --- | --- | --- |
| Drawing primitives, text, paths | `Pebble.Ui` | implemented | draw op encoding |
| Bitmap/font resources + bitmap/font draw APIs | `Pebble.Ui`, generated `Pebble.Ui.Resources` | implemented | resource upload -> generated ADT constructors (`Bitmap`, `Font`) -> draw op/resource-id encoding |
| Graphics context state | `Pebble.Ui` | implemented | tagged context settings |
| Window + canvas virtual scene | `Pebble.Ui` | implemented | virtual tree extraction in shim |
| Grouped Graphics facade | `Pebble.Graphics` | removed | redundant facade removed; use `Pebble.Ui` directly |

## User Interface

| C area | Elm module(s) | Status | Interop |
| --- | --- | --- | --- |
| Clicks / button events | `Pebble.Events` | implemented | subscription bitmask |
| Vibes | `Pebble.Vibes` | implemented | command encoding |
| Light / backlight | `Pebble.Light` | implemented | command encoding |
| Window/Layer retained model | `Pebble.Ui` | implemented | virtual top window/layer |

## Typed Interchange Policy

- Enums map to typed Elm constructors via C-side tag mapping.
- Struct-like payloads map to Elm records via C-side record construction.
- Primitive payloads use integers/booleans/strings only where they are the canonical C values.
