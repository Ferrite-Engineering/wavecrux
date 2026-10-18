#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# SPDX-License-Identifier: 0BSD
"""Hand-assemble the RV32I + Zicsr program for tb_cv32e40x_rvfi.sv.

No RISC-V toolchain required. Modelled on the WaveCrux Ibex helper's
assemble.py, extended with jal / csrrw / csrrsi / mret and an interrupt.

Memory map (2 KiB, byte addresses 0x000-0x7FF):
  0x000  mtvec base: exceptions land here  -> jal to 0x100
  0x01C  mtvec + 4*7: machine timer irq    -> jal to 0x140
  0x080  boot_addr_i (CV32E40X boots exactly at boot_addr_i)
  0x100  exception handler (ecall): read mcause/mepc, mepc += 4, mret
  0x140  interrupt handler: read mcause/mepc, clear doorbell, mret
  0x200  data scratch
  0x3F0  doorbell: a store here raises irq_i[7] (MTIP) in the testbench
  0x3F4  doorbell: a store here clears irq_i[7]
  0x3F8  doorbell: a store here raises debug_req_i (--debug variant)
  0x600  dm_halt_addr_i: debug handler (--debug variant)

Usage: assemble.py [--debug] <prog.hex> <prog.lst>
"""

import sys

MEM_WORDS = 512


