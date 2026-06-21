# FreeRTOS RISC-V Build Makefile
# Builds a bare-metal FreeRTOS application for the RV32IM SoC

# Toolchain
CROSS   = riscv-none-elf-
CC      = $(CROSS)gcc
AS      = $(CROSS)gcc
LD      = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump
SIZE    = $(CROSS)size

# Directories
FRTOS   = FreeRTOS/Source
APP     = app
BUILD   = build

# Source files
CSRCS   = $(APP)/main.c \
          $(FRTOS)/tasks.c \
          $(FRTOS)/list.c \
          $(FRTOS)/portable/GCC/RISC-V/port.c \
          $(FRTOS)/portable/MemMang/heap_4.c

ASRCS   = $(APP)/startup.S \
          $(FRTOS)/portable/GCC/RISC-V/portASM.S

# Include paths (app/ first so FreeRTOSConfig.h is found before kernel headers)
CINCS   = -I$(APP) \
          -I$(FRTOS)/include \
          -I$(FRTOS)/portable/GCC/RISC-V

# Linker script
LDSCRIPT = $(APP)/linker.ld

# Compiler flags (RV32IM, no compressed, bare-metal)
CFLAGS  = -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany \
          -Wall -Wextra -Os \
          -ffunction-sections -fdata-sections \
          -fno-builtin -ffreestanding \
          $(CINCS)

ASFLAGS = -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany \
          $(CINCS)

LDFLAGS = -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany \
          -T$(LDSCRIPT) -nostartfiles \
          -Wl,--gc-sections \
          -Wl,-Map=$(BUILD)/freertos.map

# Object files
COBJS   = $(patsubst %.c,$(BUILD)/%.o,$(CSRCS))
ASOBJS  = $(patsubst %.S,$(BUILD)/%.o,$(ASRCS))
OBJS    = $(COBJS) $(ASOBJS)

# Output
ELF     = $(BUILD)/freertos.elf
HEX     = inst_mem.hex
VERILOG_HEX = build/freertos.verilog.hex

.PHONY: all clean disasm

all: $(HEX)
	@echo "Build complete: $(HEX)"

$(HEX): $(ELF)
	$(OBJCOPY) -O verilog $< $(VERILOG_HEX)
	python3 convert_hex.py $(VERILOG_HEX) $@ 1024
	@echo "Generated $@"

$(ELF): $(OBJS)
	@mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ build/app/startup.o $(filter-out build/app/startup.o,$^)
	$(SIZE) $@

$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/%.o: %.S
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -c -o $@ $<

disasm: $(ELF)
	$(OBJDUMP) -d $< > $(BUILD)/freertos.dis
	@echo "Disassembly: $(BUILD)/freertos.dis"

clean:
	rm -rf $(BUILD) $(HEX)
