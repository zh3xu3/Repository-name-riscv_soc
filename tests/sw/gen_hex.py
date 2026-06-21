#!/usr/bin/env python3
"""Generate inst_mem.hex for RV32IM test program with timer interrupt.

Test program verifies:
  RV32I: x1=42, x2=58, x3=100, x4=58, x5=0x0F, x6=0x0F, x7=0xFFFFFFF0,
         x8=0x12345000, x15=3
  RV32M: x9=5800, x10=0, x11=1, x12=42, x13=1, x14=42
  Timer IRQ: x15=1 (incremented by trap handler on timer interrupt)
"""


def imm_to_bits(imm, bits):
    """Convert signed integer to two's complement bit string."""
    if imm < 0:
        imm = (1 << bits) + imm
    return format(imm & ((1 << bits) - 1), f"0{bits}b")


def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return f"{funct7}{rs2:05b}{rs1:05b}{funct3}{rd:05b}{opcode}"


def encode_i(imm12, rs1, funct3, rd, opcode):
    return f"{imm_to_bits(imm12, 12)}{rs1:05b}{funct3}{rd:05b}{opcode}"


def encode_s(imm12, rs2, rs1, funct3, opcode):
    b = imm_to_bits(imm12, 12)
    return f"{b[:7]}{rs2:05b}{rs1:05b}{funct3}{b[7:]}{opcode}"


def encode_b(imm13, rs2, rs1, funct3, opcode):
    """B-type: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode"""
    b = imm_to_bits(imm13, 13)
    return f"{b[0]}{b[2:8]}{rs2:05b}{rs1:05b}{funct3}{b[8:12]}{b[1]}{opcode}"


def encode_u(imm20, rd, opcode):
    """U-type: imm20 is the upper 20-bit immediate (result = imm20 << 12)."""
    return f"{format(imm20 & 0xFFFFF, '020b')}{rd:05b}{opcode}"


def encode_j(imm21, rd, opcode):
    """J-type: imm[20|10:1|11|19:12] rd opcode"""
    b = imm_to_bits(imm21, 21)
    return f"{b[0]}{b[10:20]}{b[9]}{b[1:9]}{rd:05b}{opcode}"


def encode_csr(csr_addr, rs1, funct3, rd):
    """CSR instruction (I-type): csr_addr[11:0] rs1 funct3 rd 1110011"""
    return encode_i(csr_addr, rs1, funct3, rd, OP_SYS)


def encode_mret():
    """MRET: 001100000010 00000 000 00000 1110011"""
    return "001100000010" + "00000" + "000" + "00000" + OP_SYS


def bin_to_hex(binstr):
    return format(int(binstr, 2), "08x")


# Opcodes
OP_R    = "0110011"
OP_I    = "0010011"
OP_LOAD = "0000011"
OP_S    = "0100011"
OP_B    = "1100011"
OP_LUI  = "0110111"
OP_JAL  = "1101111"
OP_SYS  = "1110011"

# funct3
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
F3_SW      = "010"
F3_LW      = "010"
F3_CSRRW   = "001"
F3_CSRRS   = "010"
F3_MRET    = "000"

