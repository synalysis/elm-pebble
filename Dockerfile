FROM elixir:1.17.3-otp-27 AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates nodejs npm && \
    rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
WORKDIR /app

COPY . .

WORKDIR /app/ide

RUN mix local.hex --force && \
    curl -fsSL https://github.com/erlang/rebar3/releases/download/3.24.0/rebar3 -o /usr/local/bin/rebar3 && \
    chmod +x /usr/local/bin/rebar3
RUN chmod +x scripts/sync_bundled_elm.sh && scripts/sync_bundled_elm.sh /app
RUN mix deps.get --only prod
RUN mix deps.compile
RUN mix compile
RUN npm ci --prefix assets
RUN npm run typecheck --prefix assets
RUN mix assets.deploy
RUN mix release

# gif2apng 1.9 (Pebble-recommended GIF → APNG converter); not in Debian repos.
FROM debian:bookworm-slim AS gif2apng-builder

ARG GIF2APNG_VERSION=1.9
ARG GIF2APNG_SRC_URL=https://sourceforge.net/projects/gif2apng/files/1.9/gif2apng-1.9-src.zip/download

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      unzip \
      zlib1g-dev && \
    curl -fsSL -o /tmp/gif2apng.zip "${GIF2APNG_SRC_URL}" && \
    unzip -q /tmp/gif2apng.zip -d /tmp/gif2apng-src && \
    make -C /tmp/gif2apng-src && \
    install -m 0755 /tmp/gif2apng-src/gif2apng /usr/local/bin/gif2apng && \
    rm -rf /var/lib/apt/lists/* /tmp/gif2apng.zip /tmp/gif2apng-src

FROM debian:bookworm-slim AS runner

ARG PEBBLE_SDK_VERSION=4.9.169

COPY --from=gif2apng-builder /usr/local/bin/gif2apng /usr/local/bin/gif2apng

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      zlib1g \
      openssl \
      libncurses6 \
      ca-certificates \
      bzip2 \
      python3 \
      pipx \
      git \
      curl \
      patch \
      xz-utils \
      build-essential \
      qemu-system-data \
      qemu-system-common \
      libsdl2-2.0-0 \
      libfreetype6 \
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
ENV PEBBLE_SDK_VERSION=${PEBBLE_SDK_VERSION}
ENV INSTALL_PEBBLE_SDK=1
ENV ELM_PEBBLE_QEMU_BIN=/var/lib/ide/.pebble-sdk/SDKs/current/toolchain/bin/qemu-pebble
ENV ELM_PEBBLE_PYPKJS_BIN=/opt/pipx/venvs/pebble-tool/bin/pypkjs
ENV ELM_PEBBLE_QEMU_IMAGE_ROOT=/var/lib/ide/.pebble-sdk/SDKs/current/sdk-core/pebble
ENV ELM_PEBBLE_QEMU_DATA_ROOT=/usr/share/qemu
ENV ELM_PEBBLE_QEMU_DOWNLOAD_IMAGES=1
ENV SECRET_KEY_BASE=8eXjTGrTXoJHN8S-sqKoLrXp1xQ8vlqv2Ryr_5wPjMz5f4lAQ9S3v5dvU7uIGrYb

WORKDIR /opt/ide

COPY --from=build /app/ide/_build/prod/rel/ide /opt/ide
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/pebble_sdk.sh /docker/pebble_sdk.sh
RUN mkdir -p /var/lib/ide && \
    chmod +x /entrypoint.sh /docker/pebble_sdk.sh && \
    chown -R nobody:nogroup /var/lib/ide /opt/ide /entrypoint.sh /docker

USER nobody

EXPOSE 4000
VOLUME ["/var/lib/ide"]

ENTRYPOINT ["/entrypoint.sh"]
