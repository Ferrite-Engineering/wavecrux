#!/usr/bin/env bash
# Copyright (c) WaveCrux contributors.
# SPDX-License-Identifier: 0BSD
#
# Reproduce: riscv-formal's `ill` check passes on eduBOS5 without its
# precondition ever occurring.
#
# For each eduBOS5 pipeline (EN_WAIT4REGS 0 and 1) this
#   1. runs the `ill` check and the `cover` check exactly as the core's own
#      formal/run-riscv-formal.sh and formal/checks.cfg run them (unmodified);
#      `cover` is the control: instructions do retire within the bound,
#   2. reruns the `ill` check in SymbiYosys cover mode, which asks whether the
#      check's own cover statement (rvfi_ill_check.sv:46: a retirement of the
#      all-zero instruction word at the check cycle) is reachable at all,
# and prints a summary that README.md explains and expected.txt records.
#
# Pinned: openPCIE (eduBOS5) a0d80cd3cb525f911cae61be4c83a44e137ed916, via the
# capture's Makefile, and riscv-formal c992aa61fdfe0846c5ed90324c596202a1c69b76.
#
# Requirements on PATH: git, make, python3 with `click`, sby (SymbiYosys),
# yosys WITH the slang front end as `yosys` (read_slang; e.g. a wrapper that
# runs `yosys -m slang.so "$@"`), yosys-abc, yosys-smtbmc, z3, and GNU sed as
# `sed` (run-riscv-formal.sh uses GNU `sed -i ... a`).
#
# Usage: ./run-ill-cover.sh            # prints the summary, compares to expected.txt
#        RISCV_FORMAL=<clone> ./run-ill-cover.sh   # use an existing checkout
#                                                  # (must be at the pinned commit)
#        KEEP_WORK=1 ./run-ill-cover.sh # keep the riscv-formal work folders
#                                       # (paths are printed on stderr)

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HELPER=$(cd "$HERE/.." && pwd)

OPENPCIE_SHA=a0d80cd3cb525f911cae61be4c83a44e137ed916
RVF_URL=https://github.com/YosysHQ/riscv-formal.git
RVF_SHA=c992aa61fdfe0846c5ed90324c596202a1c69b76
RVF=${RISCV_FORMAL:-$HERE/riscv-formal-src}

fail() {
  echo "run-ill-cover.sh: $*" >&2
  exit 2
}

for tool in git make python3 sby yosys yosys-abc yosys-smtbmc z3 sed; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing on PATH: $tool"
done
sed --version 2>/dev/null | grep -q 'GNU sed' ||
  fail "\`sed\` on PATH is not GNU sed"
yosys -q -p 'help read_slang' >/dev/null 2>&1 ||
  fail "\`yosys\` on PATH has no read_slang (load the yosys-slang plugin)"
python3 -c 'import click' 2>/dev/null ||
  fail "python3 has no \`click\` module (SymbiYosys needs it)"

# 1. eduBOS5 at the pinned openPCIE commit, shared with the capture's Makefile.
make -s -C "$HELPER" openPCIE/.pinned
CPU=$HELPER/openPCIE/2.rtl/0.common.opensource/src/CPU.eduBOS5
[ "$(git -C "$HELPER/openPCIE" rev-parse HEAD)" = "$OPENPCIE_SHA" ] ||
  fail "openPCIE checkout is not at $OPENPCIE_SHA (run make distclean in $HELPER)"

# 2. riscv-formal at the pinned commit (single-commit shallow fetch).
if [ -z "${RISCV_FORMAL:-}" ] && [ ! -f "$RVF/.pinned" ]; then
  rm -rf "$RVF"
  git init -q "$RVF"
  git -C "$RVF" remote add origin "$RVF_URL"
  git -C "$RVF" fetch -q --depth 1 origin "$RVF_SHA"
  git -C "$RVF" checkout -q --detach FETCH_HEAD
  touch "$RVF/.pinned"
fi
[ "$(git -C "$RVF" rev-parse HEAD)" = "$RVF_SHA" ] ||
  fail "riscv-formal checkout $RVF is not at $RVF_SHA"

