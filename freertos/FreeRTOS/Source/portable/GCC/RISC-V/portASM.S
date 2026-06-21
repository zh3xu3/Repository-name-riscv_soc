/*
 * FreeRTOS RISC-V port - Assembly trap handler
 * Handles context save/restore for task switching
 *
 * Context frame layout (MUST match xPortStartScheduler):
 *   offset 0:   mepc
 *   offset 4:   x1/ra
 *   offset 8:   x2/sp
 *   offset 12:  x3/gp
 *   offset 16:  x4/tp
 *   offset 20:  x5/t0
 *   offset 24:  x6/t1
 *   offset 28:  x7/t2
 *   offset 32:  x8/s0
 *   offset 36:  x9/s1
 *   offset 40:  x10/a0
 *   offset 44:  x11/a1
 *   offset 48:  x12/a2
 *   offset 52:  x13/a3
 *   offset 56:  x14/a4
 *   offset 60:  x15/a5
 *   offset 64:  x16/a6
 *   offset 68:  x17/a7
 *   offset 72:  x18/s2
 *   offset 76:  x19/s3
 *   offset 80:  x20/s4
 *   offset 84:  x21/s5
 *   offset 88:  x22/s6
 *   offset 92:  x23/s7
 *   offset 96:  x24/s8
 *   offset 100: x25/s9
 *   offset 104: x26/s10
 *   offset 108: x27/s11
 *   offset 112: x28/t3
 *   offset 116: x29/t4
 *   offset 120: x30/t5
 *   offset 124: x31/t6
 */

    .section .text
    .align 2
    .global freertos_risc_v_trap_handler
    .global freertos_risc_v_mepc_get
    .global freertos_risc_v_mepc_set

/*-----------------------------------------------------------
 * Trap entry point - called on ANY trap (IRQ, ecall, exception)
 * Hardware has already: saved mepc, set mcause, cleared MIE
 * We must: save all 32 GPRs + mepc, then dispatch
 *-----------------------------------------------------------*/
