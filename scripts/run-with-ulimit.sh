#!/usr/bin/env bash
# Run a command under a virtual-memory cap (native binaries and mix alike).
# Override via TEST_ULIMIT_V_KB (default 4 GiB for ad-hoc probes).
set -euo pipefail

ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-4194304}"
ulimit -v "${ULIMIT_V_KB}"
exec "$@"
