# elm-pebble/companion-core

Developer-facing Pebble companion platform APIs for phone apps compiled with the original Elm compiler.

Import `Pebble.Companion.*` modules for weather, storage, connectivity, and other phone-side capabilities. Watch↔phone protocol modules remain under project-local `Companion.*` namespaces.

`Pebble.Companion.Weather` uses `current`, `forecast`, and `onWeather` only — the companion bridge registers handlers when those commands run. On a phone, weather is fetched over HTTP (Open-Meteo) from geolocation; in the IDE debugger, simulator settings supply values.

Regenerate the website package viewer mirror after API changes:

```bash
./ide/scripts/sync_bundled_elm.sh
cd ide && mix ide.package_docs
```

See:

- `shared/companion-protocol/phone_bridge_v1.json`
- `docs/PEBBLE_PHONE_PROTOCOL.md`
- `docs/PEBBLE_PHONE_API_MATRIX.md`
