/*
 * RISC-V startup code for FreeRTOS
 * Sets up stack pointer and jumps to main
 */

    .section .text
    .align 2
    .global _start
    .global freertos_risc_v_trap_handler

_start:
    /* Set up stack pointer (top of RAM) */
    la   sp, _stack_top

    /* Clear BSS section */
    la   t0, __bss_start
    la   t1, __bss_end
clear_bss:
    bge  t0, t1, bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    clear_bss
bss_done:

    /* Set trap handler */
    la   t0, freertos_risc_v_trap_handler
    csrw mtvec, t0

    /* Jump to main */
    jal  ra, main

    /* If main returns, loop forever */
hang:
    j    hang
