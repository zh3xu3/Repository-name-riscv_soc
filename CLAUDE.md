# RISC-V SoC on FPGA - 项目提示词

## 项目概述

在 Xilinx Artix-7 XC7A35T 开发板上，用 Verilog 从零实现一个 RISC-V RV32I 软核处理器，最终跑上 FreeRTOS，展示软硬协同设计能力。目标是简历项目，用于 IC/验证/嵌入式方向实习。

## 技术栈

- 语言：Verilog（不要用 SystemVerilog，综合兼容性好）
- 仿真：iverilog + GTKWave（先仿真验证，再上板）
- 综合：Vivado（上板阶段）
- 目标板：XC7A35T（33K LUT，200KB BRAM，够用）
- RTOS：FreeRTOS（RV32 移植层）

## 架构设计

### 处理器内核：单周期 → 流水线 渐进式

**Phase 1 - 单周期 RV32I**（已完成）
- 37 条基础指令：算术/逻辑/分支/访存/跳转
- 五模块：ALU、寄存器堆、立即数生成、控制单元、分支比较器
- 哈佛架构：指令存储器 + 数据存储器（Block RAM）
- 目标：仿真通过，能跑简单 C 程序

**Phase 2 - 五级流水线**
- IF/ID/EX/MEM/WB 五级
- 数据冒险：forwarding unit + stall（load-use hazard）
- 控制冒险：always-not-taken 分支预测
- 验证：Dhrystone/CoreMark benchmark

**Phase 3 - M 扩展 + 中断**
- 乘法器（MUL/MULH/DIV/REM）
- CLINT 定时器 + 中断控制器
- CSR 寄存器：mtvec/mepc/mcause/mstatus
- 验证：定时器中断触发

**Phase 4 - 外设 + 总线**
- 简单总线（类 AHB-Lite）+ 地址译码
- UART（串口 TX/RX，115200 baud）
- GPIO（32-bit 双向）
- SPI Master（支持 CPOL/CPHA 配置）
- PWM（4 通道，周期/占空比可配）
- PLIC（16 中断源，优先级/阈值）
- WDT（看门狗定时器）

**Phase 5 - FreeRTOS 移植**
- 移植 FreeRTOS RV32 port
- 实现上下文切换（保存/恢复 32 个寄存器 + CSR）
- demo：多任务 LED 闪烁 + 串口输出 + 队列通信

## 目录结构

```
riscv_soc/
├── CLAUDE.md              # 本文件 - 项目提示词
├── rtl/
│   ├── core/
│   │   ├── alu.v          # ALU
│   │   ├── reg_file.v     # 32x32 寄存器堆
│   │   ├── imm_gen.v      # 立即数生成
│   │   ├── control.v      # 控制单元（指令解码）
│   │   ├── branch_comp.v  # 分支比较器
│   │   ├── branch_pred.v  # 分支预测器 (2-bit BHT + BTB)
│   │   ├── csr.v          # CSR + CLINT 定时器
│   │   ├── divider.v      # 迭代除法器 (32 周期)
│   │   └── riscv_core.v   # 顶层核心（5 级流水线 + forwarding）
│   ├── mem/
│   │   ├── inst_mem.v     # 指令存储器
│   │   └── data_mem.v     # 数据存储器
│   ├── periph/
│   │   ├── gpio.v         # GPIO (32-bit in/out)
│   │   ├── uart.v         # UART 顶层
│   │   ├── uart_tx.v      # UART 发送
│   │   ├── uart_rx.v      # UART 接收
│   │   ├── spi.v          # SPI Master (CPOL/CPHA)
│   │   ├── pwm.v          # PWM (4 通道)
│   │   ├── plic.v         # PLIC (16 中断源)
│   │   └── wdt.v          # 看门狗
│   └── soc_top.v          # SoC 顶层（地址译码总线）
├── sim/
│   ├── tb_soc.v           # 仿真 testbench (22 tests)
│   ├── tb_rv32i_ext.v     # 扩展 RV32I testbench (13 tests)
│   └── Makefile           # 仿真脚本
├── tests/
│   └── sw/
│       ├── gen_uart_gpio.py   # 主测试生成器 (22 tests)
│       ├── gen_hex.py         # Phase 1+2+3 测试
│       └── gen_rv32i_ext.py   # 扩展 RV32I 测试
├── freertos/              # FreeRTOS RV32 移植
└── fpga/
    ├── fpga_top.v         # FPGA 顶层
    ├── constraints/       # 引脚约束
    └── scripts/           # Vivado TCL 脚本
```

## 编码规范

