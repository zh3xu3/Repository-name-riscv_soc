/*
 * Linker script for RISC-V RV32IM SoC with FreeRTOS
 *
 * Memory map (matches soc_top.v):
 *   IMEM: 0x0000_0000, 4KB  (inst_mem)
 *   DMEM: 0x0000_1000, 4KB  (data_mem, base=0x1000, internal offset)
 *   UART: 0x0000_2000       (peripheral)
 *   GPIO: 0x0000_3000       (peripheral)
 */

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM (rwx) : ORIGIN = 0x00001000, LENGTH = 4K
}

ENTRY(_start)

SECTIONS
{
    /* Code in instruction memory - startup MUST be first */
    .text : {
        KEEP(*(.text.startup))
        *(.text*)
        *(.rodata*)
    } > IMEM

    /* Data - zero-initialized (startup clears BSS, no .data load needed) */
    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON*)
        __bss_end = .;
    } > DMEM

    /* Heap - after BSS (startup stack space, heap_4 uses ucHeap in BSS) */
    .heap (NOLOAD) : {
        . = ALIGN(8);
        __heap_start = .;
        . += 1K;           /* 1KB startup stack */
        __heap_end = .;
    } > DMEM

    /* Stack - top of DMEM (startup stack, then each task uses its own) */
    .stack (NOLOAD) : {
        . = ALIGN(16);
        _stack_top = .;
    } > DMEM
}
