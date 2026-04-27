# Elmc Pebble Template App

This project is the reusable Pebble app template used by IDE publish builds.
It runs generated `elmc` C output inside a Pebble app loop.

## Regenerate Compiler Output

```bash
./ide/priv/pebble_app_template/scripts/generate_elmc.sh
```

This writes generated runtime/ports/worker/pebble shim files to:

- `src/c/elmc/runtime`
- `src/c/elmc/ports`
- `src/c/elmc/c`
- `src/c/generated/companion_protocol.h` and `src/c/generated/companion_protocol.c` (from `shared/elm/CompanionProtocol/Internal.elm`)

## Build and Install

```bash
pebble build
pebble install --emulator basalt
```

## Expected Behavior

- App renders a retained virtual UI tree from Elm `view : Model -> Pebble.Ui.UiNode`.
- The generated shim extracts the top `Window -> CanvasLayer` and only replays draw ops when the virtual layer hash or IDs change.
- Expected commands include clear background, horizontal line, and centered `View: <n>` text.
- App requests weather via companion and shows `Temp: <n>C` when a response arrives.
- Up/Select buttons dispatch via generated button adapter.
- Down button dispatches decrement via generated button adapter.
- Accelerometer tap dispatches via generated accel adapter.
- This confirms generated `elmc` code is wired into a live Pebble app event loop.

## Elm Companion PoC (Typed Protocol)

- A sample Elm companion worker lives in `src/elm/CompanionApp.elm`.
- Shared request/response types are defined in `shared/elm/CompanionProtocol/Types.elm`.
- The PKJS bridge in `src/pkjs/index.js` forwards AppMessage payloads to Elm via ports and sends typed responses back.
- Watch C sends `request_tag/request_value` and receives `response_tag/response_value`; the returned value is drawn as `Phone: <n>`.
