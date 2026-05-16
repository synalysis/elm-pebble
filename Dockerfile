FROM elixir:1.17.3-otp-27 AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates nodejs npm && \
    rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
WORKDIR /app

COPY . .

WORKDIR /app/ide

RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod
RUN mix deps.compile
RUN mix compile
RUN npm ci --prefix assets
RUN mix assets.deploy
RUN mix release

FROM debian:bookworm-slim AS runner

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      openssl \
      libncurses6 \
      ca-certificates \
      bzip2 \
      python3 \
      pipx \
      qemu-system-data \
      nodejs \
      npm && \
    PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install pebble-tool && \
    npm install -g elm elm-format && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
ENV HOME=/var/lib/ide
ENV PHX_SERVER=true
ENV PORT=4000
ENV PHX_HOST=localhost
ENV IDE_DATA_ROOT=/var/lib/ide
ENV DATABASE_PATH=/var/lib/ide/ide_prod.db
ENV PROJECTS_ROOT=/var/lib/ide/workspace_projects
ENV SETTINGS_FILE=/var/lib/ide/config/settings.json
ENV PEBBLE_SDK_VERSION=latest
ENV INSTALL_PEBBLE_SDK=1
ENV ELM_PEBBLE_QEMU_BIN=/var/lib/ide/.pebble-sdk/SDKs/current/toolchain/bin/qemu-pebble
ENV ELM_PEBBLE_PYPKJS_BIN=/opt/pipx/venvs/pebble-tool/bin/pypkjs
ENV ELM_PEBBLE_QEMU_IMAGE_ROOT=/var/lib/ide/.pebble-sdk/SDKs/current/sdk-core/pebble
ENV ELM_PEBBLE_QEMU_DATA_ROOT=/usr/share/qemu
ENV ELM_PEBBLE_QEMU_DOWNLOAD_IMAGES=1
ENV ELM_PEBBLE_WASM_EMULATOR_ROOT=/var/lib/ide/wasm_emulator
ENV SECRET_KEY_BASE=8eXjTGrTXoJHN8S-sqKoLrXp1xQ8vlqv2Ryr_5wPjMz5f4lAQ9S3v5dvU7uIGrYb

WORKDIR /opt/ide

RUN mkdir -p /var/lib/ide /opt/ide && \
    chown -R nobody:nogroup /var/lib/ide /opt/ide

COPY --from=build /app/ide/_build/prod/rel/ide /opt/ide
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER nobody

EXPOSE 4000
VOLUME ["/var/lib/ide"]

ENTRYPOINT ["/entrypoint.sh"]
