#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# SPDX-License-Identifier: 0BSD
"""Make a Verilator-compatible copy of upstream bhv/cv32e40x_wrapper.sv.

Verilator 5.049 dies with "Internal Error: V3LinkDot ... No symbol for
interface alias rhs" on the upstream wrapper's port connection
  .m_c_obi_instr_if ( core_i.m_c_obi_instr_if )
i.e. a hierarchical reference to an interface instance used as an interface
port actual. The copy declares a local monitor-side instance of the same
interface and drives its five members from the core's instance with plain
hierarchical continuous assigns. Signal values are identical; nothing in the
core or in cv32e40x_rvfi changes. This is the only edit.
"""
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
old = "( core_i.m_c_obi_instr_if                                              )"
assert text.count(old) == 1, 'upstream wrapper changed: anchor not found'
text = text.replace(old, "( rvfi_instr_mon_if )")
anchor = "    cv32e40x_rvfi\n      #(.CLIC  (CLIC),"
assert text.count(anchor) == 1, 'upstream wrapper changed: rvfi anchor not found'
shim = """    // --- Verilator shim (tb-side, see patch_wrapper.py) ---
    cv32e40x_if_c_obi #(.REQ_TYPE(obi_inst_req_t), .RESP_TYPE(obi_inst_resp_t)) rvfi_instr_mon_if();
    assign rvfi_instr_mon_if.s_req        = core_i.m_c_obi_instr_if.s_req;
    assign rvfi_instr_mon_if.s_gnt        = core_i.m_c_obi_instr_if.s_gnt;
    assign rvfi_instr_mon_if.req_payload  = core_i.m_c_obi_instr_if.req_payload;
    assign rvfi_instr_mon_if.s_rvalid     = core_i.m_c_obi_instr_if.s_rvalid;
    assign rvfi_instr_mon_if.resp_payload = core_i.m_c_obi_instr_if.resp_payload;

"""
text = text.replace(anchor, shim + anchor)
open(dst, 'w').write(text)
print('wrote', dst)