{
  echo "yosys:  $(yosys -V)"
  echo "sby:    $(command -v sby)"
  echo "z3:     $(z3 --version)"
} >&2

out=$(mktemp)
trap 'rm -f "$out"' EXIT

{
  echo "eduBOS5: openPCIE $OPENPCIE_SHA"
  echo "riscv-formal: $RVF_SHA"
  echo
  echo "Why an all-zero word never retires (edubos5.sv at the pinned commit):"
  grep -n 'default: instr_decode.SYSTEM' "$CPU/edubos5.sv" | sed 's/  */ /g'
  grep -n 'if (!instr_decode.SYSTEM)' "$CPU/edubos5.sv" | sed 's/  */ /g'
  echo
  echo "The ill check's precondition (rvfi_ill_check.sv):"
  grep -n 'cover(!reset && check && valid && insn == 0)' \
    "$RVF/checks/rvfi_ill_check.sv" | sed 's/^\([0-9]*\):\s*/\1: /'
  grep -n 'assume(insn == 0)' "$RVF/checks/rvfi_ill_check.sv" |
    sed 's/^\([0-9]*\):\s*/\1: /'

  for en in 0 1; do
    echo
    echo "EN_WAIT4REGS=$en"

    # The authors' own flow, unmodified: genchecks, then two make targets.
    log=$(RISCV_FORMAL="$RVF" bash "$CPU/formal/run-riscv-formal.sh" "$en" 1 \
      "ill_ch0 cover")
    work=$(printf '%s\n' "$log" | sed -n 's/^work folder: //p')
    [ -n "$work" ] || fail "run-riscv-formal.sh printed no work folder"
    echo "  work folder: $work" >&2
    cover_status=$(printf '%s\n' "$log" | awk '$1 == "cover" { print $2 }')
    echo "  cover (control, checks.cfg [cover]: two instructions retire)," \
      "mode cover: $cover_status"
    status=$(printf '%s\n' "$log" | awk '$1 == "ill_ch0" { print $2 }')
    depth=$(sed -n 's/^depth //p' "$work/checks/ill_ch0.sby")
    check_cycle=$(sed -n 's/^`define RISCV_FORMAL_CHECK_CYCLE //p' \
      "$work/checks/ill_ch0.sby")
    echo "  ill_ch0, mode bmc (as run-riscv-formal.sh runs it): $status" \
      "(depth $depth, check cycle $check_cycle)"

    # The same check in cover mode: is its own cover statement reachable?
    # Only the mode, the engine (ABC has no cover mode) and the file name
    # change; the design, the wrapper and the check are the same.
    cd "$work/checks"
    sed -e 's/^mode bmc$/mode cover/' \
      -e '/^aigsmt /d' \
      -e '/^expect /d' \
      -e 's/^abc bmc3$/smtbmc z3/' \
      -e 's/ill_ch0\.sv/cover_ill_ch0.sv/g' \
      ill_ch0.sby >cover_ill_ch0.sby
    sby -f cover_ill_ch0.sby >/dev/null 2>&1 || true
    cover_log=cover_ill_ch0/logfile.txt
    last_step=$(grep -o 'Checking cover reachability in step [0-9]*' "$cover_log" |
      tail -1 | awk '{ print $NF }')
    unreached=$(grep -o 'Unreached cover statement at [^ ]* rvfi_ill_check.sv:[0-9.-]*' \
      "$cover_log" | sed 's/.* rvfi_ill_check/rvfi_ill_check/' | sort -u)
    verdict=$(grep -o 'DONE ([A-Z]*, rc=[0-9]*)' "$cover_log" | tail -1)
    echo "  cover_ill_ch0, mode cover: searched steps 0..$last_step," \
      "unreached: ${unreached:-none}, $verdict"
    cd "$HERE"
    if [ "${KEEP_WORK:-0}" != 1 ]; then
      rm -rf "${work%/cores/edubos5}"
    fi
  done
} | tee "$out"

echo
if diff -u "$HERE/expected.txt" "$out" >&2; then
  echo "run-ill-cover.sh: output matches expected.txt"
else
  echo "run-ill-cover.sh: output DIFFERS from expected.txt (diff above)"
  exit 1
fi
