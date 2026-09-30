#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Regenerates FST mirrors of the hand-crafted VCD known-answer fixtures.
#
# Each VCD under test/fixtures/vcd/ is converted to an equivalent FST via
# GTKWave's `vcd2fst`, committed alongside the VCD under test/fixtures/fst/.
# The FST front-end of wellen must read these byte-for-byte equivalently to
# the VCD (validated by test/services/waveform/fst_vcd_equivalence_test.dart),
# which is what justifies committing the mirrors: it exercises wellen's FST
# reader against the same known answers as the VCD reader.
#
# Requires GTKWave's vcd2fst (brew install gtkwave / apt install gtkwave).
#
#   tool/generate_fst_mirrors.sh
#
# Output: test/fixtures/fst/<name>.fst for every test/fixtures/vcd/<name>.vcd
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
vcd_dir="$root/test/fixtures/vcd"
fst_dir="$root/test/fixtures/fst"

if ! command -v vcd2fst >/dev/null 2>&1; then
  echo "error: vcd2fst not found on PATH (install GTKWave)" >&2
  exit 1
fi

mkdir -p "$fst_dir"

count=0
for vcd in "$vcd_dir"/*.vcd; do
  [ -e "$vcd" ] || continue
  name="$(basename "$vcd" .vcd)"

  # Skip error-path fixtures (deliberately malformed VCDs used only by the
  # parser error-path tests). They are not known-answer mirrors — vcd2fst would
  # emit a bogus/partial FST — and the reference comparison
  # (tool/gtkwave_reference_compare.sh) excludes them the same way.
  case "$name" in
    malformed_*)
      echo "skip  $name (error-path fixture; not mirrored)"
      continue
      ;;
  esac

  out="$fst_dir/$name.fst"
  vcd2fst "$vcd" "$out" >/dev/null 2>&1
  echo "wrote $(basename "$out") ($(du -h "$out" | cut -f1))"
  count=$((count + 1))
done

echo "generated $count FST mirror(s) in test/fixtures/fst/"