# Program: list of (hex_addr, instruction_bin)
prog = [
    # === I-type arithmetic ===
    # 0x00: addi x1, x0, 42
    (0x00, encode_i(42, 0, F3_ADD_SUB, 1, OP_I)),
    # 0x04: addi x2, x0, 58
    (0x04, encode_i(58, 0, F3_ADD_SUB, 2, OP_I)),
    # 0x08: addi x5, x0, 255
    (0x08, encode_i(255, 0, F3_ADD_SUB, 5, OP_I)),
    # 0x0C: addi x6, x0, 15
    (0x0C, encode_i(15, 0, F3_ADD_SUB, 6, OP_I)),

    # === R-type arithmetic ===
    # 0x10: add x3, x1, x2
    (0x10, encode_r("0000000", 2, 1, F3_ADD_SUB, 3, OP_R)),
    # 0x14: sub x4, x3, x1
    (0x14, encode_r("0100000", 1, 3, F3_ADD_SUB, 4, OP_R)),
    # 0x18: and x5, x5, x6
    (0x18, encode_r("0000000", 6, 5, F3_AND, 5, OP_R)),
    # 0x1C: or x6, x5, x6
    (0x1C, encode_r("0000000", 6, 5, F3_OR, 6, OP_R)),

    # === More R-type ===
    # 0x20: addi x7, x0, -1  (0xFFFFFFFF)
    (0x20, encode_i(-1, 0, F3_ADD_SUB, 7, OP_I)),
    # 0x24: xor x7, x7, x6
    (0x24, encode_r("0000000", 6, 7, F3_XOR, 7, OP_R)),
    # 0x28: addi x8, x0, 1
    (0x28, encode_i(1, 0, F3_ADD_SUB, 8, OP_I)),
    # 0x2C: sll x8, x8, x6  (1 << 15 = 0x8000)
    (0x2C, encode_r("0000000", 6, 8, F3_SLL, 8, OP_R)),

    # === LUI + memory ===
    # 0x30: lui x8, 0x12345
    (0x30, encode_u(0x12345, 8, OP_LUI)),
    # 0x34: addi x12, x0, 64
    (0x34, encode_i(64, 0, F3_ADD_SUB, 12, OP_I)),
    # 0x38: sw x13, 0(x12)  -- store x13 to MEM[64]
    # First load x13 with 0xDEADBEEF via LUI+ADDI:
    # 0x38: lui x13, 0xDEADC (need +1 because ADDI 0xBEEF sign-extends to -273)
    (0x38, encode_u(0xDEADC, 13, OP_LUI)),
    # 0x3C: addi x13, x13, 0xEEF
    (0x3C, encode_i(0xEEF, 13, F3_ADD_SUB, 13, OP_I)),
    # 0x40: sw x13, 0(x12)
    (0x40, encode_s(0, 13, 12, F3_SW, OP_S)),
    # 0x44: lw x14, 0(x12)
    (0x44, encode_i(0, 12, F3_LW, 14, OP_LOAD)),

    # === BEQ test ===
    # 0x48: addi x15, x0, 0
    (0x48, encode_i(0, 0, F3_ADD_SUB, 15, OP_I)),
    # 0x4C: beq x1, x1, +8  (branch to 0x54, skip next)
    (0x4C, encode_b(8, 1, 1, F3_BEQ, OP_B)),
    # 0x50: addi x15, x0, 99  (SKIPPED)
    (0x50, encode_i(99, 0, F3_ADD_SUB, 15, OP_I)),
    # 0x54: addi x15, x0, 1
    (0x54, encode_i(1, 0, F3_ADD_SUB, 15, OP_I)),

    # === BNE test ===
    # 0x58: bne x1, x2, +8  (branch to 0x60, skip next)
    (0x58, encode_b(8, 2, 1, F3_BNE, OP_B)),
    # 0x5C: addi x15, x0, 99  (SKIPPED)
    (0x5C, encode_i(99, 0, F3_ADD_SUB, 15, OP_I)),
    # 0x60: addi x15, x0, 2
    (0x60, encode_i(2, 0, F3_ADD_SUB, 15, OP_I)),

    # === JAL test ===
    # 0x64: jal x1, +8  (jump to 0x6C, x1=0x68)
    (0x64, encode_j(8, 1, OP_JAL)),
    # 0x68: addi x15, x0, 99  (SKIPPED)
    (0x68, encode_i(99, 0, F3_ADD_SUB, 15, OP_I)),
    # 0x6C: addi x15, x0, 3
    (0x6C, encode_i(3, 0, F3_ADD_SUB, 15, OP_I)),

    # === halt (RV32I done, jump to M-ext tests) ===
    # 0x70: jal x0, +16  (jump to 0x80 for M-ext tests)
    (0x70, encode_j(16, 0, OP_JAL)),

    # === M-extension tests (funct7=0000001) ===
    # Note: x1 was overwritten by JAL (x1=0x68), so use x2(58) and x3(100).
    # 0x74: NOP (filler)
    (0x74, encode_i(0, 0, F3_ADD_SUB, 0, OP_I)),
    # 0x78: NOP
    (0x78, encode_i(0, 0, F3_ADD_SUB, 0, OP_I)),
    # 0x7C: NOP
    (0x7C, encode_i(0, 0, F3_ADD_SUB, 0, OP_I)),
    # 0x80: mul x9, x2, x3  (58 * 100 = 5800)
    (0x80, encode_r("0000001", 3, 2, "000", 9, OP_R)),
    # 0x84: mulh x10, x2, x3  (58*100)[63:32] = 0
    (0x84, encode_r("0000001", 3, 2, "001", 10, OP_R)),
    # 0x88: div x11, x3, x2  (100 / 58 = 1)
    (0x88, encode_r("0000001", 2, 3, "100", 11, OP_R)),
    # 0x8C: rem x12, x3, x2  (100 % 58 = 42)
    (0x8C, encode_r("0000001", 2, 3, "110", 12, OP_R)),
    # 0x90: divu x13, x3, x2  (100 / 58 = 1)
    (0x90, encode_r("0000001", 2, 3, "101", 13, OP_R)),
    # 0x94: remu x14, x3, x2  (100 % 58 = 42)
    (0x94, encode_r("0000001", 2, 3, "111", 14, OP_R)),

    # === Jump from M-ext to interrupt test setup ===
    # 0x98: jal x0, +16  (jump to 0xA8, skip trap handler)
    (0x98, encode_j(16, 0, OP_JAL)),

    # === Interrupt test setup (0xA8-0xCC) ===
    # 0xA8: addi x15, x0, 0  (clear x15)
    (0xA8, encode_i(0, 0, F3_ADD_SUB, 15, OP_I)),
    # 0xAC: addi x16, x0, 0xD8  (x16 = trap handler address)
    (0xAC, encode_i(0xD8, 16, F3_ADD_SUB, 16, OP_I)),
    # 0xB0: csrrw x0, mtvec, x16  (set mtvec = 0xD8)
    (0xB0, encode_csr(0x305, 16, F3_CSRRW, 0)),
    # 0xB4: addi x16, x0, 50  (mtimecmp_lo = 50, mtime will reach it soon)
    (0xB4, encode_i(50, 0, F3_ADD_SUB, 16, OP_I)),
    # 0xB8: csrrw x0, mtimecmp_lo(0xB02), x16
    (0xB8, encode_csr(0xB02, 16, F3_CSRRW, 0)),
    # 0xBC: csrrw x0, mtimecmp_hi(0xB03), x0  (mtimecmp_hi = 0)
    (0xBC, encode_csr(0xB03, 0, F3_CSRRW, 0)),
    # 0xC0: addi x16, x0, 0x80  (MTIE bit = bit 7)
    (0xC0, encode_i(0x80, 0, F3_ADD_SUB, 16, OP_I)),
    # 0xC4: csrrw x0, mie, x16  (enable timer interrupt in mie)
    (0xC4, encode_csr(0x304, 16, F3_CSRRW, 0)),
    # 0xC8: addi x16, x0, 8  (MIE bit = bit 3 in mstatus)
    (0xC8, encode_i(8, 0, F3_ADD_SUB, 16, OP_I)),
    # 0xCC: csrrw x0, mstatus, x16  (enable global interrupt)
    (0xCC, encode_csr(0x300, 16, F3_CSRRW, 0)),
    # 0xD0: wait loop (timer interrupt fires and jumps to 0xD8)
    #   jal x0, 0  (infinite loop, interrupt breaks out via mret)
    (0xD0, encode_j(0, 0, OP_JAL)),

    # === Trap handler (mtvec = 0xD8) ===
    # Disable mie.MTIE first to prevent re-trigger when MRET restores MIE.
    # 0xD8: addi x17, x0, 0  (x17 = 0)
    (0xD8, encode_i(0, 0, F3_ADD_SUB, 17, OP_I)),
    # 0xDC: csrrw x0, mie(0x304), x17  (mie = 0, disable all interrupts)
    (0xDC, encode_csr(0x304, 17, F3_CSRRW, 0)),
    # 0xE0: addi x17, x0, -1  (x17 = 0xFFFFFFFF)
    (0xE0, encode_i(-1, 0, F3_ADD_SUB, 17, OP_I)),
    # 0xE4: csrrw x0, mtimecmp_lo(0xB02), x17  (mtimecmp_lo = max, prevent re-trigger)
    (0xE4, encode_csr(0xB02, 17, F3_CSRRW, 0)),
    # 0xE8: addi x15, x15, 1  (increment x15 to verify interrupt fired)
    (0xE8, encode_i(1, 15, F3_ADD_SUB, 15, OP_I)),
    # 0xEC: mret  (return from trap → back to 0xD0 wait loop)
    (0xEC, encode_mret()),
]

