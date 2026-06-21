# RISC-V SoC — RV32IM 5-Stage Pipelined Soft-Core Processor

A complete RISC-V RV32IM SoC implemented in Verilog, targeting Xilinx Artix-7 FPGA. Features a 5-stage pipeline with branch prediction, machine-mode interrupts, and a full peripheral subsystem (GPIO, UART, SPI, PWM, PLIC). Successfully runs FreeRTOS.

**22/22 tests passing** — verified with iverilog and Vivado xsim.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         soc_top                              │
│  ┌──────────────┐  ┌───────────┐  ┌──────────────┐          │
│  │  riscv_core  │  │ inst_mem  │  │   data_mem   │          │
│  │  ┌────────┐  │  │  (4KB)    │  │   (4KB)      │          │
│  │  │IF/ID/EX│  │  └───────────┘  └──────────────┘          │
│  │  │MEM/WB  │  │                                            │
│  │  │  ALU   │  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐    │
│  │  │  MUL   │  │  │ UART │ │ GPIO │ │ SPI  │ │ PWM  │    │
│  │  │  DIV   │  │  │(TX/RX)│ │(32b) │ │(Mstr)│ │(4ch) │    │
│  │  │  CSR   │  │  └──────┘ └──────┘ └──────┘ └──────┘    │
│  │  │  RF    │  │                                            │
│  │  │  BHT   │  │  ┌──────┐ ┌──────────────────────┐       │
│  │  │  BTB   │  │  │ WDT  │ │  PLIC (16 sources)   │       │
│  │  └────────┘  │  └──────┘ └──────────────────────┘       │
│  └──────────────┘                                            │
│                    Address Decoder (bus)                      │
└──────────────────────────────────────────────────────────────┘
```

### Pipeline Stages

| Stage | Function |
|-------|----------|
| **IF**  | Instruction fetch, PC update, branch prediction, interrupt/branch mux |
| **ID**  | Decode, register file read, immediate generation, branch resolution & BHT update |
| **EX**  | ALU / MUL / DIV execution, forwarding (EX/MEM→EX, MEM/WB→EX) |
| **MEM** | Data memory read/write (byte/half/word), peripheral access |
| **WB**  | Writeback to register file, CSR write, trap detection |

### Hazard Handling

- **Data forwarding**: EX/MEM→EX and MEM/WB→EX two-level forwarding
- **Load-use stall**: 1-cycle bubble when load result is needed immediately
- **Branch prediction**: 2-bit saturating counter BHT + BTB (64 entries), ID-stage update
- **Divider freeze**: Iterative 32-cycle divider stalls entire pipeline
- **Interrupt suppression**: `wb_we` gated by `!irq_trap`; forwarding uses `memwb_reg_wr`

## Supported Instructions

### RV32I Base (37 instructions)

| Category | Instructions |
|----------|-------------|
| Arithmetic | ADD, SUB, ADDI |
| Logic | AND, OR, XOR, ANDI, ORI, XORI |
| Shift | SLL, SRL, SRA, SLLI, SRLI, SRAI |
| Compare | SLT, SLTU, SLTI, SLTIU |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Load/Store | LW, LH, LB, LHU, LBU, SW, SH, SB |
| Jump | JAL, JALR |
| Upper Imm | LUI, AUIPC |
| System | ECALL, MRET |
| CSR | CSRRW, CSRRS, CSRRC |

### RV32M Extension (8 instructions)

MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU

### Interrupts

- Machine timer interrupt (CLINT: mtime/mtimecmp)
- Trap entry/exit with mepc/mcause/mstatus save/restore
- MRET restores MIE from MPIE

## Memory Map

| Address Range | Peripheral |
|---------------|-----------|
| `0x0000_0000 – 0x0000_0FFF` | Instruction Memory (4KB) |
| `0x0000_1000 – 0x0000_1FFF` | Data Memory (4KB) |
| `0x0000_2000 – 0x0000_200F` | UART (TX data, RX data, status, baud) |
| `0x0000_3000 – 0x0000_300F` | GPIO (output, input, direction) |
| `0x0000_5000 – 0x0000_500F` | SPI Master (data, ctrl, status, CS) |
| `0x0000_6000 – 0x0000_601F` | PWM (ctrl, period, duty0-3, count) |
| `0x0000_7000 – 0x0000_703F` | PLIC (pending, enable, threshold, claim) |

## Directory Structure

```
riscv_soc/
├── rtl/
│   ├── core/
│   │   ├── alu.v            # ALU (ADD/SUB/shift/logic/compare)
│   │   ├── branch_comp.v    # Branch comparator
│   │   ├── branch_pred.v    # 2-bit BHT + BTB branch predictor
│   │   ├── control.v        # Instruction decoder + control signals
│   │   ├── csr.v            # CSR registers + CLINT timer
│   │   ├── divider.v        # Iterative 32-cycle divider
│   │   ├── imm_gen.v        # Immediate generator (I/S/B/U/J types)
│   │   ├── reg_file.v       # 32x32-bit register file (2R1W + debug ports)
│   │   └── riscv_core.v     # Pipeline top-level (IF/ID/EX/MEM/WB + forwarding)
│   ├── mem/
│   │   ├── inst_mem.v       # Instruction memory (async read, $readmemh)
│   │   └── data_mem.v       # Data memory (sync write, async read, byte/half/word)
│   ├── periph/
│   │   ├── gpio.v           # GPIO controller (32-bit in/out)
│   │   ├── uart.v           # UART top (TX + RX + baud gen)
│   │   ├── uart_tx.v        # UART transmitter
│   │   ├── uart_rx.v        # UART receiver
│   │   ├── spi.v            # SPI master (CPOL/CPHA, 8-bit shift)
│   │   ├── pwm.v            # PWM controller (4 channels)
│   │   ├── plic.v           # PLIC (16 sources, priority/threshold)
│   │   └── wdt.v            # Watchdog timer
│   └── soc_top.v            # SoC top-level (core + mem + periph + bus decoder)
├── sim/
│   ├── tb_soc.v             # Full SoC testbench (22 tests)
│   ├── tb_rv32i_ext.v       # Extended RV32I testbench (13 tests)
│   ├── tb_quick.v           # Quick smoke test
│   ├── tb_mext.v            # M-extension debug testbench
│   └── Makefile
├── tests/
│   └── sw/
│       ├── gen_uart_gpio.py  # Main test generator (GPIO/UART/RV32I/RV32M/SPI/PWM/PLIC/Timer)
│       ├── gen_hex.py        # Phase 1+2+3 test generator
│       └── gen_rv32i_ext.py  # Extended RV32I test generator
├── freertos/                 # FreeRTOS RV32 port
├── fpga/
│   ├── fpga_top.v            # FPGA top-level wrapper
│   ├── constraints/
│   │   └── a7_lite.xdc       # Artix-7 pin constraints
│   └── scripts/
│       ├── create_project.tcl
│       ├── build.tcl
│       └── simulate.tcl
├── README.md
└── CLAUDE.md
```

## Build & Simulation

### Prerequisites

- **iverilog** (Icarus Verilog) or **Vivado** (xsim)
- **Python 3** — test hex generation
- **GTKWave** — waveform viewer (optional)

### Quick Start (iverilog)

```bash
# Generate test program
cd tests/sw
python gen_uart_gpio.py
cp inst_mem.hex ../../sim/

