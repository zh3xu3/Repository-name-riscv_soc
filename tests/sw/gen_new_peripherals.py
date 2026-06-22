#!/usr/bin/env python3
"""
Generate test program for new peripherals: DMA, I-Cache, I2C
"""

import struct

# RISC-V instruction encodings
def lui(rd, imm):
    """Load Upper Immediate"""
    return (imm << 12) | (rd << 7) | 0x37

def addi(rd, rs1, imm):
    """Add Immediate"""
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13

def sw(rs2, rs1, imm):
    """Store Word"""
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (imm4_0 << 7) | 0x23

def lw(rd, rs1, imm):
    """Load Word"""
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | 0x03

def nop():
    """No operation"""
    return addi(0, 0, 0)

def ebreak():
    """Environment break (stop simulation)"""
    return 0x00100073

# Memory map
DMA_BASE    = 0x00008000
ICACHE_BASE = 0x00009000
I2C_BASE    = 0x0000A000

# DMA registers
DMA_CTRL     = 0x00
DMA_SRC_ADDR = 0x04
DMA_DST_ADDR = 0x08
DMA_TRANS_LEN = 0x0C
DMA_STATUS   = 0x10

# I-Cache registers
ICACHE_CTRL  = 0x00
ICACHE_STATUS = 0x04
ICACHE_HIT   = 0x08
ICACHE_MISS  = 0x0C

# I2C registers
I2C_CTRL     = 0x00
I2C_STATUS   = 0x04
I2C_DATA     = 0x08
I2C_ADDR     = 0x0C

instructions = []

# Start: initialize registers
instructions.append(lui(1, 0))      # x1 = 0 (test counter)
instructions.append(lui(2, 0))      # x2 = 0 (pass counter)

# ==========================================
# Test 1: I-Cache Enable/Disable
# ==========================================
print("Test 1: I-Cache Enable/Disable")

# Load I-Cache base address
instructions.append(lui(3, ICACHE_BASE >> 12))
instructions.append(addi(3, 3, ICACHE_BASE & 0xFFF))

# Enable cache (write 1 to CTRL)
instructions.append(addi(4, 0, 1))
instructions.append(sw(4, 3, ICACHE_CTRL))

# Read STATUS to verify
instructions.append(lw(5, 3, ICACHE_STATUS))

# Disable cache (write 0 to CTRL)
instructions.append(addi(4, 0, 0))
instructions.append(sw(4, 3, ICACHE_CTRL))

# ==========================================
# Test 2: DMA Memory-to-Memory Transfer
# ==========================================
print("Test 2: DMA Memory-to-Memory")

# Load DMA base address
instructions.append(lui(3, DMA_BASE >> 12))
instructions.append(addi(3, 3, DMA_BASE & 0xFFF))

# Set source address (0x1000 - data memory)
instructions.append(lui(4, 0x1000 >> 12))
instructions.append(sw(4, 3, DMA_SRC_ADDR))

# Set destination address (0x1100)
instructions.append(lui(4, 0x1100 >> 12))
instructions.append(sw(4, 3, DMA_DST_ADDR))

# Set transfer length (16 bytes)
instructions.append(addi(4, 0, 16))
instructions.append(sw(4, 3, DMA_TRANS_LEN))

# Start DMA (CTRL = 1)
instructions.append(addi(4, 0, 1))
instructions.append(sw(4, 3, DMA_CTRL))

# Wait for DMA to complete (poll STATUS)
# In real test, would loop here

# ==========================================
# Test 3: I2C Write Operation
# ==========================================
print("Test 3: I2C Write")

# Load I2C base address
instructions.append(lui(3, I2C_BASE >> 12))
instructions.append(addi(3, 3, I2C_BASE & 0xFFF))

# Set slave address (0x50, write mode)
instructions.append(addi(4, 0, 0x50))
instructions.append(sw(4, 3, I2C_ADDR))

# Write data to TX FIFO
instructions.append(addi(4, 0, 0xAA))
instructions.append(sw(4, 3, I2C_DATA))

# Start transfer (CTRL = 0x05: enable + start)
instructions.append(addi(4, 0, 0x05))
instructions.append(sw(4, 3, I2C_CTRL))

# ==========================================
# End: Write results to GPIO for observation
# ==========================================
print("Writing results to GPIO...")

# Load GPIO base address
instructions.append(lui(3, 0x3000 >> 12))
instructions.append(addi(3, 3, 0x3000 & 0xFFF))

# Write test pattern to GPIO
instructions.append(lui(4, 0xABCD >> 12))
instructions.append(addi(4, 4, 0xABCD & 0xFFF))
instructions.append(sw(4, 3, 0))

# EBREAK to stop simulation
instructions.append(ebreak())

# Generate hex file
with open("inst_mem.hex", "w") as f:
    for i, inst in enumerate(instructions):
        f.write(f"{inst:08x}\n")

print(f"Generated {len(instructions)} instructions")
print(f"Address range: 0x000 - 0x{(len(instructions)-1)*4:03x}")
print("inst_mem.hex written")