def r(rd, rs1, rs2, funct3, funct7, opcode=0b0110011):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def i(rd, rs1, imm, funct3, opcode=0b0010011):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s(rs1, rs2, imm, funct3, opcode=0b0100011):
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
        (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def b(rs1, rs2, imm, funct3, opcode=0b1100011):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | \
        (rs1 << 15) | (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | \
        (((imm >> 11) & 1) << 7) | opcode


def jal(rd, off):
    off &= 0x1FFFFF
    return (((off >> 20) & 1) << 31) | (((off >> 1) & 0x3FF) << 21) | \
        (((off >> 11) & 1) << 20) | (((off >> 12) & 0xFF) << 12) | (rd << 7) | 0b1101111


def addi(rd, rs1, imm): return i(rd, rs1, imm, 0b000)
def add(rd, rs1, rs2): return r(rd, rs1, rs2, 0b000, 0b0000000)
def sub(rd, rs1, rs2): return r(rd, rs1, rs2, 0b000, 0b0100000)
def xor_(rd, rs1, rs2): return r(rd, rs1, rs2, 0b100, 0b0000000)
def sw(rs2, imm, rs1): return s(rs1, rs2, imm, 0b010)
def sh(rs2, imm, rs1): return s(rs1, rs2, imm, 0b001)
def sb(rs2, imm, rs1): return s(rs1, rs2, imm, 0b000)
def lw(rd, imm, rs1): return i(rd, rs1, imm, 0b010, 0b0000011)
def lhu(rd, imm, rs1): return i(rd, rs1, imm, 0b101, 0b0000011)
def lbu(rd, imm, rs1): return i(rd, rs1, imm, 0b100, 0b0000011)
def beq(rs1, rs2, imm): return b(rs1, rs2, imm, 0b000)
def bne(rs1, rs2, imm): return b(rs1, rs2, imm, 0b001)
def csrrw(rd, csr, rs1): return i(rd, rs1, csr, 0b001, 0b1110011)
def csrrs(rd, csr, rs1): return i(rd, rs1, csr, 0b010, 0b1110011)
def csrrsi(rd, csr, uimm): return i(rd, uimm, csr, 0b110, 0b1110011)


ECALL = 0x00000073
MRET = 0x30200073
WFI = 0x10500073
NOP = addi(0, 0, 0)

CSR_MSTATUS = 0x300
CSR_MIE = 0x304
CSR_MEPC = 0x341
CSR_MCAUSE = 0x342

# (byte address, word, assembly text)
PROG = [
    # vector table
    (0x000, jal(0, 0x100 - 0x000), 'jal x0, 0x100   (exception vector)'),
    (0x01C, jal(0, 0x140 - 0x01C), 'jal x0, 0x140   (MTI vector, mtvec+4*7)'),
    # main
    (0x080, addi(1, 0, 0x123), 'addi x1, x0, 0x123   (boot)'),
    (0x084, addi(2, 0, 0x456), 'addi x2, x0, 0x456'),
    (0x088, add(3, 1, 2), 'add x3, x1, x2'),
    (0x08C, sub(4, 2, 1), 'sub x4, x2, x1'),
    (0x090, addi(5, 0, 0x200), 'addi x5, x0, 0x200'),
    (0x094, sw(3, 0, 5), 'sw x3, 0(x5)'),
    (0x098, lw(6, 0, 5), 'lw x6, 0(x5)'),
    (0x09C, beq(3, 6, 8), 'beq x3, x6, +8   (taken)'),
    (0x0A0, addi(7, 0, -1), 'addi x7, x0, -1  (never retired)'),
    (0x0A4, addi(8, 0, 0x5A), 'addi x8, x0, 0x5a'),
    (0x0A8, sb(8, 4, 5), 'sb x8, 4(x5)'),
    (0x0AC, lbu(9, 4, 5), 'lbu x9, 4(x5)'),
    (0x0B0, sh(3, 8, 5), 'sh x3, 8(x5)'),
    (0x0B4, lhu(10, 8, 5), 'lhu x10, 8(x5)'),
    (0x0B8, xor_(11, 3, 4), 'xor x11, x3, x4'),
    (0x0BC, addi(15, 0, 3), 'addi x15, x0, 3'),
    (0x0C0, addi(15, 15, -1), 'addi x15, x15, -1   (loop:)'),
    (0x0C4, bne(15, 0, -4), 'bne x15, x0, -4   (backward, taken 2x)'),
    (0x0C8, beq(15, 1, 8), 'beq x15, x1, +8   (not taken)'),
    (0x0CC, ECALL, 'ecall   (traps to 0x000)'),
    # resume after ecall handler (mepc + 4)
    (0x0D0, addi(16, 0, 0x80), 'addi x16, x0, 0x80   (MTIE)'),
    (0x0D4, csrrs(0, CSR_MIE, 16), 'csrrs x0, mie, x16'),
    (0x0D8, csrrsi(0, CSR_MSTATUS, 8), 'csrrsi x0, mstatus, 8   (MIE)'),
    (0x0DC, addi(17, 0, 1), 'addi x17, x0, 1'),
    (0x0E0, sw(17, 0x1F0, 5), 'sw x17, 0x1f0(x5)   (raise irq_i[7])'),
    (0x0E4, NOP, 'nop'),
    (0x0E8, NOP, 'nop'),
    (0x0EC, NOP, 'nop'),
    (0x0F0, NOP, 'nop'),
    (0x0F4, addi(18, 0, 0x77), 'addi x18, x0, 0x77   (after irq return)'),
    (0x0F8, WFI, 'wfi   (sleep; capture ends)'),
    (0x0FC, jal(0, 0), 'jal x0, 0   (spin, should not be reached)'),
    # exception handler
    (0x100, csrrs(12, CSR_MCAUSE, 0), 'csrrs x12, mcause, x0'),
    (0x104, csrrs(13, CSR_MEPC, 0), 'csrrs x13, mepc, x0'),
    (0x108, addi(13, 13, 4), 'addi x13, x13, 4'),
    (0x10C, csrrw(0, CSR_MEPC, 13), 'csrrw x0, mepc, x13'),
    (0x110, addi(14, 0, 42), 'addi x14, x0, 42'),
    (0x114, MRET, 'mret'),
    # interrupt handler
    (0x140, csrrs(19, CSR_MCAUSE, 0), 'csrrs x19, mcause, x0'),
    (0x144, csrrs(20, CSR_MEPC, 0), 'csrrs x20, mepc, x0'),
    (0x148, sw(0, 0x1F4, 5), 'sw x0, 0x1f4(x5)   (clear irq_i[7])'),
    (0x14C, lw(21, 0x1F4, 5), 'lw x21, 0x1f4(x5)   (order after the clear)'),
    (0x150, MRET, 'mret'),
]


DRET = 0x7B200073

# Variant (--debug): exercise external debug entry instead of the marker addi.
# Store to 0x3F8 raises debug_req_i in the testbench (held until
# debug_halted_o); dm_halt_addr_i is 0x600 in the testbench.
DEBUG_PATCH = [
    (0x0F4, sw(17, 0x1F8, 5), 'sw x17, 0x1f8(x5)   (raise debug_req_i)'),
    (0x600, addi(22, 0, 0x55), 'addi x22, x0, 0x55   (debug handler)'),
    # Zcmp multi-memop: cm.push {ra, s0}, -16 (two stores -> NMEM slots 0,1)
    (0x0E8, addi(2, 0, 0x380), 'addi x2, x0, 0x380   (sp for cm.push)'),
    (0x0EC, 0x0001B852, 'cm.push {ra,s0},-16 ; c.nop   (two 16-bit insns)'),
    (0x604, DRET, 'dret'),
]


def main():
    global PROG
    if '--debug' in sys.argv:
        sys.argv.remove('--debug')
        patched = dict((a, (a, w, t)) for a, w, t in PROG)
        for a, w, t in DEBUG_PATCH:
            patched[a] = (a, w, t)
        PROG = [patched[a] for a in sorted(patched)]
    mem = [0x00000000] * MEM_WORDS
    for addr, word, _text in PROG:
        mem[addr >> 2] = word
    out = sys.argv[1] if len(sys.argv) > 1 else 'prog.hex'
    with open(out, 'w') as fh:
        for word in mem:
            fh.write('%08x\n' % word)
    listing = sys.argv[2] if len(sys.argv) > 2 else 'prog.lst'
    with open(listing, 'w') as fh:
        fh.write('# addr      word        assembly\n')
        for addr, word, text in PROG:
            fh.write('0x%03x   0x%08x   %s\n' % (addr, word, text))
    print('wrote %s (%d words) and %s' % (out, MEM_WORDS, listing))


if __name__ == '__main__':
    main()
