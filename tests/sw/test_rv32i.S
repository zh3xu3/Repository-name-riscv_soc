# RV32I Test Program - Clean version
# Expected results in comments
# All instructions are 4 bytes, word-aligned

# addr 0x00: I-type arithmetic
00: addi x1, x0, 42         # x1 = 42
04: addi x2, x0, 58         # x2 = 58
08: addi x5, x0, 255        # x5 = 0xFF
0c: addi x6, x0, 15         # x6 = 0x0F

# addr 0x10: R-type arithmetic
10: add  x3, x1, x2         # x3 = 100
14: sub  x4, x3, x1         # x4 = 58
18: and  x5, x5, x6         # x5 = 0x0F
1c: or   x6, x5, x6         # x6 = 0x0F (0x0F | 0x0F)

# addr 0x20: More R-type
20: addi x7, x0, 0rPid       # x7 = -1 (0xFFFFFFFF)
24: xor  x7, x7, x6         # x7 = 0xFFFFFFF0
28: addi x8, x0, 1
2c: sll  x8, x8, x6         # x8 = 1 << 15 = 0x8000

# addr 0x30: LUI + memory
30: lui  x8, 0x12345         # x8 = 0x12345000
34: addi x12, x0, 64         # x12 = 64 (address)
38: sw   x8, 0(x12)          # MEM[64] = 0x12345000
3c: lw   x14, 0(x12)         # x14 = 0x12345000

# addr 0x40: Branch
40: addi x15, x0, 0          # x15 = 0
44: beq  x1, x1, 8           # branch to 0x4C (PC+8)
48: addi x15, x0, 99         # skipped
4c: addi x15, x0, 1          # x15 = 1

# addr 0x50: BNE
50: bne  x1, x2, 8           # 42 != 58, branch to 0x58
54: addi x15, x0, 99         # skipped
58: addi x15, x0, 2          # x15 = 2

# addr 0x5C: JAL
5c: jal  x1, 8               # x1 = PC+4, jump to 0x64
60: addi x15, x0, 99         # skipped
64: addi x15, x0, 3          # x15 = 3

# addr 0x68: halt
68: jal  x0, 0               # infinite loop
