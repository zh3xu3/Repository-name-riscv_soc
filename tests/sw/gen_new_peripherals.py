#!/usr/bin/env python3
"""Generate inst_mem.hex for RISC-V SoC: DMA, I-Cache, I2C peripheral tests.

Test sections:
  1. DMA memory-to-memory transfer      (0x000-0x058)
  2. DMA transfer-complete interrupt      (0x05C-0x0E8)
  3. I-Cache enable/disable               (0x0EC-0x108)
  4. I-Cache hit/miss statistics          (0x10C-0x140)
  5. I-Cache flush                        (0x144-0x178)
  6. I2C write operation                  (0x17C-0x1B4)
  7. I2C read operation                   (0x1B8-0x1F0)
  8. I2C NACK handling                    (0x1F4-0x230)
  9. Results reporting via GPIO + EBREAK  (0x234-0x250)

Results written to GPIO (0x3000) for testbench observation:
  GPIO[0] = pass count (bits [7:0]), fail count (bits [15:8]),
            test_id of last passed test (bits [23:16])

Memory map:
  0x0000_1000  DMEM (test data)
  0x0000_3000  GPIO
  0x0000_8000  DMA
  0x0000_9000  I-Cache
  0x0000_A000  I2C
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


def encode_csr(csr_addr, rs1, funct3, rd):
    return encode_i(csr_addr, rs1, funct3, rd, OP_SYS)


def encode_mret():
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
OP_JALR = "1100111"
OP_AUIPC = "0010111"
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
F3_BLT     = "100"
F3_BGE     = "101"
F3_BLTU    = "110"
F3_BGEU    = "111"
F3_LW      = "010"
F3_SW      = "010"
F3_CSRRW   = "001"

NOP     = "00000000000000000000000000010011"   # addi x0, x0, 0
EBREAK  = "00000000000100000000000001110011"

# Register aliases (caller-save, not used for pass/fail result):
# x1-x7   = scratch / operands
# x16-x21 = scratch (not checked by TB)
# x8      = pass counter (bits 7:0)
# x9      = fail counter (bits 15:8 shifted)
# x10     = last passed test ID (bits 23:16 shifted)
# x11     = GPIO base address
# x28     = DMEM base (0x1000)
# x29     = DMA base   (0x8000)
# x30     = I-Cache base (0x9000)
# x31     = I2C base   (0xA000)

prog = []

# ================================================================
# Helper: macro-like register setup at program start
# ================================================================
# x8  = pass counter = 0
# x9  = fail counter = 0
# x10 = last passed test ID = 0
# x11 = GPIO base = 0x3000
# x28 = DMEM base = 0x1000
# x29 = DMA base  = 0x8000
# x30 = I-Cache base = 0x9000
# x31 = I2C base  = 0xA000
prog.append((0x000, encode_i(0, 0, F3_ADD_SUB, 8, OP_I)))       # x8  = 0
prog.append((0x004, encode_i(0, 0, F3_ADD_SUB, 9, OP_I)))       # x9  = 0
prog.append((0x008, encode_i(0, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 0
prog.append((0x00C, encode_u(0x3, 11, OP_LUI)))                 # x11 = 0x3000 (GPIO)
prog.append((0x010, encode_u(0x1, 28, OP_LUI)))                 # x28 = 0x1000 (DMEM)
prog.append((0x014, encode_u(0x8, 29, OP_LUI)))                 # x29 = 0x8000 (DMA)
prog.append((0x018, encode_u(0x9, 30, OP_LUI)))                 # x30 = 0x9000 (I-Cache)
prog.append((0x01C, encode_u(0xA, 31, OP_LUI)))                 # x31 = 0xA000 (I2C)

# ================================================================
# Section 1: DMA Memory-to-Memory Transfer (0x020-0x058)
# ================================================================
# Prepare source data: DMEM[0x100..0x10F] = 4 words of known patterns
#   src = 0x1100, dst = 0x1200, len = 16 bytes
prog.append((0x020, encode_i(0xDE, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0xDE
prog.append((0x024, encode_i(0xAD, 0, F3_ADD_SUB, 2, OP_I)))    # x2 = 0xAD
prog.append((0x028, encode_i(0xBE, 0, F3_ADD_SUB, 3, OP_I)))    # x3 = 0xBE
prog.append((0x02C, encode_i(0xEF, 0, F3_ADD_SUB, 4, OP_I)))    # x4 = 0xEF
# Store 4 test words into DMEM[0x1100..0x110C]
# We use x28=0x1000 as DMEM base, so offsets 0x100..0x10C
prog.append((0x030, encode_s(0x100, 1, 28, F3_SW, OP_S)))       # SW x1, 0x100(x28) → [0x1100]=0xDE
prog.append((0x034, encode_s(0x104, 2, 28, F3_SW, OP_S)))       # SW x2, 0x104(x28) → [0x1104]=0xAD
prog.append((0x038, encode_s(0x108, 3, 28, F3_SW, OP_S)))       # SW x3, 0x108(x28) → [0x1108]=0xBE
prog.append((0x03C, encode_s(0x10C, 4, 28, F3_SW, OP_S)))       # SW x4, 0x10C(x28) → [0x110C]=0xEF

# Configure DMA
# DMA_SRC_ADDR = 0x1100
prog.append((0x040, encode_u(0x1, 1, OP_LUI)))                  # x1 = 0x1000
prog.append((0x044, encode_i(0x100, 1, F3_ADD_SUB, 1, OP_I)))   # x1 = 0x1100
prog.append((0x048, encode_s(0x04, 1, 29, F3_SW, OP_S)))        # DMA_SRC_ADDR = 0x1100

# DMA_DST_ADDR = 0x1200
prog.append((0x04C, encode_i(0x200, 0, F3_ADD_SUB, 1, OP_I)))   # x1 = 0x200
prog.append((0x050, encode_u(0x1, 1, OP_LUI)))                  # x1 += 0x1000 → 0x1200
prog.append((0x054, encode_s(0x08, 1, 29, F3_SW, OP_S)))        # DMA_DST_ADDR = 0x1200

# DMA_TRANS_LEN = 16
prog.append((0x058, encode_i(16, 0, F3_ADD_SUB, 1, OP_I)))      # x1 = 16
prog.append((0x05C, encode_s(0x0C, 1, 29, F3_SW, OP_S)))        # DMA_TRANS_LEN = 16

# DMA_CTRL = 0x01 (start, dir=mem2mem=00, width=byte=00)
prog.append((0x060, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1
prog.append((0x064, encode_s(0x00, 1, 29, F3_SW, OP_S)))        # DMA_CTRL = 1 (start)

# Poll DMA_STATUS until done (bit 1)
# Wait loop: read STATUS, check bit 1
prog.append((0x068, encode_i(0x10, 29, F3_LW, 1, OP_LOAD)))     # x1 = DMA_STATUS
prog.append((0x06C, encode_i(2, 0, F3_ADD_SUB, 2, OP_I)))       # x2 = 2 (done mask)
prog.append((0x070, encode_r("0000000", 2, 1, F3_AND, 1, OP_R))) # x1 = x1 & 2
prog.append((0x074, encode_b(-12, 0, 1, F3_BEQ, OP_B)))          # if (x1 & 2)==0, loop back

# Verify: read destination memory and compare
# Load 4 words from DMEM[0x1200..0x120C]
prog.append((0x078, encode_u(0x1, 1, OP_LUI)))                  # x1 = 0x1000
prog.append((0x07C, encode_i(0x200, 1, F3_ADD_SUB, 1, OP_I)))   # x1 = 0x1200
prog.append((0x080, encode_i(0, 1, F3_LW, 2, OP_LOAD)))         # x2 = [0x1200]
prog.append((0x084, encode_i(4, 1, F3_LW, 3, OP_LOAD)))         # x3 = [0x1204]
prog.append((0x088, encode_i(8, 1, F3_LW, 4, OP_LOAD)))         # x4 = [0x1208]
prog.append((0x08C, encode_i(0xC, 1, F3_LW, 5, OP_LOAD)))       # x5 = [0x120C]

# Compare with expected values
prog.append((0x090, encode_i(0xDE, 0, F3_ADD_SUB, 6, OP_I)))    # x6 = 0xDE
prog.append((0x094, encode_b(8, 6, 2, F3_BNE, OP_B)))           # if x2!=0xDE, skip pass
prog.append((0x098, encode_i(0xAD, 0, F3_ADD_SUB, 6, OP_I)))    # x6 = 0xAD
prog.append((0x09C, encode_b(8, 6, 3, F3_BNE, OP_B)))           # if x3!=0xAD, skip pass
prog.append((0x0A0, encode_i(0xBE, 0, F3_ADD_SUB, 6, OP_I)))    # x6 = 0xBE
prog.append((0x0A4, encode_b(8, 6, 4, F3_BNE, OP_B)))           # if x4!=0xBE, skip pass
prog.append((0x0A8, encode_i(0xEF, 0, F3_ADD_SUB, 6, OP_I)))    # x6 = 0xEF
prog.append((0x0AC, encode_b(8, 6, 5, F3_BNE, OP_B)))           # if x5!=0xEF, skip pass

# All 4 words match → DMA mem2mem PASS
prog.append((0x0B0, encode_i(1, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++)
prog.append((0x0B4, encode_i(1, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 1 (test ID)
prog.append((0x0B8, encode_j(12, 0, OP_JAL)))                    # skip fail
# FAIL path:
prog.append((0x0BC, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# ================================================================
# Section 2: DMA Transfer-Complete Interrupt (0x0C0-0x14C)
# ================================================================
# Set up trap handler for DMA IRQ
# Trap handler at address 0x130
prog.append((0x0C0, encode_i(0x130, 0, F3_ADD_SUB, 16, OP_I)))  # x16 = 0x130
prog.append((0x0C4, encode_csr(0x305, 16, F3_CSRRW, 0)))        # mtvec = 0x130

# Prepare fresh source data for second DMA transfer
prog.append((0x0C8, encode_i(0x55, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0x55
prog.append((0x0CC, encode_i(0xAA, 0, F3_ADD_SUB, 2, OP_I)))    # x2 = 0xAA
prog.append((0x0D0, encode_u(0x1, 3, OP_LUI)))                  # x3 = 0x1000
prog.append((0x0D4, encode_i(0x100, 3, F3_ADD_SUB, 3, OP_I)))   # x3 = 0x1100
prog.append((0x0D8, encode_s(0, 1, 3, F3_SW, OP_S)))            # [0x1100] = 0x55
prog.append((0x0DC, encode_s(4, 2, 3, F3_SW, OP_S)))            # [0x1104] = 0xAA

# Clear x15 (interrupt flag) — used to detect IRQ
prog.append((0x0E0, encode_i(0, 0, F3_ADD_SUB, 15, OP_I)))      # x15 = 0

# Configure DMA: src=0x1100, dst=0x1200, len=8, irq_en=1
prog.append((0x0E4, encode_u(0x1, 1, OP_LUI)))                  # x1 = 0x1000
prog.append((0x0E8, encode_i(0x100, 1, F3_ADD_SUB, 1, OP_I)))   # x1 = 0x1100
prog.append((0x0EC, encode_s(0x04, 1, 29, F3_SW, OP_S)))        # DMA_SRC_ADDR = 0x1100
prog.append((0x0F0, encode_i(0x200, 0, F3_ADD_SUB, 1, OP_I)))   # x1 = 0x200
prog.append((0x0F4, encode_u(0x1, 1, OP_LUI)))                  # x1 = 0x1200
prog.append((0x0F8, encode_s(0x08, 1, 29, F3_SW, OP_S)))        # DMA_DST_ADDR = 0x1200
prog.append((0x0FC, encode_i(8, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 8
prog.append((0x100, encode_s(0x0C, 1, 29, F3_SW, OP_S)))        # DMA_TRANS_LEN = 8
# IRQ_EN register at offset 0x14
prog.append((0x104, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1
prog.append((0x108, encode_s(0x14, 1, 29, F3_SW, OP_S)))        # DMA_IRQ_EN = 1

# Enable MIE (machine interrupt enable) - bit for external interrupts
# For simplicity, set mstatus.MIE and mie fully
prog.append((0x10C, encode_i(8, 0, F3_ADD_SUB, 16, OP_I)))      # x16 = 0x8 (MIE bit in mstatus)
prog.append((0x110, encode_csr(0x300, 16, F3_CSRRW, 0)))        # mstatus = 0x8
prog.append((0x114, encode_i(-1, 0, F3_ADD_SUB, 16, OP_I)))     # x16 = 0xFFFFFFFF (enable all)
prog.append((0x118, encode_csr(0x304, 16, F3_CSRRW, 0)))        # mie = all enabled

# Start DMA transfer
prog.append((0x11C, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1
prog.append((0x120, encode_s(0x00, 1, 29, F3_SW, OP_S)))        # DMA_CTRL = 1 (start)

# Wait for interrupt: spin until x15 becomes non-zero
# 0x124: loop
prog.append((0x124, NOP))
prog.append((0x128, encode_b(-4, 0, 15, F3_BEQ, OP_B)))         # if x15==0, keep spinning

# Interrupt fired → check x15 == 1 (trap handler sets it)
prog.append((0x12C, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1
prog.append((0x130, encode_b(8, 1, 15, F3_BNE, OP_B)))          # if x15!=1, skip pass
# Wait — 0x130 is trap handler! Need to relocate.
# Actually we set mtvec=0x130, so trap handler IS at 0x130. We need to move the
# post-interrupt check. Let me reorganize: trap handler goes at 0x170.
# Re-do: mtvec = 0x170, post-check at 0x130

# (We'll fix the addresses below — writing final version)
prog = prog[:len(prog) - 4]  # Remove last 4 entries (0x124-0x130)

# Fix: trap handler at 0x170
# Re-set mtvec
prog.append((0x10C, encode_i(8, 0, F3_ADD_SUB, 16, OP_I)))      # x16 = 0x8
prog.append((0x110, encode_csr(0x300, 16, F3_CSRRW, 0)))        # mstatus = 0x8
prog.append((0x114, encode_i(-1, 0, F3_ADD_SUB, 16, OP_I)))     # x16 = 0xFFFFFFFF
prog.append((0x118, encode_csr(0x304, 16, F3_CSRRW, 0)))        # mie = all

# Start DMA
prog.append((0x11C, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1
prog.append((0x120, encode_s(0x00, 1, 29, F3_SW, OP_S)))        # DMA_CTRL = 1

# Spin wait for x15 != 0
# 0x124: spin
prog.append((0x124, NOP))
prog.append((0x128, encode_b(-4, 0, 15, F3_BEQ, OP_B)))         # if x15==0, spin

# x15 should be 1 (set by trap handler)
prog.append((0x12C, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1
prog.append((0x130, encode_b(12, 1, 15, F3_BNE, OP_B)))         # if x15!=1, skip → fail
prog.append((0x134, encode_i(2, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++, test 2)
prog.append((0x138, encode_i(2, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 2
prog.append((0x13C, encode_j(12, 0, OP_JAL)))                    # skip fail
# FAIL:
prog.append((0x140, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# Disable interrupts after DMA IRQ test
prog.append((0x144, encode_i(0, 0, F3_ADD_SUB, 16, OP_I)))      # x16 = 0
prog.append((0x148, encode_csr(0x304, 16, F3_CSRRW, 0)))        # mie = 0
prog.append((0x14C, encode_csr(0x300, 16, F3_CSRRW, 0)))        # mstatus = 0

# ================================================================
# Section 3: I-Cache Enable/Disable (0x150-0x178)
# ================================================================
# I-Cache CTRL at 0x9000, STATUS at 0x9004
prog.append((0x150, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1 (enable)
prog.append((0x154, encode_s(0, 1, 30, F3_SW, OP_S)))           # ICACHE_CTRL = 1
# Readback CTRL to verify enable bit
prog.append((0x158, encode_i(0, 30, F3_LW, 2, OP_LOAD)))        # x2 = ICACHE_CTRL readback
prog.append((0x15C, encode_i(1, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 1 (expected)
prog.append((0x160, encode_b(8, 3, 2, F3_BNE, OP_B)))           # if x2!=1, skip pass
prog.append((0x164, encode_i(3, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++, test 3)
prog.append((0x168, encode_i(3, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 3
prog.append((0x16C, encode_j(8, 0, OP_JAL)))                    # skip fail
prog.append((0x170, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# Disable cache
prog.append((0x174, encode_i(0, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 0
prog.append((0x178, encode_s(0, 1, 30, F3_SW, OP_S)))           # ICACHE_CTRL = 0

# ================================================================
# Section 4: I-Cache Hit/Miss Statistics (0x17C-0x1C0)
# ================================================================
# Enable cache, read some addresses, check HIT_CNT and MISS_CNT
prog.append((0x17C, encode_i(1, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 1
prog.append((0x180, encode_s(0, 1, 30, F3_SW, OP_S)))           # ICACHE_CTRL = 1 (enable)

# Execute several reads from inst_mem (which goes through I-Cache).
# We do this by reading from data memory (addresses 0x1000-0x100F).
# These reads go through data path, not I-Cache. I-Cache only caches instruction fetches.
# To test I-Cache hit/miss we rely on the instruction fetches themselves.
# After enabling cache, the next instruction fetches will cause misses on first access.
# We add a small loop to generate multiple instruction fetches.

# Loop: execute 64 iterations of NOP (each iteration = 2 instructions = 2 fetches)
prog.append((0x184, encode_i(64, 0, F3_ADD_SUB, 1, OP_I)))      # x1 = 64 (loop counter)
# 0x188: loop body
prog.append((0x188, encode_i(-1, 1, F3_ADD_SUB, 1, OP_I)))      # x1--
prog.append((0x18C, encode_b(-4, 0, 1, F3_BNE, OP_B)))          # if x1!=0, loop

# Read hit/miss counters
prog.append((0x190, encode_i(8, 30, F3_LW, 2, OP_LOAD)))        # x2 = HIT_CNT
prog.append((0x194, encode_i(0xC, 30, F3_LW, 3, OP_LOAD)))      # x3 = MISS_CNT

# We expect: HIT_CNT > 0 (loop body re-fetched same cache lines)
# and MISS_CNT > 0 (initial cold misses)
# Check: HIT_CNT > 0
prog.append((0x198, encode_b(20, 0, 2, F3_BEQ, OP_B)))          # if HIT_CNT==0, skip → fail
# Check: MISS_CNT > 0
prog.append((0x19C, encode_b(16, 0, 3, F3_BEQ, OP_B)))          # if MISS_CNT==0, skip → fail
# Both non-zero → pass
prog.append((0x1A0, encode_i(4, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++, test 4)
prog.append((0x1A4, encode_i(4, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 4
prog.append((0x1A8, encode_j(8, 0, OP_JAL)))                    # skip fail
prog.append((0x1AC, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# ================================================================
# Section 5: I-Cache Flush (0x1B0-0x1EC)
# ================================================================
# Flush: write bit 1 of CTRL → auto-clears after flush completes
prog.append((0x1B0, encode_i(3, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 3 (enable + flush)
prog.append((0x1B4, encode_s(0, 1, 30, F3_SW, OP_S)))           # ICACHE_CTRL = 3 (flush)

# Poll STATUS until busy clears (bit 0)
# 0x1B8: poll
prog.append((0x1B8, encode_i(4, 30, F3_LW, 2, OP_LOAD)))        # x2 = ICACHE_STATUS
prog.append((0x1BC, encode_i(1, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 1 (busy mask)
prog.append((0x1C0, encode_r("0000000", 3, 2, F3_AND, 2, OP_R))) # x2 = x2 & 1
prog.append((0x1C4, encode_b(-12, 0, 2, F3_BNE, OP_B)))          # if busy, keep polling

# After flush, MISS_CNT should have increased on next access.
# Read MISS_CNT now (post-flush baseline)
prog.append((0x1C8, encode_i(0xC, 30, F3_LW, 4, OP_LOAD)))      # x4 = MISS_CNT (after flush)

# Re-enable cache (flush auto-cleared enable? No, flush only clears flush bit.
# But the write of 3 set enable=1 AND flush=1. After flush, enable stays 1.)
# Do a read to trigger a miss
prog.append((0x1CC, encode_i(64, 0, F3_ADD_SUB, 1, OP_I)))      # x1 = 64
# 0x1D0: loop
prog.append((0x1D0, encode_i(-1, 1, F3_ADD_SUB, 1, OP_I)))      # x1--
prog.append((0x1D4, encode_b(-4, 0, 1, F3_BNE, OP_B)))          # if x1!=0, loop

# Read MISS_CNT again
prog.append((0x1D8, encode_i(0xC, 30, F3_LW, 5, OP_LOAD)))      # x5 = MISS_CNT (after re-read)

# MISS_CNT should have increased (new misses after flush)
prog.append((0x1DC, encode_r("0100000", 4, 5, F3_ADD_SUB, 6, OP_R)))  # x6 = x5 - x4
prog.append((0x1E0, encode_b(12, 0, 6, F3_BEQ, OP_B)))          # if diff==0, fail
prog.append((0x1E4, encode_i(5, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++, test 5)
prog.append((0x1E8, encode_i(5, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 5
prog.append((0x1EC, encode_j(8, 0, OP_JAL)))                    # skip fail
prog.append((0x1F0, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# Disable cache after flush test
prog.append((0x1F4, encode_i(0, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 0
prog.append((0x1F8, encode_s(0, 1, 30, F3_SW, OP_S)))           # ICACHE_CTRL = 0

# ================================================================
# Section 6: I2C Write Operation (0x1FC-0x238)
# ================================================================
# I2C register map:
#   0x00: CTRL     [0]=enable, [1]=start, [2]=stop, [3]=ack, [4]=irq_en
#   0x04: STATUS   [0]=busy, [1]=ack_rx, [2]=arb_lost, [3]=ack_err
#   0x08: DATA     [7:0]=data byte
#   0x0C: DIVIDER  [15:0]=clock divider
#   0x10: CMD      [0]=write, [1]=read, [2]=restart

# Set divider (small value for simulation speed)
prog.append((0x1FC, encode_i(4, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 4
prog.append((0x200, encode_s(0xC, 1, 31, F3_SW, OP_S)))        # I2C_DIVIDER = 4

# Set slave address (0x50) into DATA register
prog.append((0x204, encode_i(0x50, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0x50
prog.append((0x208, encode_s(8, 1, 31, F3_SW, OP_S)))          # I2C_DATA = 0x50

# Write data byte
prog.append((0x20C, encode_i(0xA5, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0xA5 (test byte)
prog.append((0x210, encode_s(8, 1, 31, F3_SW, OP_S)))          # I2C_DATA = 0xA5

# Start transfer: CTRL = enable(1) | start(2) | stop(4) = 0x07
prog.append((0x214, encode_i(0x07, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0x07
prog.append((0x218, encode_s(0, 1, 31, F3_SW, OP_S)))           # I2C_CTRL = 0x07

# Poll STATUS until not busy (bit 0)
# 0x21C: poll
prog.append((0x21C, encode_i(4, 31, F3_LW, 2, OP_LOAD)))       # x2 = I2C_STATUS
prog.append((0x220, encode_i(1, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 1 (busy mask)
prog.append((0x224, encode_r("0000000", 3, 2, F3_AND, 2, OP_R))) # x2 = x2 & 1
prog.append((0x228, encode_b(-12, 0, 2, F3_BNE, OP_B)))         # if busy, keep polling

# Read STATUS: check busy==0 and ack_err==0 (write should succeed)
prog.append((0x22C, encode_i(4, 31, F3_LW, 2, OP_LOAD)))       # x2 = I2C_STATUS
prog.append((0x230, encode_i(1, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 1
prog.append((0x234, encode_r("0000000", 3, 2, F3_AND, 4, OP_R))) # x4 = busy bit
prog.append((0x238, encode_b(16, 0, 4, F3_BNE, OP_B)))          # if busy!=0, fail
# ack_err check (bit 3)
prog.append((0x23C, encode_i(8, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 8
prog.append((0x240, encode_r("0000000", 3, 2, F3_AND, 4, OP_R))) # x4 = ack_err bit
prog.append((0x244, encode_b(8, 0, 4, F3_BNE, OP_B)))           # if ack_err!=0, fail
# Pass
prog.append((0x248, encode_i(6, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++, test 6)
prog.append((0x24C, encode_i(6, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 6
prog.append((0x250, encode_j(8, 0, OP_JAL)))                    # skip fail
prog.append((0x254, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# ================================================================
# Section 7: I2C Read Operation (0x258-0x2A0)
# ================================================================
# Set up read: addr=0x50, read mode
# Write address with read bit (0x51) to DATA
prog.append((0x258, encode_i(0x51, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0x51 (0x50 | read)
prog.append((0x25C, encode_s(8, 1, 31, F3_SW, OP_S)))          # I2C_DATA = 0x51

# Start read: CTRL = enable | start = 0x03 (no stop, expect data)
prog.append((0x260, encode_i(0x03, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0x03
prog.append((0x264, encode_s(0, 1, 31, F3_SW, OP_S)))          # I2C_CTRL = 0x03

# Poll until not busy
# 0x268: poll
prog.append((0x268, encode_i(4, 31, F3_LW, 2, OP_LOAD)))       # x2 = I2C_STATUS
prog.append((0x26C, encode_i(1, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 1
prog.append((0x270, encode_r("0000000", 3, 2, F3_AND, 2, OP_R))) # x2 = x2 & 1
prog.append((0x274, encode_b(-12, 0, 2, F3_BNE, OP_B)))         # if busy, keep polling

# Read data register
prog.append((0x278, encode_i(8, 31, F3_LW, 5, OP_LOAD)))       # x5 = I2C_DATA (RX data)

# Check: busy==0 (transfer completed) and ack_err==0
prog.append((0x27C, encode_i(4, 31, F3_LW, 2, OP_LOAD)))       # x2 = I2C_STATUS
prog.append((0x280, encode_i(1, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 1
prog.append((0x284, encode_r("0000000", 3, 2, F3_AND, 4, OP_R))) # x4 = busy
prog.append((0x288, encode_b(16, 0, 4, F3_BNE, OP_B)))          # if busy!=0, fail
prog.append((0x28C, encode_i(8, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 8
prog.append((0x290, encode_r("0000000", 3, 2, F3_AND, 4, OP_R))) # x4 = ack_err
prog.append((0x294, encode_b(8, 0, 4, F3_BNE, OP_B)))           # if ack_err!=0, fail
# Pass
prog.append((0x298, encode_i(7, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++, test 7)
prog.append((0x29C, encode_i(7, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 7
prog.append((0x2A0, encode_j(8, 0, OP_JAL)))                    # skip fail
prog.append((0x2A4, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# ================================================================
# Section 8: I2C NACK Handling (0x2A8-0x2EC)
# ================================================================
# Use an invalid address (0x7F) that no slave will ACK
prog.append((0x2A8, encode_i(0x7F, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0x7F (invalid addr)
prog.append((0x2AC, encode_s(8, 1, 31, F3_SW, OP_S)))          # I2C_DATA = 0x7F

# Start transfer: enable + start + stop
prog.append((0x2B0, encode_i(0x07, 0, F3_ADD_SUB, 1, OP_I)))    # x1 = 0x07
prog.append((0x2B4, encode_s(0, 1, 31, F3_SW, OP_S)))          # I2C_CTRL = 0x07

# Poll until not busy
# 0x2B8: poll
prog.append((0x2B8, encode_i(4, 31, F3_LW, 2, OP_LOAD)))       # x2 = I2C_STATUS
prog.append((0x2BC, encode_i(1, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 1
prog.append((0x2C0, encode_r("0000000", 3, 2, F3_AND, 2, OP_R))) # x2 = x2 & 1
prog.append((0x2C4, encode_b(-12, 0, 2, F3_BNE, OP_B)))         # if busy, keep polling

# Read STATUS: check ack_err (bit 3) is set
prog.append((0x2C8, encode_i(4, 31, F3_LW, 2, OP_LOAD)))       # x2 = I2C_STATUS
prog.append((0x2CC, encode_i(8, 0, F3_ADD_SUB, 3, OP_I)))       # x3 = 8 (ack_err mask)
prog.append((0x2D0, encode_r("0000000", 3, 2, F3_AND, 4, OP_R))) # x4 = ack_err bit
prog.append((0x2D4, encode_b(8, 0, 4, F3_BEQ, OP_B)))           # if ack_err==0, fail (expected NACK)
# Pass: NACK detected as expected
prog.append((0x2D8, encode_i(8, 8, F3_ADD_SUB, 8, OP_I)))       # x8++ (pass++, test 8)
prog.append((0x2DC, encode_i(8, 0, F3_ADD_SUB, 10, OP_I)))      # x10 = 8
prog.append((0x2E0, encode_j(8, 0, OP_JAL)))                    # skip fail
prog.append((0x2E4, encode_i(1, 9, F3_ADD_SUB, 9, OP_I)))       # x9++ (fail++)

# ================================================================
# Section 9: Results Reporting (0x2E8-0x304)
# ================================================================
# Write pass/fail summary to GPIO[0]:
#   GPIO[0] = {8'b0, last_test_id, fail_count, pass_count}
#   pass_count in [7:0], fail_count in [15:8], test_id in [23:16]

# x8 = pass count, x9 = fail count, x10 = last passed test ID
# Pack: result = x8 | (x9 << 8) | (x10 << 16)
prog.append((0x2E8, encode_i(8, 0, F3_ADD_SUB, 1, OP_I)))       # x1 = 8
prog.append((0x2EC, encode_r("0000000", 1, 9, F3_SLL, 2, OP_R))) # x2 = x9 << 8
prog.append((0x2F0, encode_r("0000000", 2, 8, F3_OR, 2, OP_R))) # x2 = x8 | (x9<<8)
prog.append((0x2F4, encode_i(16, 0, F3_ADD_SUB, 3, OP_I)))      # x3 = 16
prog.append((0x2F8, encode_r("0000000", 3, 10, F3_SLL, 4, OP_R))) # x4 = x10 << 16
prog.append((0x2FC, encode_r("0000000", 4, 2, F3_OR, 5, OP_R))) # x5 = x2 | x4

# Write to GPIO
prog.append((0x300, encode_s(0, 5, 11, F3_SW, OP_S)))           # GPIO[0] = result

# ================================================================
# Trap Handler: DMA IRQ (0x304-0x31C)
# ================================================================
# mtvec = 0x170 (set earlier), but we need to fix the earlier mtvec value.
# Actually, we set mtvec=0x130 at 0x0C4. Let's relocate trap handler here at 0x304.
# The mtvec value set at 0x0C4 was 0x130. We need to fix that.
# Let me adjust: set mtvec = 0x304 instead.

# Rebuild: remove the mtvec write at 0x0C4 and set it to 0x304
# (We'll do this by replacing the instruction at 0x0C4)

# Actually, we need to be careful. Let me just set mtvec=0x304 in the DMA IRQ setup section.
# Fix: the instruction at 0x0C4 encodes mtvec=0x130. We need mtvec=0x304.
# 0x304 >> 12 = 0x3, 0x304 & 0xFFF = 0x304

# (We'll patch the mtvec instruction after generating the full program.)

# Trap handler code at 0x304:
# 1. Disable DMA interrupt (write 0 to DMA_IRQ_EN)
# 2. Set x15 = 1 (interrupt flag)
# 3. MRET

prog.append((0x304, encode_i(0, 0, F3_ADD_SUB, 16, OP_I)))      # x16 = 0
prog.append((0x308, encode_s(0x14, 16, 29, F3_SW, OP_S)))       # DMA_IRQ_EN = 0
prog.append((0x30C, encode_i(0, 0, F3_ADD_SUB, 16, OP_I)))      # x16 = 0
prog.append((0x310, encode_csr(0x304, 16, F3_CSRRW, 0)))        # mie = 0
prog.append((0x314, encode_i(1, 0, F3_ADD_SUB, 15, OP_I)))      # x15 = 1
prog.append((0x318, encode_mret()))

# EBREAK: stop simulation
prog.append((0x31C, EBREAK))

# ================================================================
# Post-processing: fix mtvec to point to 0x304
# ================================================================
# Find the mtvec write instruction (originally at 0x0C4) and replace with 0x304
new_prog = []
for addr, binstr in prog:
    if addr == 0x0C4:
        # csrrw x0, mtvec(0x305), x16 where x16 = 0x304
        # We need x16 = 0x304. The previous instruction at 0x0C0 sets x16=0x130.
        # We need to change that to x16=0x304.
        pass  # We'll fix 0x0C0 instead
    new_prog.append((addr, binstr))

prog = new_prog

# Fix: replace instruction at 0x0C0 to load x16=0x304
new_prog = []
for addr, binstr in prog:
    if addr == 0x0C0:
        # addi x16, x0, 0x304
        new_prog.append((addr, encode_i(0x304, 0, F3_ADD_SUB, 16, OP_I)))
    else:
        new_prog.append((addr, binstr))
prog = new_prog

# ================================================================
# Deduplicate (in case of overwrites from reorganization)
# ================================================================
addr_map = {}
for addr, binstr in prog:
    addr_map[addr] = binstr
prog = sorted(addr_map.items())

# ================================================================
# Generate hex file
# ================================================================
max_addr = max(addr for addr, _ in prog)
num_words = max(max_addr // 4 + 1, 256)

hex_lines = [bin_to_hex(NOP)] * num_words
for addr, binstr in prog:
    assert addr % 4 == 0, f"Address {addr:#x} not word-aligned"
    hex_lines[addr // 4] = bin_to_hex(binstr)

with open("inst_mem.hex", "w") as f:
    for h in hex_lines:
        f.write(h + "\n")

print(f"Generated {len(prog)} instructions")
print(f"Address range: 0x000 - 0x{max_addr:03X}")
print("inst_mem.hex written")
print()
print("Test summary:")
print("  Test 1: DMA mem-to-mem transfer       (check 4 words match)")
print("  Test 2: DMA transfer-complete IRQ      (x15==1 after IRQ)")
print("  Test 3: I-Cache enable/disable         (CTRL readback)")
print("  Test 4: I-Cache hit/miss counters      (HIT>0, MISS>0)")
print("  Test 5: I-Cache flush                  (MISS increases)")
print("  Test 6: I2C write operation            (busy==0, ack_err==0)")
print("  Test 7: I2C read operation             (busy==0, ack_err==0)")
print("  Test 8: I2C NACK handling              (ack_err==1)")
print()
print("Expected GPIO output: pass_count | (fail_count<<8) | (last_test_id<<16)")
print("  Ideal: 0x08_00_08 = 0x00080008 (all 8 tests pass)")
