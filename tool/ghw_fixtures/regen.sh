#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Regenerates the GHW functional fixture from the in-house VHDL testbench.
# Requires GHDL (brew install ghdl / apt install ghdl).
#
#   tool/ghw_fixtures/regen.sh
#
# Output: test/fixtures/real_world/wavecrux_vhdl_types.ghw
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../test/fixtures/real_world/wavecrux_vhdl_types.ghw"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"
ghdl -a --std=08 "$here/wavecrux_vhdl_types_tb.vhd"
ghdl -e --std=08 wavecrux_vhdl_types_tb
ghdl -r --std=08 wavecrux_vhdl_types_tb --wave="$out" --stop-time=600ns
echo "wrote $out ($(du -h "$out" | cut -f1))"
