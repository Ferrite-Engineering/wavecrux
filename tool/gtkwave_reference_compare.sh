#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Layer-3 reference comparison (ARCHITECTURE.md §8.9): cross-check the
# committed fixtures against an INDEPENDENT reader from the GTKWave family.
#
# For each VCD known-answer fixture and its committed FST mirror, GTKWave's
# `fst2vcd` reads the FST and re-emits a VCD. We then diff the *signal
# declarations* (name + width) of GTKWave's reading against the original
# hand-crafted VCD. A divergence means either our FST mirror is stale or the
# GTKWave VCD↔FST toolchain disagrees with our fixture — both worth a human
# look. Value-change counts are reported as information only (formatting and
# coalescing legitimately differ between writers).
#
# Designed to run as a NON-BLOCKING CI job (continue-on-error) on a Linux
# runner where GTKWave is installable, per the §8.9 Layer-3 plan. Promote to
# blocking once the signal is trusted. Requires GTKWave's `fst2vcd`.
#
#   tool/gtkwave_reference_compare.sh
#
# Exit status: 0 if every fixture's signal declarations match, 1 otherwise.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
vcd_dir="$root/test/fixtures/vcd"
fst_dir="$root/test/fixtures/fst"

if ! command -v fst2vcd >/dev/null 2>&1; then
  echo "error: fst2vcd not found on PATH (install GTKWave)" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Extracts a sorted "name width" line per $var declaration, normalizing the
# whitespace GTKWave and the hand-authored VCDs format differently.
#   $var wire 8 ! data $end  ->  "data 8"
#
# `real` vars are normalized to width "real": a VCD real is conventionally
# declared width 1 while GTKWave's fst2vcd emits width 64 (a real is a 64-bit
# double). That representational difference is benign, so we compare on the
# type rather than the numeric width for reals — genuine name/width divergence
# on logic signals still fails.
declarations() {
  grep -E '^\s*\$var' "$1" \
    | awk '{ w = ($2 == "real") ? "real" : $3; print $5, w }' \
    | sort
}

value_changes() {
  # Count value-change tokens: scalar (0/1/x/z + id), vector (b.../r... + id).
  grep -cE '^([01xzXZ]|b[01xzXZ]+ |r[-0-9.eE+]+ )' "$1" || true
}

status=0
echo "── GTKWave reference comparison (fst2vcd vs source VCD) ──"
for vcd in "$vcd_dir"/*.vcd; do
  [ -e "$vcd" ] || continue
  name="$(basename "$vcd" .vcd)"

  # Error-path fixtures (deliberately malformed VCDs exercised only by the
  # parser error-path tests, e.g. waveform_source_provider_open_test.dart) are
  # NOT known-answer mirrors: they have no committed FST and must be excluded.
  # The curated known-answer set is the `_fixtures` list in
  # test/services/waveform/fst_vcd_equivalence_test.dart.
  case "$name" in
    malformed_*)
      echo "SKIP  $name (error-path fixture; no FST mirror by design)"
      continue
      ;;
  esac

  fst="$fst_dir/$name.fst"
  if [ ! -e "$fst" ]; then
    echo "WARN  $name: no committed FST mirror (run tool/generate_fst_mirrors.sh)"
    status=1
    continue
  fi

  rt="$work/$name.roundtrip.vcd"
  if ! fst2vcd "$fst" >"$rt" 2>/dev/null; then
    echo "FAIL  $name: fst2vcd could not read the committed FST"
    status=1
    continue
  fi

  src_decls="$work/$name.src.decls"
  rt_decls="$work/$name.rt.decls"
  declarations "$vcd" >"$src_decls"
  declarations "$rt" >"$rt_decls"

  if diff -q "$src_decls" "$rt_decls" >/dev/null; then
    echo "PASS  $name: $(wc -l <"$src_decls" | tr -d ' ') signals match" \
         "(vcd Δ=$(value_changes "$vcd"), gtkwave Δ=$(value_changes "$rt"))"
  else
    echo "FAIL  $name: signal declarations diverge —"
    diff "$src_decls" "$rt_decls" | sed 's/^/        /'
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo "── reference comparison found discrepancies (non-blocking) ──"
fi
exit "$status"
