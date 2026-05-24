# MCP Weather Watchface Showcase

This walkthrough creates an animated weather watchface project, imports vector
graphics through the IDE, and verifies the companion weather flow end to end.

## Prerequisites

- IDE running locally with MCP enabled (`mix ide.mcp --capabilities read,edit,build`)
- MCP client configured (see `docs/IDE_MCP.md`)
- Optional: SVG artwork for weather icons and transition sequences

## 1. Create the project

Use `projects.create` with the weather animated template:

```json
{
  "name": "Weather Animated",
  "slug": "weather-animated",
  "target_type": "watchface",
  "template": "watchface-weather-animated"
}
```

The template seeds:

- `watch/src/Main.elm` — clock plus weather icon rendering
- `phone/src/CompanionApp.elm` — Open-Meteo fetch on `RequestWeather`
- `protocol/src/Companion/Types.elm` — typed weather messages
- `watch/resources/vectors.json` — placeholder vector manifest entries

Inspect the workspace with `projects.tree` and confirm these roots exist.

## 2. Import static weather icons

Each weather condition maps to a static vector constructor in `watch/src/Main.elm`:

| Condition | Constructor |
|-----------|-------------|
| Clear | `WeatherClear` |
| Cloudy | `WeatherCloudy` |
| Fog | `WeatherFog` |
| Drizzle | `WeatherDrizzle` |
| Rain | `WeatherRain` |
| Snow | `WeatherSnow` |
| Showers | `WeatherShowers` |
| Storm | `WeatherStorm` |
| Unknown | `WeatherUnknown` |

In the IDE **Resources** page for the project:

1. Open the **Vectors** tab.
2. Upload one SVG or PDC per static icon.
3. Name files to match the constructor (for example `WeatherClear.svg`).

The IDE converts SVG uploads to PDC, updates `watch/resources/vectors.json`, and
regenerates `watch/src/Pebble/Ui/Resources.elm`.

Repeat until all nine static constructors have non-zero byte entries in the
manifest.

## 3. Import transition sequences

When `ProvideCondition` changes, the watchface plays a transition sequence via
`Ui.drawVectorSequenceAt`. Constructor names follow
`Transition<From>To<To>` — for example `TransitionClearToCloudy`.

Import transition assets the same way:

1. Upload PDC sequence files (or SVG sources the IDE converts).
2. Match filenames to constructor names listed in `vectors.json`.
3. Confirm the Resources page shows updated byte counts.

The watch app resolves transitions with explicit case mapping in
`conditionVector` and `transitionVector` inside `watch/src/Main.elm`.

## 4. Compile and package

Run MCP build tools:

1. `compiler.check` with the project slug.
2. `compiler.compile` to produce watch and phone artifacts.
3. `pebble.package` when ready to install on hardware or the emulator.

Fix any missing-vector diagnostics by importing the corresponding asset.

## 5. Exercise the companion flow

1. Start the debugger with `debugger.start`.
2. Connect the phone companion bridge in the IDE workspace.
3. Confirm the watch sends `RequestWeather CurrentLocation`.
4. Verify the phone responds with `ProvideTemperature` and `ProvideCondition`.
5. Change the Open-Meteo location or weather code mapping in
   `phone/src/CompanionApp.elm` to trigger a different condition.
6. Observe the watch switch from `Ui.drawVectorAt` to
   `Ui.drawVectorSequenceAt` during the transition, then settle on the new
   static icon.

Use `debugger.state` and `sessions.summary` to inspect recent companion traffic.

## 6. Capture a showcase screenshot

When the watchface renders correctly:

```json
{
  "slug": "weather-animated"
}
```

Call `screenshots.capture` (requires `build` capability) to store an emulator
frame for documentation or regression comparison.

## Troubleshooting

- **Missing constructors at compile time** — regenerate resources by re-opening
  the Resources page or running `compiler.check` (which calls
  `ResourceStore.ensure_generated/1`).
- **Blank icon area** — placeholder manifest entries have `"bytes": 0`; import
  the actual PDC/SVG asset for that constructor.
- **Transition snaps instantly** — import the matching
  `Transition<From>To<To>` sequence; unmapped pairs fall back to an immediate
  icon swap.
- **Stale weather** — the watch re-requests every 30 minutes on minute ticks;
  force a refresh by reloading the debugger or sending another `RequestWeather`.

## Related docs

- `docs/IDE_MCP.md` — MCP tool reference
- `docs/PEBBLE_PHONE_PROTOCOL.md` — companion messaging overview
