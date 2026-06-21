#!/usr/bin/env python3
"""Generate inst_mem.hex for extended RV32I instruction coverage.

Tests: SLL/SRL/SRA, SLT/SLTU, LB/LH/LBU/LHU/SB/SH,
       BLT/BGE/BLTU/BGEU, AUIPC, JALR
Results stored to DMEM[0x1100..0x1134] for testbench verification.
"""

def imm_to_bits(imm, bits):
    if imm < 0:
        imm = (1 << bits) + imm
    return format(imm & ((1 << bits) - 1), f"0{bits}b")

def encode_i(imm12, rs1, funct3, rd, opcode):
    return f"{imm_to_bits(imm12, 12)}{rs1:05b}{funct3}{rd:05b}{opcode}"

def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return f"{funct7}{rs2:05b}{rs1:05b}{funct3}{rd:05b}{opcode}"

def encode_s(imm12, rs2, rs1, funct3, opcode):
    b = imm_to_bits(imm12, 12)
    return f"{b[:7]}{rs2:05b}{rs1:05b}{funct3}{b[7:]}{opcode}"

def encode_b(imm13, rs2, rs1, funct3, opcode):
    b = imm_to_bits(imm13, 13)
    return f"{b[0]}{b[2:8]}{rs2:05b}{rs1:05b}{funct3}{b[8:12]}{b[1]}{opcode}"

def encode_u(imm20, rd, opcode):
    return f"{format(imm20 & 0xFFFFF, '020b')}{rd:05b}{opcode}"

def encode_j(imm21, rd, opcode):
    b = imm_to_bits(imm21, 21)
    return f"{b[0]}{b[10:20]}{b[9]}{b[1:9]}{rd:05b}{opcode}"

def bin_to_hex(binstr):
    return format(int(binstr, 2), "08x")

OP_R    = "0110011"
OP_I    = "0010011"
OP_LOAD = "0000011"
OP_S    = "0100011"
OP_B    = "1100011"
OP_LUI  = "0110111"
OP_AUIPC= "0010111"
OP_JAL  = "1101111"
OP_JALR = "1100111"

F3_ADD_SUB = "000"
F3_SLL     = "001"
F3_SLT     = "010"
F3_SLTU    = "011"
F3_XOR     = "100"
F3_SRL_SRA = "101"
F3_OR      = "110"
F3_AND     = "111"
F3_BEQ     = "000"
F3_BNE     = "001"
F3_BLT     = "100"
F3_BGE     = "101"
F3_BLTU    = "110"
F3_BGEU    = "111"
F3_LB      = "000"
F3_LH      = "001"
F3_LW      = "010"
F3_LBU     = "100"
F3_LHU     = "101"
F3_SB      = "000"
F3_SH      = "001"
F3_SW      = "010"

NOP = "00000013"

prog = []
def emit(addr, inst):
    prog.append((addr, inst))

# x15 = DMEM base (0x1000)
emit(0x00, encode_u(0x1, 15, OP_LUI))

# ============================================================
# Shift tests
# ============================================================
# x1 = 0x00000001
emit(0x04, encode_i(1, 0, F3_ADD_SUB, 1, OP_I))
# x2 = 4
emit(0x08, encode_i(4, 0, F3_ADD_SUB, 2, OP_I))
# x3 = 0x80000000 (build via LUI)
emit(0x0C, encode_u(0x80000, 3, OP_LUI))

# x4 = SLL: 1 << 4 = 16
emit(0x10, encode_r("0000000", 2, 1, F3_SLL, 4, OP_R))
# x5 = SRL: 0x80000000 >> 4 = 0x08000000
emit(0x14, encode_r("0000000", 2, 3, F3_SRL_SRA, 5, OP_R))
# x6 = SRA: 0x80000000 >>> 4 = 0xF8000000
emit(0x18, encode_r("0100000", 2, 3, F3_SRL_SRA, 6, OP_R))

# Store shift results
emit(0x1C, encode_s(0x100, 4, 15, F3_SW, OP_S))
emit(0x20, encode_s(0x104, 5, 15, F3_SW, OP_S))
emit(0x24, encode_s(0x108, 6, 15, F3_SW, OP_S))

# ============================================================
# SLT / SLTU tests
# ============================================================
# x1 = -1 (0xFFFFFFFF)
emit(0x28, encode_i(-1, 0, F3_ADD_SUB, 1, OP_I))
# x2 = 1
emit(0x2C, encode_i(1, 0, F3_ADD_SUB, 2, OP_I))
# x3 = SLT(-1, 1) = 1
emit(0x30, encode_r("0000000", 2, 1, F3_SLT, 3, OP_R))
# x4 = SLTU(-1, 1) = 0
emit(0x34, encode_r("0000000", 2, 1, F3_SLTU, 4, OP_R))

emit(0x38, encode_s(0x10C, 3, 15, F3_SW, OP_S))
emit(0x3C, encode_s(0x110, 4, 15, F3_SW, OP_S))

# ============================================================
# AUIPC test
# ============================================================
emit(0x40, encode_u(0x10000, 5, OP_AUIPC))
emit(0x44, encode_s(0x114, 5, 15, F3_SW, OP_S))

# ============================================================
# JALR test
# ============================================================
emit(0x48, encode_i(0x54, 0, F3_ADD_SUB, 6, OP_JALR))
emit(0x4C, encode_i(99, 0, F3_ADD_SUB, 6, OP_I))  # skipped
emit(0x50, encode_i(99, 0, F3_ADD_SUB, 6, OP_I))  # skipped
emit(0x54, encode_s(0x118, 6, 15, F3_SW, OP_S))

