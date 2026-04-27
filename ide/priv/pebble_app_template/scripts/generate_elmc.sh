#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
ELMC_DIR="${ROOT_DIR}/elmc"
FIXTURE_DIR="${ELMC_DIR}/test/fixtures/simple_project"
TEMPLATE_DIR="${ROOT_DIR}/ide/priv/pebble_app_template"
OUT_DIR="${TEMPLATE_DIR}/src/c/elmc"
PROTOCOL_ELM="${ROOT_DIR}/shared/elm/Companion/Types.elm"
PROTOCOL_ELM_INTERNAL="${TEMPLATE_DIR}/src/elm/Companion/Internal.elm"
PROTOCOL_H="${TEMPLATE_DIR}/src/c/generated/companion_protocol.h"
PROTOCOL_C="${TEMPLATE_DIR}/src/c/generated/companion_protocol.c"
PROTOCOL_JS="${TEMPLATE_DIR}/src/pkjs/companion-protocol.js"

cd "${ROOT_DIR}/ide"
mix run -e "case Ide.CompanionProtocolGenerator.generate_elm_internal(\"${PROTOCOL_ELM}\", \"${PROTOCOL_ELM_INTERNAL}\") do :ok -> IO.puts(\"generated: ${PROTOCOL_ELM_INTERNAL}\"); {:error, e} -> IO.inspect(e); System.halt(1) end"

cd "${ELMC_DIR}"
mix run -e "case Elmc.compile(\"${FIXTURE_DIR}\", %{out_dir: \"${OUT_DIR}\", entry_module: \"Main\"}) do {:ok, _} -> IO.puts(\"generated: ${OUT_DIR}\"); {:error, e} -> IO.inspect(e); System.halt(1) end"

cd "${ROOT_DIR}/ide"
mix run -e "case Ide.CompanionProtocolGenerator.generate(\"${PROTOCOL_ELM}\", \"${PROTOCOL_H}\", \"${PROTOCOL_C}\", \"${PROTOCOL_JS}\") do :ok -> IO.puts(\"generated: ${PROTOCOL_H}\"); IO.puts(\"generated: ${PROTOCOL_JS}\"); {:error, e} -> IO.inspect(e); System.halt(1) end"
