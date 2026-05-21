#!/bin/bash
set -euo pipefail

extra_cflags="${1:-}"
CFLAGS="${CFLAGS}${extra_cflags}"

format_args() {
  printf "'%s', " "$@" | sed 's/, $//'
}

{
  printf '%s\n' '[built-in options]'
  printf 'c_args = [%s]\n' "$(format_args ${CFLAGS})"
  printf 'cpp_args = [%s]\n' "$(format_args ${CFLAGS})"
  printf 'objc_args = [%s]\n' "$(format_args ${CFLAGS})"
  printf 'c_link_args = [%s]\n' "$(format_args ${LDFLAGS})"
  printf 'cpp_link_args = [%s]\n' "$(format_args ${LDFLAGS})"
} >> /cross.meson
