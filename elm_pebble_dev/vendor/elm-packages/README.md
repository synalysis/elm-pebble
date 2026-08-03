Vendored Elm packages that cannot be fetched from GitHub version tags.

Used by `scripts/seed-elm-packages.sh` when seeding `ELM_HOME` for cold CI.

- `lamdera/codecs/1.0.0` — not on package.elm-lang.org; public repo has no
  version tags (Lamdera injects this package). Sources only (`elm.json` +
  `src/`), BSD-3-Clause.
