# elm-pebble

This is the Elm-based Pebble development platform.

## Current Scope Kept In Repo

- `elmc/` - Elm-to-C compiler, runtime, and conformance tests.
- `ide/` - Phoenix LiveView IDE app (Phases 1-3 baseline).
- `src/` - shared Elm-side Pebble API surface currently used by fixtures/apps.
- `shared/` - cross-target Elm protocol modules (watch + companion).
- `ide/priv/pebble_app_template/` - Pebble app template/shim used by IDE publish builds.

## Docker (persistent by default)

Run the IDE container with persistent storage:

```bash
docker compose up -d
```

This starts `elm-pebble-ide` on [http://localhost:4000/projects](http://localhost:4000/projects)
and stores all runtime data in the named volume `elm_pebble_ide_data`:

- SQLite database (`/var/lib/ide/ide_prod.db`)
- project workspace files (`/var/lib/ide/workspace_projects`)
- user settings (`/var/lib/ide/config/settings.json`)
- Pebble SDK state (`/var/lib/ide/.pebble-sdk`)

Container image includes required toolchain binaries:

- `elm` (installed globally via npm)
- `pebble` CLI (`pebble-tool`)

On first startup, the container installs/activates the Pebble SDK automatically
(`PEBBLE_SDK_VERSION=latest` by default). To pin a specific SDK version, set:

```bash
PEBBLE_SDK_VERSION=4.9.148 docker compose up -d
```

The first startup can take a few minutes while SDK/toolchain artifacts download.

To skip automatic SDK installation/activation:

```bash
INSTALL_PEBBLE_SDK=0 docker compose up -d
```

To use an external disk path instead of a Docker-managed volume:

```bash
cp docker-compose.external-disk.example.yml docker-compose.override.yml
# edit the host path in docker-compose.override.yml
docker compose up -d
```

The image build pipeline is defined in `.github/workflows/docker-image.yml`.
On pushes, GitHub Actions publishes images to GitHub Container Registry as
`ghcr.io/<owner>/<repo>`.

To run a published image directly:

```bash
ELM_PEBBLE_IMAGE=ghcr.io/synalysis/elm-pebble:latest docker compose up -d
```

## Next Direction

The target architecture and staged execution plan for the IDE are captured in:

- `docs/IDE_ROADMAP.md`
