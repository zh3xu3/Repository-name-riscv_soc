#!/usr/bin/env python3
"""RV32I ISA simulator - verify test program before running on Verilog."""

import sys
import os

# Load hex file
hex_path = os.path.join(os.path.dirname(__file__), "..", "tests", "sw", "inst_mem.hex")
if not os.path.exists(hex_path):
    # Try current directory
    hex_path = "inst_mem.hex"

with open(hex_path) as f:
    mem = [int(line.strip(), 16) for line in f if line.strip()]

regs = [0] * 32
pc = 0
max_cycles = 200

def s32(v):
    """Convert to signed 32-bit."""
    v = v & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v

def u32(v):
    return v & 0xFFFFFFFF

for cycle in range(max_cycles):
    if pc >= len(mem) * 4:
        print(f"PC out of range: 0x{pc:08x}")
        break

    inst = mem[pc >> 2]
    opcode = inst & 0x7F
    rd     = (inst >> 7) & 0x1F
    funct3 = (inst >> 12) & 0x7
    rs1    = (inst >> 15) & 0x1F
    rs2    = (inst >> 20) & 0x1F
    funct7 = (inst >> 25) & 0x7F

    next_pc = pc + 4

    if opcode == 0x13:  # I-type ALU
        imm12 = (inst >> 20) & 0xFFF
        if imm12 & 0x800:
            imm = s32(imm12 | 0xFFFFF000)
        else:
            imm = imm12
        a = regs[rs1]
        b = imm
        if funct3 == 0: result = a + b       # ADDI
        elif funct3 == 1: result = a << (b & 0x1F)  # SLLI
        elif funct3 == 2: result = 1 if s32(a) < s32(b) else 0  # SLTI
        elif funct3 == 3: result = 1 if u32(a) < u32(b) else 0  # SLTIU
        elif funct3 == 4: result = a ^ b      # XORI
        elif funct3 == 5:
            if funct7 & 0x20: result = s32(a) >> (b & 0x1F)  # SRAI
            else: result = u32(a) >> (b & 0x1F)               # SRLI
        elif funct3 == 6: result = a | b      # ORI
        elif funct3 == 7: result = a & b      # ANDI
        else: result = 0
        regs[rd] = u32(result)

    elif opcode == 0x33:  # R-type ALU
        a = regs[rs1]
        b = regs[rs2]
        if funct3 == 0:
            if funct7 & 0x20: result = a - b  # SUB
            else: result = a + b              # ADD
        elif funct3 == 1: result = a << (b & 0x1F)  # SLL
        elif funct3 == 2: result = 1 if s32(a) < s32(b) else 0  # SLT
        elif funct3 == 3: result = 1 if u32(a) < u32(b) else 0  # SLTU
        elif funct3 == 4: result = a ^ b      # XOR
        elif funct3 == 5:
            if funct7 & 0x20: result = s32(a) >> (b & 0x1F)  # SRA
            else: result = u32(a) >> (b & 0x1F)               # SRL
        elif funct3 == 6: result = a | b      # OR
        elif funct3 == 7: result = a & b      # AND
        else: result = 0
        regs[rd] = u32(result)

    elif opcode == 0x03:  # Load
        imm12 = (inst >> 20) & 0xFFF
        if imm12 & 0x800:
            imm = s32(imm12 | 0xFFFFF000)
        else:
            imm = imm12
        addr = u32(regs[rs1] + imm)
        word_idx = addr >> 2
        if word_idx < len(mem):
            word = mem[word_idx]
        else:
            word = 0
        byte_off = addr & 3
        if funct3 == 0:  # LB
            val = (word >> (byte_off * 8)) & 0xFF
            if val & 0x80: val |= 0xFFFFFF00
        elif funct3 == 1:  # LH
            val = (word >> (byte_off * 8)) & 0xFFFF
            if val & 0x8000: val |= 0xFFFF0000
        else:  # LW
            val = word
        regs[rd] = u32(val)

    elif opcode == 0x23:  # Store
        imm11_5 = (inst >> 25) & 0x7F
        imm4_0  = (inst >> 7) & 0x1F
        imm = (imm11_5 << 5) | imm4_0
        if imm & 0x800: imm |= 0xFFFFF000
        imm = s32(imm)
        addr = u32(regs[rs1] + imm)
        word_idx = addr >> 2
        byte_off = addr & 3
        if word_idx < len(mem):
            if funct3 == 0:  # SB
                mem[word_idx] = (mem[word_idx] & ~(0xFF << (byte_off*8))) | ((regs[rs2] & 0xFF) << (byte_off*8))
            elif funct3 == 1:  # SH
                mem[word_idx] = (mem[word_idx] & ~(0xFFFF << (byte_off*8))) | ((regs[rs2] & 0xFFFF) << (byte_off*8))
            else:  # SW
                mem[word_idx] = regs[rs2] & 0xFFFFFFFF

    elif opcode == 0x63:  # Branch
        imm12   = (inst >> 31) & 1
        imm10_5 = (inst >> 25) & 0x3F
        imm4_1  = (inst >> 8) & 0xF
        imm11   = (inst >> 7) & 1
        imm = (imm12 << 12) | (imm11 << 11) | (imm10_5 << 5) | (imm4_1 << 1)
        if imm & 0x1000: imm |= 0xFFFFE000
        imm = s32(imm)
        a = regs[rs1]
        b = regs[rs2]
        take = False
        if funct3 == 0: take = (a == b)      # BEQ
        elif funct3 == 1: take = (a != b)    # BNE
        elif funct3 == 4: take = (s32(a) < s32(b))  # BLT
        elif funct3 == 5: take = (s32(a) >= s32(b)) # BGE
        elif funct3 == 6: take = (u32(a) < u32(b))  # BLTU
        elif funct3 == 7: take = (u32(a) >= u32(b)) # BGEU
        if take:
            next_pc = u32(pc + imm)

    elif opcode == 0x6F:  # JAL
        imm20    = (inst >> 31) & 1
        imm10_1  = (inst >> 21) & 0x3FF
        imm11    = (inst >> 20) & 1
        imm19_12 = (inst >> 12) & 0xFF
        imm = (imm20 << 20) | (imm19_12 << 12) | (imm11 << 11) | (imm10_1 << 1)
        if imm & 0x100000: imm |= 0xFFE00000
        imm = s32(imm)
        regs[rd] = u32(pc + 4)
        next_pc = u32(pc + imm)

    elif opcode == 0x37:  # LUI
        imm = inst & 0xFFFFF000  # upper 20 bits << 12
        regs[rd] = u32(imm)

    elif opcode == 0x17:  # AUIPC
        imm = inst & 0xFFFFF000
        regs[rd] = u32(pc + imm)

    elif opcode == 0x17:  # AUIPC
        imm = inst & 0xFFFFF000
        regs[rd] = u32(pc + imm)

    else:
        print(f"Unknown opcode: 0x{opcode:02x} at PC=0x{pc:08x}")

    regs[0] = 0  # x0 always 0
    pc = next_pc

    # Check halt
    if pc == mem[pc >> 2] and (mem[pc >> 2] & 0x7F) == 0x6F and (mem[pc >> 2] & 0x7C) == 0:
        # JAL x0, 0 = halt
        break

