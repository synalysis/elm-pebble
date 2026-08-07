# Yes Emery text parity fixture

Fixed-state reference for `mix ide.text_parity yes` and `Ide.Debugger.TextParityYesTest`.

| File | Purpose |
|------|---------|
| `emulator.png` | 200×228 firmware framebuffer from the embedded Emery emulator (`Ide.Emulator.screenshot/2`) |
| `labels.json` | Twelve dial label GRects from `runtime_view_output.json` |
| `runtime_view_output.json` | Debugger view-output rows for the Yes face |

## Gates

The harness compares **ink centroids** (not only mean `|dy|`) after:

- rasterizing the debugger as a **text-only** SVG (no hands/ticks/sun wedges)
- extracting glyph blobs in the lower band of each GRect (ticks enter from the dial)

Regression thresholds: mean `|dy| ≤ 1.0`, every label `|dy| ≤ 1.5`, mean height error ≤ 2.5.

## Refresh

```bash
# 1) Capture firmware LCD (embedded emulator — not pebble CLI emery)
mix run -e '...'  # Emulator.launch + install + screenshot → emulator.png

# 2) Refresh view ops + labels from the IDE debugger surface for users/3/yes
# 3) mix ide.text_parity yes
```

Pebble CLI `screenshot --emulator emery` returns a flat mask, not the LCD framebuffer.
