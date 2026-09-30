#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

#
# Regenerates the picorv32 captured FSM fixture for the FSM golden sweep
# (FSM robustness plan — Layer F).
#
# Fetches the upstream picorv32 core at a pinned commit, runs the committed
# testbench (tool/picorv32_fsm_tb.v) through Icarus Verilog, and writes the
# resulting cpu_state VCD into both the test/ and verification/ corpora. The
# $date header is stripped so the committed trace is byte-stable across
# regenerations.
#
# Requirements: iverilog + vvp (Icarus Verilog), curl. No RISC-V toolchain.
#
# Usage (from the repo root):
#   tool/generate_picorv32_fsm_capture.sh
#   REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart
#
# picorv32 is ISC-licensed (Copyright Claire Xenia Wolf / YosysHQ); see the
# captured/PROVENANCE.md for full attribution.
set -euo pipefail

# Pinned upstream source commit (YosysHQ/picorv32).
PICORV32_SHA="87c89acc18994c8cf9a2311e871818e87d304568"
PICORV32_URL="https://raw.githubusercontent.com/YosysHQ/picorv32/${PICORV32_SHA}/picorv32.v"

TB="tool/picorv32_fsm_tb.v"
NAME="picorv32_state"
DEST_DIRS=(
  "test/fixtures/fsm/${NAME}/captured"
  "verification/fixtures/fsm/${NAME}/captured"
)

if ! command -v iverilog >/dev/null 2>&1; then
  echo "error: iverilog (Icarus Verilog) is required but not on PATH" >&2
  exit 1
fi
if [[ ! -f "$TB" ]]; then
  echo "error: run from the repo root — $TB not found" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Fetching picorv32.v @ ${PICORV32_SHA:0:10} ..."
curl -fsSL "$PICORV32_URL" -o "$WORK/picorv32.v"

echo "Compiling + simulating ..."
iverilog -o "$WORK/sim" "$WORK/picorv32.v" "$TB"
( cd "$WORK" && vvp sim >/dev/null )

# Strip the non-deterministic $date block so the fixture is byte-stable.
awk '
  /^\$date/        { indate=1; next }
  indate && /^\$end/ { indate=0; next }
  indate           { next }
  { print }
' "$WORK/picorv32_state.vcd" > "$WORK/stripped.vcd"

for dir in "${DEST_DIRS[@]}"; do
  mkdir -p "$dir"
  cp "$WORK/stripped.vcd" "$dir/${NAME}.vcd"
  echo "wrote $dir/${NAME}.vcd ($(wc -c < "$dir/${NAME}.vcd" | tr -d ' ') bytes)"
done

echo
echo "Done. Now regenerate the golden:"
echo "  REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart"
