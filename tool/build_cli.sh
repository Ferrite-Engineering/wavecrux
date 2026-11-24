#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build the headless `wavecrux` binary: `info`, `search`, `values`,
# `transitions` and `mcp`.
#
# The binary reads waveforms through the same native wellen library the app
# bundles, so the archive is the executable plus that library:
#
#   <output-dir>/bundle/bin/wavecrux        (wavecrux.exe on Windows)
#   <output-dir>/bundle/lib/libwellen_ffi.{dylib,so} (wellen_ffi.dll)
#
# `openWellenFfiLibrary` looks beside the executable and in `../lib/`, so the
# bundle runs from wherever it is unpacked.
#
# Why `dart build cli` and not `dart compile exe`: `dart compile` refuses to
# run when any package in the resolution declares a native build hook, and
# `objective_c` does, pulled in by a Flutter plugin the desktop app needs and
# this binary never touches (resolution is per package, not per entry point).
# `dart build cli` compiles the same AOT executable and puts any hook assets
# in `bundle/lib/`, where the wellen library joins them. LintCrux and
# SimCrux build their binaries the same way.
#
# This script is also a proof that the binary's import closure is
# Flutter-free: a `package:flutter/...` import anywhere in it fails the
# compile here (`test/static/headless_cli_closure_test.dart` catches it
# sooner).
#
# Usage:
#   tool/build_cli.sh [output-dir]        # default: build/cli
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-build/cli}"
BUNDLE="${OUT_DIR}/bundle"

case "$(uname -s)" in
  Darwin) LIB_NAME="libwellen_ffi.dylib"; EXE="wavecrux" ;;
  Linux) LIB_NAME="libwellen_ffi.so"; EXE="wavecrux" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="wellen_ffi.dll"; EXE="wavecrux.exe" ;;
  *) echo "error: no build for $(uname -s)" >&2; exit 1 ;;
esac

LIB="native/wellen_ffi/target/release/${LIB_NAME}"
if [[ ! -f "${LIB}" ]]; then
  echo "==> cargo build --release (wellen_ffi)"
  cargo build --release --manifest-path native/wellen_ffi/Cargo.toml
fi

echo "==> dart build cli -t bin/wavecrux.dart -o ${OUT_DIR}"
dart build cli -t bin/wavecrux.dart -o "${OUT_DIR}"
mkdir -p "${BUNDLE}/lib"
cp "${LIB}" "${BUNDLE}/lib/${LIB_NAME}"

BIN="${BUNDLE}/bin/${EXE}"
if [[ ! -x "${BIN}" ]]; then
  echo "error: expected executable at ${BIN}" >&2
  exit 1
fi

echo "==> smoke test"
"${BIN}" --version
"${BIN}" --help > /dev/null
# Reads a waveform, so the bundled library is found and loads.
"${BIN}" info spec/fixtures/handshake.vcd --json > /dev/null

echo "==> built ${BIN}"
