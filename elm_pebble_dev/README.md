# elm-pebble.dev

elm-pages site for [elm-pebble.dev](https://elm-pebble.dev).

## Render Deployment

This directory includes a `render.yaml` Blueprint for deploying this site as a
Render Static Site. When creating the Blueprint in Render, set the Blueprint file
path to `elm_pebble_dev/render.yaml`.

Equivalent manual Render settings:

- **Service type:** Static Site
- **Blueprint file path:** `elm_pebble_dev/render.yaml`
- **Root directory:** `elm_pebble_dev`
- **Build command:** `npm ci --include=dev && npm run build`
- **Publish directory:** `dist`
- **Environment variable:** `NODE_VERSION=22.12.0`

The build runs elm-pages and publishes the generated static files from `dist/`.
