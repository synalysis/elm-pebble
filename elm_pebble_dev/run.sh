#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"
npm run gen:tailwind
npx elm-pages dev --port 8765
