# Pebble Phone Validation Checklist

Use this checklist for final companion validation after bridge and contract changes.

## Automated checks

- `elmc` bridge generator tests pass:
  - `mix test test/phone_bridge_generator_test.exs test/phone_bridge_contract_test.exs`
- `ide` project/template tests pass:
  - `mix test test/ide/projects_test.exs`

## Emulator checks

- Build and install a sample app with companion JS:
  - `pebble build`
  - `pebble install --emulator basalt --logs`
- Verify watch -> companion -> watch roundtrip logs for at least 3 messages.
- Verify failed/unsupported operation returns structured `unsupported_operation` error envelope.

## Real phone checks

- Ensure phone app is logged in and has a paired watch.
- Install with phone transport:
  - `pebble install --phone --logs`
- Validate:
  - lifecycle events (`ready`, visibility, config close)
  - one successful HTTP request
  - one failing HTTP request (timeout or network)
  - storage set/get/remove
  - websocket connect/message/close

## Wrong-target checks

- Confirm watch-only API names are not present in `shared/companion-protocol/phone_bridge_v1.json`.
- Confirm unsupported watch-only operations return structured bridge errors instead of silent failures.
