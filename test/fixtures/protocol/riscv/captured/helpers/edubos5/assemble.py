#!/usr/bin/env python3
# Copyright (c) WaveCrux contributors.
# SPDX-License-Identifier: 0BSD
"""Hand-assemble the tiny RV32I program used by tb_edubos5_rvfi.sv.

No RISC-V toolchain is required: this script encodes the eight RV32I
instructions the capture needs and writes a $readmemh image for the
instruction memory, plus a listing.

eduBOS5 has separate instruction and data memories (as in its own
formal/rvfi_wrapper.sv), so the program and its data never share words:
  IMEM 0x000  reset vector (eduBOS5 resets its PC to 0)
  DMEM 0x100  data scratch
"""

import sys

MEM_WORDS = 256  # 1 KiB of instruction memory


def r(rd, rs1, rs2, funct3, funct7, opcode=0b0110011):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def i(rd, rs1, imm, funct3, opcode=0b0010011):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s(rs1, rs2, imm, funct3, opcode=0b0100011):
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
        (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def j(rd, imm, opcode=0b1101111):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
        (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | opcode


def addi(rd, rs1, imm):
    return i(rd, rs1, imm, 0b000)


def add(rd, rs1, rs2):
    return r(rd, rs1, rs2, 0b000, 0b0000000)


def sw(rs2, imm, rs1):
    return s(rs1, rs2, imm, 0b010)


def sb(rs2, imm, rs1):
    return s(rs1, rs2, imm, 0b000)


def lw(rd, imm, rs1):
    return i(rd, rs1, imm, 0b010, 0b0000011)


def jal(rd, imm):
    return j(rd, imm)


# (byte address, word, assembly text)
PROGRAM = [
    (0x000, addi(1, 0, 0), 'addi x1, x0, 0'),
    (0x004, addi(3, 0, 0x100), 'addi x3, x0, 0x100'),
    (0x008, addi(1, 1, 1), 'addi x1, x1, 1     (loop:)'),
    (0x00C, sw(1, 0, 3), 'sw x1, 0(x3)'),
    (0x010, lw(2, 0, 3), 'lw x2, 0(x3)'),
    (0x014, add(4, 1, 2), 'add x4, x1, x2'),
    (0x018, sb(4, 5, 3), 'sb x4, 5(x3)'),
    (0x01C, jal(0, 0x008 - 0x01C), 'jal x0, -20        (to loop:)'),
]


def main():
    mem = [0x00000000] * MEM_WORDS
    for addr, word, _text in PROGRAM:
        mem[addr >> 2] = word

    out = sys.argv[1] if len(sys.argv) > 1 else 'prog.hex'
    with open(out, 'w') as fh:
        for word in mem:
            fh.write('%08x\n' % word)

    listing = sys.argv[2] if len(sys.argv) > 2 else 'prog.lst'
    with open(listing, 'w') as fh:
        fh.write('# addr      word        assembly\n')
        for addr, word, text in PROGRAM:
            fh.write('0x%03x   0x%08x   %s\n' % (addr, word, text))

    print('wrote %s (%d words) and %s' % (out, MEM_WORDS, listing))


if __name__ == '__main__':
    main()