freertos_risc_v_trap_handler:
    /* Allocate stack frame: mepc + 32 regs = 33 * 4 = 132 bytes */
    addi sp, sp, -132

    /* Save mepc at offset 0 (must match xPortStartScheduler layout) */
    csrr t0, mepc
    sw   t0, 0(sp)

    /* Save registers at offsets matching xPortStartScheduler's layout */
    sw   x1,  4(sp)           /* x1/ra  at offset 4   */
    sw   x5,  20(sp)          /* x5/t0  at offset 20 (save BEFORE overwriting t0) */
    addi t0, sp, 132          /* t0 = original sp before frame allocation */
    sw   t0,  8(sp)           /* x2/sp  at offset 8   */
    sw   x3,  12(sp)          /* x3/gp  at offset 12  */
    sw   x4,  16(sp)          /* x4/tp  at offset 16  */
    sw   x6,  24(sp)          /* x6/t1  at offset 24  */
    sw   x7,  28(sp)          /* x7/t2  at offset 28  */
    sw   x8,  32(sp)          /* x8/s0  at offset 32  */
    sw   x9,  36(sp)          /* x9/s1  at offset 36  */
    sw   x10, 40(sp)          /* x10/a0 at offset 40  */
    sw   x11, 44(sp)          /* x11/a1 at offset 44  */
    sw   x12, 48(sp)          /* x12/a2 at offset 48  */
    sw   x13, 52(sp)          /* x13/a3 at offset 52  */
    sw   x14, 56(sp)          /* x14/a4 at offset 56  */
    sw   x15, 60(sp)          /* x15/a5 at offset 60  */
    sw   x16, 64(sp)          /* x16/a6 at offset 64  */
    sw   x17, 68(sp)          /* x17/a7 at offset 68  */
    sw   x18, 72(sp)          /* x18/s2 at offset 72  */
    sw   x19, 76(sp)          /* x19/s3 at offset 76  */
    sw   x20, 80(sp)          /* x20/s4 at offset 80  */
    sw   x21, 84(sp)          /* x21/s5 at offset 84  */
    sw   x22, 88(sp)          /* x22/s6 at offset 88  */
    sw   x23, 92(sp)          /* x23/s7 at offset 92  */
    sw   x24, 96(sp)          /* x24/s8 at offset 96  */
    sw   x25, 100(sp)         /* x25/s9 at offset 100 */
    sw   x26, 104(sp)         /* x26/s10 at offset 104 */
    sw   x27, 108(sp)         /* x27/s11 at offset 108 */
    sw   x28, 112(sp)         /* x28/t3 at offset 112 */
    sw   x29, 116(sp)         /* x29/t4 at offset 116 */
    sw   x30, 120(sp)         /* x30/t5 at offset 120 */
    sw   x31, 124(sp)         /* x31/t6 at offset 124 */

    /* Call C trap handler: BaseType_t *vTaskTrapHandler(UBaseType_t *sp, UBaseType_t mcause) */
    mv   a0, sp               /* a0 = pointer to saved context */
    csrr a1, mcause           /* a1 = mcause */
    jal  ra, vTaskTrapHandler

    /* a0 = pointer to context to restore (same or different task).
     * a0 is preserved by vTaskTrapHandler (verified in disassembly). */

    /* Restore mepc from context[0] and write to CSR */
    lw   t0, 0(a0)
    nop                 /* Pipeline bubble: allows lw result to reach WB for forwarding to csrw */
    csrw mepc, t0

    /* Restore sp FIRST: original sp = context pointer + 132.
     * After this, sp = task's original stack pointer.
     * Context frame is at sp - 132. */
    addi sp, a0, 132

    /* Restore all registers from context frame via sp-relative negative offsets.
     * Context frame layout: mepc(0), ra(4), sp(8), gp(12), tp(16), t0(20),
     *   t1(24), t2(28), s0(32), s1(36), a0(40), a1(44), ..., t6(124).
     * Offsets from sp: context[i] = sp - 132 + i*4. */
    lw   x1,  -128(sp)        /* x1/ra  at context+4  */
    lw   x3,  -120(sp)        /* x3/gp  at context+12 */
    lw   x4,  -116(sp)        /* x4/tp  at context+16 */
    lw   x5,  -112(sp)        /* x5/t0  at context+20 */
    lw   x6,  -108(sp)        /* x6/t1  at context+24 */
    lw   x7,  -104(sp)        /* x7/t2  at context+28 */
    lw   x8,  -100(sp)        /* x8/s0  at context+32 */
    lw   x9,  -96(sp)         /* x9/s1  at context+36 */
    lw   x10, -92(sp)         /* x10/a0 at context+40 */
    lw   x11, -88(sp)         /* x11/a1 at context+44 */
    lw   x12, -84(sp)         /* x12/a2 at context+48 */
    lw   x13, -80(sp)         /* x13/a3 at context+52 */
    lw   x14, -76(sp)         /* x14/a4 at context+56 */
    lw   x15, -72(sp)         /* x15/a5 at context+60 */
    lw   x16, -68(sp)         /* x16/a6 at context+64 */
    lw   x17, -64(sp)         /* x17/a7 at context+68 */
    lw   x18, -60(sp)         /* x18/s2 at context+72 */
    lw   x19, -56(sp)         /* x19/s3 at context+76 */
    lw   x20, -52(sp)         /* x20/s4 at context+80 */
    lw   x21, -48(sp)         /* x21/s5 at context+84 */
    lw   x22, -44(sp)         /* x22/s6 at context+88 */
    lw   x23, -40(sp)         /* x23/s7 at context+92 */
    lw   x24, -36(sp)         /* x24/s8 at context+96 */
    lw   x25, -32(sp)         /* x25/s9 at context+100 */
    lw   x26, -28(sp)         /* x26/s10 at context+104 */
    lw   x27, -24(sp)         /* x27/s11 at context+108 */
    lw   x28, -20(sp)         /* x28/t3 at context+112 */
    lw   x29, -16(sp)         /* x29/t4 at context+116 */
    lw   x30, -12(sp)         /* x30/t5 at context+120 */
    lw   x31, -8(sp)          /* x31/t6 at context+124 */

    /* Return from trap */
    mret

/*-----------------------------------------------------------
 * Helper: get mepc value
 *-----------------------------------------------------------*/
freertos_risc_v_mepc_get:
    csrr a0, mepc
    ret

/*-----------------------------------------------------------
 * Helper: set mepc value
 *-----------------------------------------------------------*/
freertos_risc_v_mepc_set:
    csrw mepc, a0
    ret
