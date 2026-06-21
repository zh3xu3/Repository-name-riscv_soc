#!/usr/bin/env python3
"""Generate inst_mem.hex for RISC-V SoC: GPIO + UART + RV32IM + Extended RV32I + Timer IRQ.

Test sections:
  1. GPIO output/input loopback (0x00-0x2C)
  2. UART TX/RX loopback (0x30-0x50)
  3. RV32I basic: ADDI, ADD, SUB, AND, OR, XOR, SLL, LUI (0x60-0x90)
  4. RV32I extended: SLT, SLTU, SRL, SRA, SRLI, SRAI, AUIPC, JALR, LB, LH, LBU, LHU, SB, SH (0x94-0xDC)
  5. Memory: SW/LW (0xD0-0xD8)  [merged into extended section]
  6. Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU (0xA8-0xCC)
  7. RV32M: MUL, MULH, DIV, REM, DIVU, REMU (0xE0-0xF4)
  8. Timer interrupt + trap handler (0xF8-0x148)

Debug ports: x1-x8, x12-x15 (plus x16-x20 used internally, not checked by TB)
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
F3_CSRRW   = "001"

NOP = "00000000000000000000000000010011"  # addi x0, x0, 0 in binary

prog = [
    # ================================================================
    # Section 1: GPIO Tests (0x00-0x2C)
    # ================================================================
    (0x00, encode_u(0x3, 1, OP_LUI)),                  # x1 = 0x3000 (GPIO base)
    (0x04, encode_u(0xABCD1, 2, OP_LUI)),              # x2 = 0xABCD1000
    (0x08, encode_i(0x234, 2, F3_ADD_SUB, 2, OP_I)),   # x2 = 0xABCD1234
    (0x0C, encode_s(0, 2, 1, F3_SW, OP_S)),            # GPIO[0] = 0xABCD1234
    (0x10, NOP),                                        # sync delay
    (0x14, NOP),
    (0x18, NOP),
    (0x1C, encode_i(0, 1, F3_LW, 3, OP_LOAD)),         # x3 = GPIO output readback
    (0x20, encode_i(4, 1, F3_LW, 4, OP_LOAD)),         # x4 = GPIO input (loopback)
    # Save GPIO results to DMEM[0x1000]
    (0x24, encode_u(0x1, 5, OP_LUI)),                  # x5 = 0x1000
    (0x28, encode_s(0, 3, 5, F3_SW, OP_S)),            # MEM[0x1000] = GPIO readback
    (0x2C, encode_s(4, 4, 5, F3_SW, OP_S)),            # MEM[0x1004] = GPIO loopback

    # ================================================================
    # Section 2: UART Tests (0x30-0x50)
    # ================================================================
    (0x30, encode_u(0x2, 5, OP_LUI)),                  # x5 = 0x2000 (UART base)
    (0x34, encode_i(0x55, 0, F3_ADD_SUB, 6, OP_I)),    # x6 = 0x55
    (0x38, encode_s(0, 6, 5, F3_SW, OP_S)),            # UART TX = 0x55
    # Delay loop: 16384 iterations (~32768 cycles with predictor > 8680 UART TX cycles)
    (0x3C, encode_u(0x4, 7, OP_LUI)),                  # x7 = 16384
    (0x40, encode_i(-1, 7, F3_ADD_SUB, 7, OP_I)),      # x7--
    (0x44, encode_b(-4, 0, 7, F3_BNE, OP_B)),          # if x7!=0 goto 0x40
    (0x48, encode_i(4, 5, F3_LW, 8, OP_LOAD)),         # x8 = UART RX (0x55)
    # Save UART result
    (0x4C, encode_u(0x1, 5, OP_LUI)),                  # x5 = 0x1000
    (0x50, encode_s(8, 8, 5, F3_SW, OP_S)),            # MEM[0x1008] = UART RX

    # ================================================================
    # Jump to RV32I tests
    # ================================================================
    (0x54, encode_j(12, 0, OP_JAL)),                   # jal x0, +12 → 0x60
    (0x58, NOP),
    (0x5C, NOP),

    # ================================================================
    # Section 3: RV32I Basic Tests (0x60-0x90)
    # ================================================================
    (0x60, encode_i(42, 0, F3_ADD_SUB, 1, OP_I)),      # x1 = 42
    (0x64, encode_i(58, 0, F3_ADD_SUB, 2, OP_I)),      # x2 = 58
    (0x68, encode_i(255, 0, F3_ADD_SUB, 5, OP_I)),     # x5 = 255
    (0x6C, encode_i(15, 0, F3_ADD_SUB, 6, OP_I)),      # x6 = 15
    (0x70, encode_r("0000000", 2, 1, F3_ADD_SUB, 3, OP_R)),  # x3 = x1+x2 = 100
    (0x74, encode_r("0100000", 1, 3, F3_ADD_SUB, 4, OP_R)),  # x4 = x3-x1 = 58
    (0x78, encode_r("0000000", 6, 5, F3_AND, 5, OP_R)),      # x5 = 255&15 = 15
    (0x7C, encode_r("0000000", 6, 5, F3_OR, 6, OP_R)),       # x6 = 15|15 = 15
    (0x80, encode_i(-1, 0, F3_ADD_SUB, 7, OP_I)),             # x7 = -1
    (0x84, encode_r("0000000", 6, 7, F3_XOR, 7, OP_R)),      # x7 = -1^15 = 0xFFFFFFF0
    (0x88, encode_i(1, 0, F3_ADD_SUB, 8, OP_I)),              # x8 = 1
    (0x8C, encode_r("0000000", 6, 8, F3_SLL, 8, OP_R)),      # x8 = 1<<15 = 0x8000
    (0x90, encode_u(0x12345, 8, OP_LUI)),                     # x8 = 0x12345000

    # ================================================================
    # Section 4: RV32I Extended Tests (0x94-0xDC)
    # Uses x16-x20 (not checked by TB, safe for internal use)
    # ================================================================
    # --- SLT/SLTU ---
    (0x94, encode_i(-5, 0, F3_ADD_SUB, 16, OP_I)),     # x16 = -5 (0xFFFFFFFB)
    (0x98, encode_i(10, 0, F3_ADD_SUB, 17, OP_I)),    # x17 = 10
    (0x9C, encode_r("0000000", 17, 16, F3_SLT, 1, OP_R)),  # x1 = (x16<x17)?1:0 = 1 (signed)
    (0xA0, encode_r("0000000", 17, 16, F3_SLTU, 2, OP_R)), # x2 = (x16<x17)?1:0 = 0 (unsigned: 0xFFFFFFFB > 10)

    # --- Shifts ---
    (0xA4, encode_i(256, 0, F3_ADD_SUB, 16, OP_I)),   # x16 = 256 (0x100)
    (0xA8, encode_i(4, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 4
    (0xAC, encode_r("0000000", 17, 16, F3_SRL_SRA, 3, OP_R)),  # x3 = 256>>4 = 16 (SRL)
    (0xB0, encode_i(-16, 0, F3_ADD_SUB, 16, OP_I)),   # x16 = -16 (0xFFFFFFF0)
    (0xB4, encode_r("0100000", 17, 16, F3_SRL_SRA, 4, OP_R)),  # x4 = -16>>>4 = -1 (SRA)
    (0xB8, encode_i(1, 0, F3_ADD_SUB, 16, OP_I)),     # x16 = 1
    (0xBC, encode_i(31, 0, F3_ADD_SUB, 17, OP_I)),    # x17 = 31
    (0xC0, encode_r("0000000", 17, 16, F3_SRL_SRA, 5, OP_R)),  # x5 = 1u>>31 = 0 (SRLI)

    # --- AUIPC ---
    (0xC4, encode_u(0x10, 16, OP_AUIPC)),              # x16 = PC + 0x10000 (PC=0xC4, x16=0x100C4)

    # --- JALR ---
    (0xC8, encode_i(0xD0, 0, F3_ADD_SUB, 17, OP_I)),  # x17 = 0xD0 (target)
    (0xCC, encode_i(0, 17, "000", 18, OP_JALR)),       # jalr x18, 0(x17) → x18=0xD0, PC=0xD0
    (0xD0, encode_i(0, 0, F3_ADD_SUB, 0, OP_I)),       # NOP (flushed by JALR)

    # --- Byte/Half store/load ---
    (0xD4, encode_u(0x1, 16, OP_LUI)),                 # x16 = 0x1000 (DMEM base)
    (0xD8, encode_i(0xD0, 0, F3_ADD_SUB, 17, OP_I)),  # x17 = 0xD0
    (0xDC, encode_s(0xD0, 17, 16, F3_SB, OP_S)),        # SB: store 0xD0 to DMEM[0x10D0]
    (0xE0, encode_s(0xD2, 17, 16, F3_SH, OP_S)),       # SH: store 0x00D0 to DMEM[0x10D2..0x10D1]

    # --- Load byte/half tests ---
    (0xE4, encode_i(0xD0, 16, F3_LB, 18, OP_LOAD)),    # x18 = LB from 0x10D0 = sign_ext(0xD0) = 0xFFFFFFD0
    (0xE8, encode_i(0xD0, 16, F3_LBU, 19, OP_LOAD)),   # x19 = LBU from 0x10D0 = 0x000000D0
    (0xEC, encode_i(0xD2, 16, F3_LH, 20, OP_LOAD)),    # x20 = LH from 0x10D2 = sign_ext(0x00D0) = 0x000000D0
    (0xF0, encode_i(0xD2, 16, F3_LHU, 18, OP_LOAD)),   # x18 = LHU from 0x10D2 = 0x000000D0

    # --- Load M-extension operands into x20,x21 (not checked by TB) ---
    (0xF4, encode_i(58, 0, F3_ADD_SUB, 20, OP_I)),     # x20 = 58
    (0xF8, encode_i(100, 0, F3_ADD_SUB, 21, OP_I)),    # x21 = 100

    # --- M-extension tests (uses x20,x21 to avoid clobbering x2,x3) ---
    (0xFC, encode_r("0000001", 21, 20, "000", 9, OP_R)),   # x9  = MUL(58,100) = 5800
    (0x100, encode_r("0000001", 21, 20, "001", 10, OP_R)), # x10 = MULH(58,100) = 0
    (0x104, encode_r("0000001", 20, 21, "100", 11, OP_R)), # x11 = DIV(100,58) = 1
    (0x108, encode_r("0000001", 20, 21, "110", 12, OP_R)), # x12 = REM(100,58) = 42
    (0x10C, encode_r("0000001", 20, 21, "101", 13, OP_R)), # x13 = DIVU(100,58) = 1
    (0x110, encode_r("0000001", 20, 21, "111", 14, OP_R)), # x14 = REMU(100,58) = 42

    # ================================================================
    # Section 5: SPI Test (0x114-0x140)
    # SPI loopback: MOSI connected to MISO in TB
    # ================================================================
    (0x114, encode_u(0x5, 16, OP_LUI)),                # x16 = 0x5000 (SPI base)
    (0x118, encode_i(0x10, 0, F3_ADD_SUB, 17, OP_I)),  # x17 = 0x10 (CPOL=0, CPHA=0, div=1)
    (0x11C, encode_s(4, 17, 16, F3_SW, OP_S)),         # SPI_CTRL = 0x12
    (0x120, encode_i(0, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 0
    (0x124, encode_s(0xC, 17, 16, F3_SW, OP_S)),       # SPI_CS = 0 (active)
    (0x128, encode_i(0xA5, 0, F3_ADD_SUB, 17, OP_I)),  # x17 = 0xA5 (test byte)
    (0x12C, encode_s(0, 17, 16, F3_SW, OP_S)),         # SPI_DATA = 0xA5 (start TX)
    # Delay for SPI transfer (~80 cycles)
    (0x130, encode_u(0x1, 17, OP_LUI)),                 # x17 = 4096
    (0x134, encode_i(-1, 17, F3_ADD_SUB, 17, OP_I)),   # x17--
    (0x138, encode_b(-4, 0, 17, F3_BNE, OP_B)),        # if x17!=0 goto 0x134
    # Read SPI results
    (0x13C, encode_i(0, 16, F3_LW, 18, OP_LOAD)),      # x18 = SPI_DATA (RX: loopback 0xA5)
    (0x140, encode_i(8, 16, F3_LW, 19, OP_LOAD)),      # x19 = SPI_STATUS (busy=0, rx_valid=1)
    (0x144, encode_i(1, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 1
    (0x148, encode_s(0xC, 17, 16, F3_SW, OP_S)),       # SPI_CS = 1 (inactive)
    # Save SPI results to DMEM
    (0x14C, encode_u(0x1, 16, OP_LUI)),                 # x16 = 0x1000
    (0x150, encode_s(0xC, 18, 16, F3_SW, OP_S)),       # MEM[0x100C] = SPI RX
    (0x154, encode_s(0x10, 19, 16, F3_SW, OP_S)),      # MEM[0x1010] = SPI STATUS

    # ================================================================
    # Section 6: PWM Test (0x158-0x184)
    # ================================================================
    (0x158, encode_u(0x6, 16, OP_LUI)),                 # x16 = 0x6000 (PWM base)
    (0x15C, encode_i(3, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 3 (period)
    (0x160, encode_s(4, 17, 16, F3_SW, OP_S)),         # PWM_PERIOD = 3
    (0x164, encode_i(2, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 2 (duty0)
    (0x168, encode_s(8, 17, 16, F3_SW, OP_S)),         # PWM_DUTY0 = 2
    (0x16C, encode_i(1, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 1 (duty1)
    (0x170, encode_s(0xC, 17, 16, F3_SW, OP_S)),       # PWM_DUTY1 = 1
    (0x174, encode_i(0x51, 0, F3_ADD_SUB, 17, OP_I)),  # x17 = 0x51 (global_en + ch0_en + ch1_en)
    (0x178, encode_s(0, 17, 16, F3_SW, OP_S)),         # PWM_CTRL = 0x51
    # Wait for PWM counter to tick
    (0x17C, NOP),
    (0x180, NOP),
    (0x184, NOP),
    # Read PWM results
    (0x188, encode_i(4, 16, F3_LW, 18, OP_LOAD)),      # x18 = PWM_PERIOD readback
    (0x18C, encode_i(0, 16, F3_LW, 19, OP_LOAD)),      # x19 = PWM_CTRL readback
    (0x190, encode_i(0x18, 16, F3_LW, 20, OP_LOAD)),   # x20 = PWM_COUNT
    # Save PWM results
    (0x194, encode_u(0x1, 16, OP_LUI)),                 # x16 = 0x1000
    (0x198, encode_s(0x14, 18, 16, F3_SW, OP_S)),      # MEM[0x1014] = PWM_PERIOD
    (0x19C, encode_s(0x18, 19, 16, F3_SW, OP_S)),      # MEM[0x1018] = PWM_CTRL

    # ================================================================
    # Section 7: PLIC Test (0x1A0-0x1C8)
    # ================================================================
    (0x1A0, encode_u(0x7, 16, OP_LUI)),                 # x16 = 0x7000 (PLIC base)
    (0x1A4, encode_i(0xFF, 0, F3_ADD_SUB, 17, OP_I)),  # x17 = 0xFF (enable sources 0-7)
    (0x1A8, encode_s(4, 17, 16, F3_SW, OP_S)),         # PLIC_ENABLE = 0xFF
    (0x1AC, encode_i(5, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 5 (threshold)
    (0x1B0, encode_s(8, 17, 16, F3_SW, OP_S)),         # PLIC_THRESHOLD = 5
    # Read PLIC results
    (0x1B4, encode_i(4, 16, F3_LW, 18, OP_LOAD)),      # x18 = PLIC_ENABLE readback
    (0x1B8, encode_i(8, 16, F3_LW, 19, OP_LOAD)),      # x19 = PLIC_THRESHOLD readback
    (0x1BC, encode_i(0, 16, F3_LW, 20, OP_LOAD)),      # x20 = PLIC_PENDING (should be 0)
    # Save PLIC results
    (0x1C0, encode_u(0x1, 16, OP_LUI)),                 # x16 = 0x1000
    (0x1C4, encode_s(0x1C, 18, 16, F3_SW, OP_S)),      # MEM[0x101C] = PLIC_ENABLE
    (0x1C8, encode_s(0x20, 19, 16, F3_SW, OP_S)),      # MEM[0x1020] = PLIC_THRESHOLD
    (0x1CC, encode_s(0x24, 20, 16, F3_SW, OP_S)),      # MEM[0x1024] = PLIC_PENDING

    # --- Jump to interrupt test ---
    (0x1D0, encode_j(16, 0, OP_JAL)),                   # jal x0, +16 → 0x1E0

    # ================================================================
    # Section 8: Interrupt Test Setup (0x1E0-0x220)
    # ================================================================
    (0x1E0, encode_i(0, 0, F3_ADD_SUB, 15, OP_I)),     # x15 = 0
    (0x1E4, encode_i(0x224, 0, F3_ADD_SUB, 16, OP_I)), # x16 = trap handler addr (0x224)
    (0x1E8, encode_csr(0x305, 16, F3_CSRRW, 0)),       # mtvec = 0x224
    # mtimecmp = 200000 (0x30D40) — must be larger than total program cycles
    (0x1EC, encode_u(0x31, 16, OP_LUI)),               # x16 = 0x31000
    (0x1F0, encode_i(0xD40, 16, F3_ADD_SUB, 16, OP_I)),# x16 = 0x31D40 (204096)
    (0x1F4, encode_csr(0xB02, 16, F3_CSRRW, 0)),       # mtimecmp_lo = 204096
    (0x1F8, encode_csr(0xB03, 0, F3_CSRRW, 0)),        # mtimecmp_hi = 0
    (0x1FC, encode_i(0x80, 0, F3_ADD_SUB, 16, OP_I)),  # x16 = MTIE bit
    (0x200, encode_csr(0x304, 16, F3_CSRRW, 0)),       # mie = 0x80
    (0x204, encode_i(8, 0, F3_ADD_SUB, 16, OP_I)),     # x16 = MIE bit
    (0x208, encode_csr(0x300, 16, F3_CSRRW, 0)),       # mstatus = 0x8 (enable IRQ)
    (0x20C, encode_j(0, 0, OP_JAL)),                    # jal x0, +0 → wait for IRQ

    # ================================================================
    # Section 9: Trap Handler (mtvec = 0x224)
    # ================================================================
    (0x224, encode_i(0, 0, F3_ADD_SUB, 17, OP_I)),     # x17 = 0
    (0x228, encode_csr(0x304, 17, F3_CSRRW, 0)),       # mie = 0 (disable IRQ)
    (0x22C, encode_i(-1, 0, F3_ADD_SUB, 17, OP_I)),    # x17 = 0xFFFFFFFF
    (0x230, encode_csr(0xB02, 17, F3_CSRRW, 0)),       # mtimecmp = max (clear pending)
    (0x234, encode_i(1, 15, F3_ADD_SUB, 15, OP_I)),    # x15++ (x15=1, timer fired)
    (0x238, encode_mret()),                             # return to 0x20C (self-jump → halt)
]

# Generate hex file
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