print("===== Simulation Results =====")
print(f"Stopped at PC = 0x{pc:08x} after {cycle+1} cycles")
print()
print("Register file:")
for i in range(16):
    print(f"  x{i:2d} = 0x{regs[i]:08x}")

print()
print("===== Verification =====")
expected = {
    1:  0x00000068,  # JAL return addr (PC+4 at 0x64)
    2:  0x0000003a,  # 58
    3:  0x00000064,  # 100
    4:  0x0000003a,  # 58
    5:  0x0000000f,  # AND
    6:  0x0000000f,  # OR
    7:  0xfffffff0,  # XOR
    8:  0x12345000,  # LUI
    12: 0x00000040,  # 64
    13: 0xdeadbeef,  # LUI+ADDI
    14: 0xdeadbeef,  # LW
    15: 0x00000003,  # BEQ+BNE+JAL
}

passed = 0
failed = 0
for reg_num, exp in expected.items():
    actual = regs[reg_num]
    if actual == exp:
        print(f"  PASS: x{reg_num} = 0x{actual:08x}")
        passed += 1
    else:
        print(f"  FAIL: x{reg_num} = 0x{actual:08x}, expected 0x{exp:08x}")
        failed += 1

print(f"\n{passed} PASS, {failed} FAIL")
if failed == 0:
    print("ALL TESTS PASSED!")