- 模块名：snake_case（如 `riscv_core`）
- 信号名：snake_case（如 `rs1_data`）
- 参数：UPPER_CASE（如 `MEM_SIZE`）
- 每个模块头部简短注释说明功能
- 端口声明统一用 `input wire` / `output wire` / `output reg`

## RV32I 指令编码参考

| 类型 | opcode   | 格式      | 示例指令           |
|------|----------|-----------|--------------------|
| R    | 0110011  | funct7+rs2+rs1+funct3+rd | ADD, SUB, AND, OR  |
| I    | 0010011  | imm[11:0]+rs1+funct3+rd  | ADDI, ANDI, SLLI   |
| Load | 0000011  | imm[11:0]+rs1+funct3+rd  | LW, LH, LB        |
| S    | 0100011  | imm[11:5]+rs2+rs1+funct3+imm[4:0] | SW, SH, SB |
| B    | 1100011  | imm[12\|10:5]+rs2+rs1+funct3+imm[4:1\|11] | BEQ, BNE |
| U    | 0110111  | imm[31:12]+rd            | LUI, AUIPC         |
| J    | 1101111  | imm[20\|10:1\|11\|19:12]+rd | JAL              |

## ALU 操作编码（内部）

```
{funct7[5], funct3}:
0000 = ADD    0100 = SUB
0001 = SLL    0010 = SLT
0011 = SLTU   0101 = XOR
0110 = SRL    1110 = SRA
0111 = OR     1000 = AND
```

## 仿真验证方法

```bash
# 生成测试程序
cd tests/sw && python gen_uart_gpio.py && cp inst_mem.hex ../../sim/

# 编译 (iverilog)
cd ../../sim
iverilog -o tb_soc.vvp -I ../rtl/core -I ../rtl/mem -I ../rtl \
    tb_soc.v ../rtl/core/*.v ../rtl/mem/*.v ../rtl/soc_top.v ../rtl/periph/*.v

# 运行
vvp tb_soc.vvp
# 预期：22 PASS, 0 FAIL

# 查看波形
gtkwave wave.vcd
```

## 测试程序说明

`tests/sw/gen_uart_gpio.py` 生成主测试 (22 tests)：
1. GPIO 输出/输入回环 (2)
2. UART TX/RX 回环 (1)
3. RV32I 基础：OR, XOR, LUI (3)
4. RV32I 扩展：SLT, SLTU, SRL, SRA, SRLI (5)
5. RV32M：REM, DIVU, REMU (3)
6. 定时器中断处理 (1)
7. SPI MOSI→MISO 回环 + rx_valid (2)
8. PWM PERIOD/CTRL 寄存器读回 (2)
9. PLIC ENABLE/THRESHOLD/PENDING 读回 (3)

预期结果（testbench 中验证）：
- GPIO: readback=0xABCD1234, loopback=0xABCD1234
- UART: RX=0x55 (TX→RX 回环)
- RV32I: x1=1(SLT), x2=0(SLTU), x3=16(SRL), x4=-1(SRA), x5=0(SRLI)
- RV32M: x12=42(REM), x13=1(DIVU), x14=42(REMU)
- Timer: x15=1 (中断处理执行)
- SPI: RX=0xA5, STATUS[1]=1 (rx_valid)
- PWM: PERIOD=3, CTRL=0x51
- PLIC: ENABLE=0xFF, THRESHOLD=5, PENDING=0

## 已完成

- [x] Phase 1: 单周期 RV32I（12/12 测试 PASS）
- [x] Phase 2: 五级流水线 + 冒险处理（12/12 测试 PASS）
- [x] Phase 3: M 扩展 + 中断（MUL/DIV/REM + CLINT 定时器 + MRET）
- [x] Phase 4: 外设 + 总线（UART + GPIO + 地址译码，18/18 测试 PASS）
- [x] Phase 5: FreeRTOS 移植（2/2 测试 PASS）
- [x] Phase 5.5: 扩展 RV32I 验证（13/13 测试 PASS）
- [x] Phase 6: SPI/PWM/PLIC 外设 + 22/22 测试 PASS
- [x] Phase 7: 分支预测器 (2-bit BHT + BTB) + SPI CPHA 修复
- [ ] Phase 8: Vivado 综合 + 上板验证

## 当前进度

Phase 7 完成。22/22 测试全部通过：
- GPIO (2), UART (1), RV32I Basic (3), RV32I Extended (5)
- RV32M (3), Timer IRQ (1), SPI (2), PWM (2), PLIC (3)

下一步：Phase 8 - Vivado 综合 + 板级验证