# Generate hex file using addr field to place instructions at correct positions
# $readmemh reads hex values one per line, each = 32-bit word
NOP = "00000013"  # addi x0, x0, 0

# Find max address to determine file size
max_addr = max(addr for addr, _ in prog)
num_words = max(max_addr // 4 + 1, 256)  # at least 256 words

# Initialize with NOPs
hex_lines = [NOP] * num_words

# Place instructions at their specified addresses
for addr, binstr in prog:
    assert addr % 4 == 0, f"Address {addr:#x} not word-aligned"
    hex_lines[addr // 4] = bin_to_hex(binstr)

with open("inst_mem.hex", "w") as f:
    for h in hex_lines:
        f.write(h + "\n")

print(f"Generated {len(prog)} instructions")
print("inst_mem.hex written")

# Print expected register values
print("\nExpected results:")
print("  x1  = 0x{:08x} (JAL return addr)".format(0x68))
print("  x2  = 0x{:08x} (58)".format(58))
print("  x3  = 0x{:08x} (100)".format(100))
print("  x4  = 0x{:08x} (58)".format(58))
print("  x5  = 0x{:08x}".format(0xFF & 0x0F))
print("  x6  = 0x{:08x}".format(0x0F | 0x0F))
print("  x7  = 0x{:08x}".format(0xFFFFFFFF ^ 0x0F))
print("  x8  = 0x{:08x}".format(0x12345 << 12))
print("  x12 = 0x{:08x} (100 % 58, REM)".format(100 % 58))
print("  x13 = 0x{:08x} (100 / 58, DIVU)".format(100 // 58))
print("  x14 = 0x{:08x} (100 % 58, REMU)".format(100 % 58))
print("  x15 = 1 (timer interrupt handler incremented from 0)")
