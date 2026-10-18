#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# SPDX-License-Identifier: 0BSD
"""Trim a full-hierarchy VCD down to a whitelist of full signal paths.

Verilator ignores the scope/level arguments to $dumpvars, so the raw capture
contains the entire CV32E40X hierarchy (~3570 signals). This filter keeps only
the 21 RVFI channels WaveCrux binds plus clock and reset, preserving the real
hierarchical names (tb_cv32e40x_rvfi.wrapper_i.rvfi_i.rvfi_*) that a user's
own CV32E40X simulation with the upstream wrapper would emit. CV32E40X's
extension ports (rvfi_dbg, rvfi_csr_*, rvfi_gpr_*, ...) are dropped; read the
raw VCD for those.

Usage: trim.py <in.vcd> <out.vcd>
"""

import re
import sys

RVFI_CHANNELS = [
    'rvfi_valid', 'rvfi_order', 'rvfi_insn', 'rvfi_trap', 'rvfi_halt',
    'rvfi_intr', 'rvfi_mode', 'rvfi_ixl', 'rvfi_rs1_addr', 'rvfi_rs1_rdata',
    'rvfi_rs2_addr', 'rvfi_rs2_rdata', 'rvfi_rd_addr', 'rvfi_rd_wdata',
    'rvfi_pc_rdata', 'rvfi_pc_wdata', 'rvfi_mem_addr', 'rvfi_mem_rmask',
    'rvfi_mem_wmask', 'rvfi_mem_rdata', 'rvfi_mem_wdata',
]

KEEP = {'tb_cv32e40x_rvfi.clk', 'tb_cv32e40x_rvfi.rst_n'}
KEEP |= {'tb_cv32e40x_rvfi.wrapper_i.rvfi_i.' + c for c in RVFI_CHANNELS}

VAR_RE = re.compile(r'^\$var\s+(\S+)\s+(\d+)\s+(\S+)\s+(.+?)\s*\$end\s*$')


def main():
    src, dst = sys.argv[1], sys.argv[2]

    scope = []
    keep_ids = set()
    header = []
    seen = set()

    with open(src) as fh:
        lines = fh.readlines()

    # --- header pass -------------------------------------------------
    end_idx = 0
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('$enddefinitions'):
            end_idx = idx
            break

    scope_stack = []
    pending = []  # emitted lazily so empty scopes are dropped
    for line in lines[:end_idx]:
        stripped = line.strip()
        if stripped.startswith('$scope'):
            parts = stripped.split()
            scope_stack.append(parts[2])
            pending.append(('scope', line))
        elif stripped.startswith('$upscope'):
            scope_stack.pop()
            if pending and pending[-1][0] == 'scope':
                pending.pop()          # scope turned out to be empty
            else:
                pending.append(('up', line))
        else:
            match = VAR_RE.match(stripped)
            if match:
                _typ, _width, ident, name = match.groups()
                leaf = name.split()[0]  # strip any "[31:0]" range suffix
                full = '.'.join(scope_stack + [leaf])
                if full in KEEP:
                    keep_ids.add(ident)
                    seen.add(full)
                    pending.append(('var', line))
            elif stripped.startswith('$date') or stripped.startswith('$version') \
                    or stripped.startswith('$timescale') or stripped.startswith('$end') \
                    or stripped.startswith('$comment'):
                header.append(line)
            elif not stripped.startswith('$'):
                header.append(line)   # continuation of $date/$version/$timescale

    # collapse trailing empty scopes
    while pending and pending[-1][0] == 'scope':
        pending.pop()

    missing = KEEP - seen
    if missing:
        sys.exit('trim.py: signals not found in source VCD: %s' % sorted(missing))

    # --- body pass ---------------------------------------------------
    body = []
    for line in lines[end_idx + 1:]:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped[0] == '#':
            body.append(stripped)
        elif stripped in ('$dumpvars', '$dumpall', '$end'):
            body.append(stripped)
        elif stripped[0] in 'bBrR':
            value, _, ident = stripped.rpartition(' ')
            if ident in keep_ids:
                body.append(stripped)
        else:
            ident = stripped[1:]
            if ident in keep_ids:
                body.append(stripped)

    # drop timestamps that ended up with no value changes
    pruned = []
    for entry in body:
        if entry.startswith('#') and pruned and pruned[-1].startswith('#'):
            pruned[-1] = entry
            continue
        pruned.append(entry)
    if pruned and pruned[-1].startswith('#'):
        pruned.pop()

    with open(dst, 'w') as out:
        out.writelines(header)
        out.writelines(line for _kind, line in pending)
        out.write('$enddefinitions $end\n')
        for entry in pruned:
            out.write(entry + '\n')

    print('trim.py: kept %d signals (%d ids), %d body lines'
          % (len(seen), len(keep_ids), len(pruned)))


if __name__ == '__main__':
    main()
