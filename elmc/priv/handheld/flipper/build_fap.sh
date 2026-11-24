#!/bin/sh
# Assemble a ufbt app and build the .fap.
# With ELMC_OUT set to an `elmc --target flipper` directory, the Elm worker
# replaces smoke_app.c. Without it, the smoke bar is the program.
set -e
root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
dest=${1:-"$root/build"}
rm -rf "$dest"
mkdir -p "$dest"
cp "$root/application.fam" "$root/flipper_host.c" "$root/flipper_host.h" "$dest/"
cp "$root/../include/handheld_host.h" "$dest/"
if [ -n "$ELMC_OUT" ]; then
  cp "$root/../shim/elmc_handheld_shim.c" "$root/../meow_app_entry.c" "$dest/"
  cp "$ELMC_OUT"/c/elmc_generated.c "$ELMC_OUT"/c/elmc_generated.h \
    "$ELMC_OUT"/c/elmc_worker.c "$ELMC_OUT"/c/elmc_worker.h "$dest/"
  if [ -d "$ELMC_OUT/runtime" ]; then
    cp "$ELMC_OUT"/runtime/*.c "$ELMC_OUT"/runtime/*.h "$dest/"
  fi
  if [ -d "$ELMC_OUT/ports" ]; then
    cp "$ELMC_OUT"/ports/*.c "$ELMC_OUT"/ports/*.h "$dest/" 2>/dev/null || true
  fi
  # ufbt compiles sources in one directory, so the generated relative includes
  # have to point at the copies sitting next to them.
  for file in "$dest"/*.c "$dest"/*.h; do
    [ -f "$file" ] || continue
    sed -i \
      -e 's|#include "../runtime/elmc_runtime.h"|#include "elmc_runtime.h"|' \
      -e 's|#include "../ports/elmc_ports.h"|#include "elmc_ports.h"|' \
      "$file"
  done
  for file in "$dest"/*.c; do
    [ -f "$file" ] || continue
    tmp=$(mktemp)
    printf '%s\n' '#pragma GCC diagnostic ignored "-Wredundant-decls"' | cat - "$file" > "$tmp"
    mv "$tmp" "$file"
  done
else
  cp "$root/smoke_app.c" "$dest/"
fi
cd "$dest"
exec ufbt
