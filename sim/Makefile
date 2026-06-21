# RISC-V SoC Simulation Makefile
# Usage:
#   make hex    - generate inst_mem.hex from Python
#   make sim    - compile and run simulation
#   make wave   - open waveform viewer
#   make all    - hex + sim
#   make clean  - remove build artifacts

TOP     = tb_soc
OUT     = out
WAVE    = wave.vcd
HEX_SRC = ../tests/sw/gen_uart_gpio.py
HEX_DST = inst_mem.hex

RTL_DIR = ../rtl
SRCS    = $(RTL_DIR)/core/alu.v \
          $(RTL_DIR)/core/reg_file.v \
          $(RTL_DIR)/core/imm_gen.v \
          $(RTL_DIR)/core/control.v \
          $(RTL_DIR)/core/branch_comp.v \
          $(RTL_DIR)/core/divider.v \
          $(RTL_DIR)/core/csr.v \
          $(RTL_DIR)/core/riscv_core.v \
          $(RTL_DIR)/mem/inst_mem.v \
          $(RTL_DIR)/mem/data_mem.v \
          $(RTL_DIR)/periph/uart_tx.v \
          $(RTL_DIR)/periph/uart_rx.v \
          $(RTL_DIR)/periph/uart.v \
          $(RTL_DIR)/periph/gpio.v \
          $(RTL_DIR)/soc_top.v \
          tb_soc.v

.PHONY: all sim wave clean hex

all: hex sim

hex:
	python3 $(HEX_SRC)
	cp ../tests/sw/inst_mem.hex .

sim: $(HEX_DST)
	iverilog -o $(OUT) $(SRCS)
	vvp $(OUT)

wave:
	gtkwave $(WAVE) &

$(HEX_DST):
	$(MAKE) hex

clean:
	rm -f $(OUT) $(WAVE) $(HEX_DST)