# ============================================================
# Load/Store byte/half tests
# ============================================================
# x1 = 0xDEADBEEF
# NOTE: ADDI 0xEEF has bit 11=1, so it sign-extends to 0xFFFFFEEF (= -0x111).
# To get 0xDEADBEEF, LUI must use 0xDEADC so that 0xDEADC000 + (-0x111) = 0xDEADBEEF.
emit(0x58, encode_u(0xDEADC, 1, OP_LUI))
emit(0x5C, encode_i(0xEEF, 1, F3_ADD_SUB, 1, OP_I))

# SH first (before SB) to isolate
emit(0x60, encode_s(4, 1, 15, F3_SH, OP_S))
# LH: sign-ext -> x2 = 0xFFFFBEEF
emit(0x64, encode_i(4, 15, F3_LH, 2, OP_LOAD))
# LHU: zero-ext -> x3 = 0x0000BEEF
emit(0x68, encode_i(4, 15, F3_LHU, 3, OP_LOAD))

# SB: store byte 0xEF to DMEM[0x1000]
emit(0x6C, encode_s(0, 1, 15, F3_SB, OP_S))
# LB: sign-ext -> x4 = 0xFFFFFFEF
emit(0x70, encode_i(0, 15, F3_LB, 4, OP_LOAD))
# LBU: zero-ext -> x5 = 0x000000EF
emit(0x74, encode_i(0, 15, F3_LBU, 5, OP_LOAD))

# SW: store word 0xDEADBEEF to DMEM[0x1008]
emit(0x78, encode_s(8, 1, 15, F3_SW, OP_S))
# LW: load word -> x6 = 0xDEADBEEF
emit(0x7C, encode_i(8, 15, F3_LW, 6, OP_LOAD))

# Store load results
emit(0x80, encode_s(0x11C, 2, 15, F3_SW, OP_S))
emit(0x84, encode_s(0x120, 3, 15, F3_SW, OP_S))
emit(0x88, encode_s(0x124, 4, 15, F3_SW, OP_S))
emit(0x8C, encode_s(0x128, 5, 15, F3_SW, OP_S))
emit(0x90, encode_s(0x12C, 6, 15, F3_SW, OP_S))

# ============================================================
# Branch tests
# ============================================================
emit(0x94, encode_i(5, 0, F3_ADD_SUB, 1, OP_I))
emit(0x98, encode_i(10, 0, F3_ADD_SUB, 2, OP_I))
emit(0x9C, encode_i(-1, 0, F3_ADD_SUB, 3, OP_I))
emit(0xA0, encode_i(0, 0, F3_ADD_SUB, 7, OP_I))

# BLT(5,10)=taken
emit(0xA4, encode_b(8, 2, 1, F3_BLT, OP_B))
emit(0xA8, encode_i(99, 0, F3_ADD_SUB, 7, OP_I))
emit(0xAC, encode_i(1, 0, F3_ADD_SUB, 7, OP_I))

# BGE(10,5)=taken
emit(0xB0, encode_b(8, 1, 2, F3_BGE, OP_B))
emit(0xB4, encode_i(99, 0, F3_ADD_SUB, 7, OP_I))
emit(0xB8, encode_i(2, 0, F3_ADD_SUB, 7, OP_I))

# BLTU(5,-1)=taken
emit(0xBC, encode_b(8, 3, 1, F3_BLTU, OP_B))
emit(0xC0, encode_i(99, 0, F3_ADD_SUB, 7, OP_I))
emit(0xC4, encode_i(3, 0, F3_ADD_SUB, 7, OP_I))

# BGEU(-1,5)=taken
emit(0xC8, encode_b(8, 1, 3, F3_BGEU, OP_B))
emit(0xCC, encode_i(99, 0, F3_ADD_SUB, 7, OP_I))
emit(0xD0, encode_i(4, 0, F3_ADD_SUB, 7, OP_I))

# BLT(-1,5)=taken (signed)
emit(0xD4, encode_b(8, 2, 3, F3_BLT, OP_B))
emit(0xD8, encode_i(99, 0, F3_ADD_SUB, 7, OP_I))
emit(0xDC, encode_i(5, 0, F3_ADD_SUB, 7, OP_I))

# BLTU(-1,5)=NOT taken (unsigned 0xFFFFFFFF > 5)
emit(0xE0, encode_b(8, 1, 3, F3_BLTU, OP_B))
emit(0xE4, encode_i(6, 0, F3_ADD_SUB, 7, OP_I))

# BGE(-1,5)=NOT taken (signed -1 >= 5 is false)
emit(0xE8, encode_b(8, 1, 3, F3_BGE, OP_B))
emit(0xEC, encode_i(7, 0, F3_ADD_SUB, 7, OP_I))

emit(0xF0, encode_s(0x130, 7, 15, F3_SW, OP_S))

# Halt
emit(0xF4, encode_j(0, 0, OP_JAL))

# Generate hex file
max_addr = max(addr for addr, _ in prog)
num_words = max(max_addr // 4 + 1, 128)
hex_lines = [NOP] * num_words
for addr, binstr in prog:
    assert addr % 4 == 0, f"Address {addr:#x} not word-aligned"
    hex_lines[addr // 4] = bin_to_hex(binstr)

with open("inst_mem.hex", "w") as f:
    for h in hex_lines:
        f.write(h + "\n")

print(f"Generated {len(prog)} instructions")
print("inst_mem.hex written")
