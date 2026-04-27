# Repo Cleanup And Scope

This document defines what we keep for the initial monorepo baseline and what
is treated as generated/transient.

## Keep (Source of Truth)

- `elmc/` source code, tests, scripts, docs.
- `src/` shared Elm API modules.
- `shared/elm` and `shared/elm-companion` protocol modules.
- `ide/priv/pebble_app_template/` source and scripts.

## Do Not Track In Git

- Mix output: `_build/`, `deps/`, `tmp/`.
- Elm output: `elm-stuff/`.
- Pebble app output: `build/`, generated maps/binaries.
- Local screenshots and ad-hoc debug assets.

These are excluded via root `.gitignore`.

## Initial Commit Intent

The initial commit should represent a reproducible source baseline, not local
machine build output. Any generated code required for runtime operation should
be reproducible by scripts already in the repository (for example
`ide/priv/pebble_app_template/scripts/generate_elmc.sh`).

## Structure We Will Evolve Toward

Planned top-level areas:

- `elmc/` - compiler and runtime generation.
- `ide/` - Phoenix LiveView web IDE (new).
- `projects/` - persisted user project workspaces (new, runtime-managed).
- `shared/` - cross-target protocol and library modules.
- `docs/` - architecture and operational docs.
