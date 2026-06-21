# FreeRTOS Simulation Makefile
TOP     = tb_freertos
OUT     = out_freertos
WAVE    = wave_freertos.vcd

RTL_DIR = ../../rtl
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
          tb_freertos.v

.PHONY: all sim wave clean

all: sim

sim: inst_mem.hex
	iverilog -o $(OUT) $(SRCS)
	vvp $(OUT)

wave:
	gtkwave $(WAVE) &

clean:
	rm -f $(OUT) $(WAVE)
