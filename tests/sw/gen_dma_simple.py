#!/usr/bin/env python3
"""Simple DMA test - just test DMA mem2mem transfer"""

def imm_to_bits(imm, bits):
    if imm < 0:
        imm = (1 << bits) + imm
    return format(imm & ((1 << bits) - 1), f"0{bits}b")

def encode_i(imm12, rs1, funct3, rd, opcode):
    return f"{imm_to_bits(imm12, 12)}{rs1:05b}{funct3}{rd:05b}{opcode}"

def encode_s(imm12, rs2, rs1, funct3, opcode):
    b = imm_to_bits(imm12, 12)
    return f"{b[:7]}{rs2:05b}{rs1:05b}{funct3}{b[7:]}{opcode}"

def encode_u(imm20, rd, opcode):
    return f"{format(imm20 & 0xFFFFF, '020b')}{rd:05b}{opcode}"

def bin_to_hex(binstr):
    return format(int(binstr, 2), "08x")

OP_I    = "0010011"
OP_LOAD = "0000011"
OP_S    = "0100011"
OP_LUI  = "0110111"
OP_SYS  = "1110011"

F3_ADD_SUB = "000"
F3_LW      = "010"
F3_SW      = "010"

NOP     = "00000000000000000000000000010011"
EBREAK  = "00000000000100000000000001110011"

prog = []

# x28 = DMEM base = 0x1000
# x29 = DMA base  = 0x8000
# x11 = GPIO base = 0x3000
prog.append((0x000, encode_u(0x1, 28, OP_LUI)))      # x28 = 0x1000
prog.append((0x004, encode_u(0x8, 29, OP_LUI)))      # x29 = 0x8000
prog.append((0x008, encode_u(0x3, 11, OP_LUI)))      # x11 = 0x3000

# Store test data: DMEM[0x1100..0x110C] = 0xDEADBEEF
prog.append((0x00C, encode_i(0xDE, 0, F3_ADD_SUB, 1, OP_I)))  # x1 = 0xDE
prog.append((0x010, encode_s(0x100, 1, 28, F3_SW, OP_S)))     # [0x1100] = 0xDE
prog.append((0x014, encode_i(0xAD, 0, F3_ADD_SUB, 1, OP_I)))  # x1 = 0xAD
prog.append((0x018, encode_s(0x104, 1, 28, F3_SW, OP_S)))     # [0x1104] = 0xAD
prog.append((0x01C, encode_i(0xBE, 0, F3_ADD_SUB, 1, OP_I)))  # x1 = 0xBE
prog.append((0x020, encode_s(0x108, 1, 28, F3_SW, OP_S)))     # [0x1108] = 0xBE
prog.append((0x024, encode_i(0xEF, 0, F3_ADD_SUB, 1, OP_I)))  # x1 = 0xEF
prog.append((0x028, encode_s(0x10C, 1, 28, F3_SW, OP_S)))     # [0x110C] = 0xEF

# Configure DMA
prog.append((0x02C, encode_u(0x1, 1, OP_LUI)))                # x1 = 0x1000
prog.append((0x030, encode_i(0x100, 1, F3_ADD_SUB, 1, OP_I))) # x1 = 0x1100
prog.append((0x034, encode_s(0x04, 1, 29, F3_SW, OP_S)))      # DMA_SRC = 0x1100

prog.append((0x038, encode_u(0x1, 1, OP_LUI)))                # x1 = 0x1000
prog.append((0x03C, encode_i(0x200, 1, F3_ADD_SUB, 1, OP_I))) # x1 = 0x1200
prog.append((0x040, encode_s(0x08, 1, 29, F3_SW, OP_S)))      # DMA_DST = 0x1200

prog.append((0x044, encode_i(16, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 16
prog.append((0x048, encode_s(0x0C, 1, 29, F3_SW, OP_S)))      # DMA_LEN = 16

# Start DMA
prog.append((0x04C, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))     # x1 = 1
prog.append((0x050, encode_s(0x00, 1, 29, F3_SW, OP_S)))      # DMA_CTRL = 1

# Wait a few cycles
prog.append((0x054, NOP))
prog.append((0x058, NOP))
prog.append((0x05C, NOP))
prog.append((0x060, NOP))

# Read DMA STATUS
prog.append((0x064, encode_i(0x10, 29, F3_LW, 1, OP_LOAD)))   # x1 = DMA_STATUS

# Write result to GPIO
prog.append((0x068, encode_s(0, 1, 11, F3_SW, OP_S)))         # GPIO[0] = STATUS

# EBREAK
prog.append((0x06C, EBREAK))

# Generate hex file
hex_lines = [NOP] * 64
for addr, binstr in prog:
    hex_lines[addr // 4] = bin_to_hex(binstr)

with open("inst_mem.hex", "w") as f:
    for h in hex_lines:
        f.write(h + "\n")

print(f"Generated {len(prog)} instructions")
print("inst_mem.hex written")
print("Expected: GPIO[0] = DMA_STATUS (should show done=1)")