# Compile and run
cd ../../sim
iverilog -o tb_soc.vvp -I ../rtl/core -I ../rtl/mem -I ../rtl \
    tb_soc.v ../rtl/core/*.v ../rtl/mem/*.v ../rtl/soc_top.v ../rtl/periph/*.v
vvp tb_soc.vvp
# Expected: 22 PASS, 0 FAIL
```

### Vivado Simulation

```bash
cd fpga/scripts
vivado -mode batch -source simulate.tcl
```

### View Waveforms

```bash
gtkwave sim/wave.vcd &
```

## Test Coverage (22 tests)

### tb_soc — Full SoC Test

| Category | # | Tests |
|----------|---|-------|
| GPIO | 2 | Output readback, input loopback |
| UART | 1 | TX/RX loopback (0x55 at 115200 baud) |
| RV32I Basic | 3 | OR, XOR, LUI |
| RV32I Extended | 5 | SLT, SLTU, SRL, SRA, SRLI |
| RV32M | 3 | REM, DIVU, REMU |
| Timer IRQ | 1 | Interrupt handler execution (mtimecmp → trap → mret) |
| SPI | 2 | MOSI→MISO loopback (0xA5), rx_valid status |
| PWM | 2 | PERIOD readback, CTRL readback |
| PLIC | 3 | ENABLE readback, THRESHOLD readback, PENDING=0 |

### tb_rv32i_ext — Extended RV32I (13 tests)

| Category | Tests |
|----------|-------|
| Shift | SLL, SRL, SRA |
| Compare | SLT (signed), SLTU (unsigned) |
| AUIPC/JALR | PC-relative addressing, indirect jump |
| Load/Store | LH, LHU, LB, LBU, LW, SH, SB |
| Branch | BLT, BGE, BLTU, BGEU (taken + not-taken) |

## Key Design Decisions

1. **Branch predictor**: 2-bit saturating counter BHT (64 entries) + BTB. Predicts in IF stage using instruction opcode directly. Updated in ID stage after branch resolution. Reduces branch penalty from 1 cycle to 0 for correctly predicted branches.

2. **SPI CPOL/CPHA handling**: The SPI master supports all four CPOL/CPHA combinations. Sampling vs shifting is determined by `(!spi_clk_internal ^ cpol) ^ cpha` — when true, sample MISO; when false, shift out next bit.

3. **CSR forwarding via separate EX-stage read port**: CSR read address arrives from WB stage (1 cycle behind EX), so a dedicated `fwd_addr`/`fwd_rdata` port reads CSR values combinationally in EX stage.

4. **`memwb_reg_wr` for forwarding during traps**: `wb_we` is suppressed by `!irq_trap` during trap entry, but load results must still forward. Using `memwb_reg_wr` ensures correct forwarding.

5. **Iterative divider with 2-cycle freeze**: The 32-cycle shift-subtract divider freezes the entire pipeline. After `div_done`, a 2-cycle freeze counter holds EX/MEM so the result propagates before the bubble overwrites it.

## Target FPGA

- **Device**: Xilinx Artix-7 XC7A35T
- **Tool**: Vivado
- **Resources**: ~33K LUT, 200KB BRAM
- **Clock**: 100 MHz (default)

## Author

深圳技术大学 · 电子科学与技术 · 大二
