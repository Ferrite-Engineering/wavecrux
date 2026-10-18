#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# SPDX-License-Identifier: 0BSD
"""Independent RVFI retire dump from a VCD, for cross-checking WaveCrux.

Shares no code with WaveCrux: it parses the VCD text directly and prints one
line per cycle in which rvfi_valid is high, sampled just before the rising
clock edge. Unlike WaveCrux it also reads CV32E40X's nonstandard rvfi_dbg
channel, so run it on the raw (untrimmed) VCD to see the debug cause:

    python3 dump_retires.py raw.vcd
    python3 dump_retires.py raw_debug.vcd

maddr shows the low 32 bits of rvfi_mem_addr (slot 0); hi=nz marks a
retirement that used a second memory slot.
"""
import sys
SC="tb_cv32e40x_rvfi.wrapper_i.rvfi_i"
want=['rvfi_valid','rvfi_order','rvfi_insn','rvfi_trap','rvfi_intr','rvfi_mode','rvfi_ixl','rvfi_halt',
'rvfi_rs1_addr','rvfi_rs1_rdata','rvfi_rs2_addr','rvfi_rs2_rdata','rvfi_rd_addr','rvfi_rd_wdata',
'rvfi_pc_rdata','rvfi_pc_wdata','rvfi_mem_addr','rvfi_mem_rmask','rvfi_mem_wmask','rvfi_mem_rdata','rvfi_mem_wdata','rvfi_dbg']
idmap={};scope=[];vals={};clk=None
lines=open(sys.argv[1])
for line in lines:
    s=line.split()
    if not s: continue
    if s[0]=='$scope': scope.append(s[2])
    elif s[0]=='$upscope': scope.pop()
    elif s[0]=='$var':
        full='.'.join(scope+[s[4]])
        if '.'.join(scope)==SC and s[4] in want: idmap.setdefault(s[3],[]).append(s[4])
        if full=='tb_cv32e40x_rvfi.clk': clk=s[3]
    elif s[0]=='$enddefinitions': break
rows=[]
def snap(t):
    if vals.get('rvfi_valid',0)==1: rows.append((t,dict(vals)))
t=0
for line in lines:
    s=line.strip()
    if not s: continue
    if s[0]=='#':
        t=int(s[1:]); continue
    if s[0] in 'bB':
        v,ident=s[1:].split()
        val=int(v.replace('x','0').replace('z','0'),2)
    elif s[0] in '01xz':
        ident=s[1:]; val=1 if s[0]=='1' else 0
    else: continue
    if ident==clk and val==1:
        # sample state just before this rising edge = values settled in the previous cycle
        snap(t)
    for n in idmap.get(ident,[]): vals[n]=val
for t,v in rows:
    m=lambda k:v.get(k,0)
    print(f"t={t:>6} ord={m('rvfi_order'):>3} pc={m('rvfi_pc_rdata'):03x}->{m('rvfi_pc_wdata'):03x} insn={m('rvfi_insn'):08x} trap={m('rvfi_trap'):04x} intr={m('rvfi_intr'):04x} mode={m('rvfi_mode')} rd=x{m('rvfi_rd_addr')}={m('rvfi_rd_wdata'):x} rs1=x{m('rvfi_rs1_addr')} rs2=x{m('rvfi_rs2_addr')} maddr={m('rvfi_mem_addr')&0xffffffff:x}(hi={'nz' if m('rvfi_mem_addr')>>32 else 0}) rm={m('rvfi_mem_rmask'):x} wm={m('rvfi_mem_wmask'):x} rd={m('rvfi_mem_rdata'):x} wd={m('rvfi_mem_wdata'):x} dbg={m('rvfi_dbg')}")
print(len(rows),'retirement-cycles')
