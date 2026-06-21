/*
 * FreeRTOS RISC-V port for RV32IM soft-core
 * Supports: timer interrupt, ecall yield, full context save/restore
 */
#include "FreeRTOS.h"
#include "task.h"

/* CSR addresses */
#define CSR_MSTATUS     0x300
#define CSR_MIE         0x304
#define CSR_MTVEC       0x305
#define CSR_MEPC        0x341

/* mstatus bits */
#define MSTATUS_MIE     (1 << 3)

/* Timer cycles per tick */
#define TICK_CYCLES      (configCPU_CLOCK_HZ / configTICK_RATE_HZ)

/* External references */
extern void freertos_risc_v_trap_handler(void);

/* TCB type (must match tasks.c) */
typedef struct tskTaskControlBlock {
    volatile StackType_t *pxTopOfStack;  /* Must be first member */
} tskTCB;

extern volatile tskTCB * volatile pxCurrentTCB;

/*-----------------------------------------------------------
 * CSR helpers
 *-----------------------------------------------------------*/
static inline uint32_t csr_read_mepc(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mepc" : "=r"(val));
    return val;
}

static inline void csr_write_mepc(uint32_t val) {
    __asm__ volatile ("csrw mepc, %0" :: "r"(val));
}

/*-----------------------------------------------------------
 * Setup the timer for the tick interrupt.
 * Uses CSR-based CLINT (mtime/mtimecmp) accessed via CSRR/CSRW.
 *-----------------------------------------------------------*/
void vPortSetupTimerInterrupt(void) {
    /* mtimecmp CSR: 0xB02 (lo), 0xB03 (hi) */
    /* mtime CSR: 0xC01 (lo) */
    uint32_t now;
    __asm__ volatile ("csrr %0, 0xC01" : "=r"(now));
    uint32_t next = now + TICK_CYCLES;
    __asm__ volatile ("csrw 0xB02, %0" :: "r"(next));
    uint32_t zero = 0;
    __asm__ volatile ("csrw 0xB03, %0" :: "r"(zero));

    /* Enable timer interrupt in mie.MTIE (bit 7) */
    __asm__ volatile ("csrs 0x304, %0" :: "r"(1 << 7));
}

/*-----------------------------------------------------------
 * Initialize the stack of a new task.
 *
 * Creates a stack frame that looks like a saved interrupt context.
 * Layout (32 words = 128 bytes):
 *   [0]  = mepc (task entry point)
 *   [1]  = x1/ra
 *   [2]  = x2/sp (not used, sp is the frame pointer itself)
 *   [3]  = x3/gp
 *   ...
 *   [10] = x10/a0 (task parameter)
 *   ...
 *   [31] = x31/t6
 *-----------------------------------------------------------*/
StackType_t *pxPortInitialiseStack(StackType_t *pxTopOfStack,
                                   TaskFunction_t pxCode,
                                   void *pvParameters) {
    /* Align to 16 bytes */
    pxTopOfStack = (StackType_t *)((uint32_t)pxTopOfStack & ~0xF);

    /* Allocate context frame: mepc + 32 GPRs = 33 words (stack grows downward) */
    pxTopOfStack -= 33;

    /* Zero the entire context frame (132 bytes).
     * This is safe because xTaskCreate allocates usStackDepth+36 words,
     * reserving space below the usable stack for this frame. */
    for (int i = 0; i < 33; i++) {
        pxTopOfStack[i] = 0;
    }

    /* [0] mepc = task entry point */
    pxTopOfStack[0] = (StackType_t)pxCode;

    /* [2] x2/sp = context frame address (task starts with valid sp) */
    pxTopOfStack[2] = (StackType_t)pxTopOfStack;

    /* [10] x10/a0 = task parameter */
    pxTopOfStack[10] = (StackType_t)pvParameters;

    return pxTopOfStack;
}

/*-----------------------------------------------------------
 * Start the scheduler - restore first task context and jump to it.
 *-----------------------------------------------------------*/
BaseType_t xPortStartScheduler(void) {
    /* Set trap handler */
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uint32_t)freertos_risc_v_trap_handler));

    /* Setup tick timer */
    vPortSetupTimerInterrupt();

    /* DO NOT enable MIE here — a timer interrupt before the first task's
     * context is loaded would corrupt state (pxCurrentTCB deref inside
     * vTaskTrapHandler with an incomplete context frame).
     * Instead, MIE is enabled right before mret, after all registers
     * are loaded from the valid context frame. */

    /* Get first task's context pointer */
    volatile StackType_t *pxCtx = pxCurrentTCB->pxTopOfStack;

    /* Set mepc to task entry point */
    csr_write_mepc(pxCtx[0]);

    /* Restore registers, enable MIE, and jump to task.
     * If a timer fires between csrs and mret, the trap handler
     * has a fully valid pxCurrentTCB and context frame, so it
     * will save/restore correctly. */
    __asm__ volatile (
        "mv   sp, %0\n"
        "lw   x1,  1 * 4(sp)\n"
        "lw   x3,  3 * 4(sp)\n"
        "lw   x4,  4 * 4(sp)\n"
        "lw   x5,  5 * 4(sp)\n"
        "lw   x6,  6 * 4(sp)\n"
        "lw   x7,  7 * 4(sp)\n"
        "lw   x8,  8 * 4(sp)\n"
        "lw   x9,  9 * 4(sp)\n"
        "lw   x10, 10 * 4(sp)\n"
        "lw   x11, 11 * 4(sp)\n"
        "lw   x12, 12 * 4(sp)\n"
        "lw   x13, 13 * 4(sp)\n"
        "lw   x14, 14 * 4(sp)\n"
        "lw   x15, 15 * 4(sp)\n"
        "lw   x16, 16 * 4(sp)\n"
        "lw   x17, 17 * 4(sp)\n"
        "lw   x18, 18 * 4(sp)\n"
        "lw   x19, 19 * 4(sp)\n"
        "lw   x20, 20 * 4(sp)\n"
        "lw   x21, 21 * 4(sp)\n"
        "lw   x22, 22 * 4(sp)\n"
        "lw   x23, 23 * 4(sp)\n"
        "lw   x24, 24 * 4(sp)\n"
        "lw   x25, 25 * 4(sp)\n"
        "lw   x26, 26 * 4(sp)\n"
        "lw   x27, 27 * 4(sp)\n"
        "lw   x28, 28 * 4(sp)\n"
        "lw   x29, 29 * 4(sp)\n"
        "lw   x30, 30 * 4(sp)\n"
        "lw   x31, 31 * 4(sp)\n"
        "lw   x2,  2 * 4(sp)\n"
        "csrs mstatus, %1\n"
        "mret\n"
        :: "r"(pxCtx), "r"(MSTATUS_MIE) : "memory"
    );

    /* Never reached */
    return pdTRUE;
}

/*-----------------------------------------------------------
 * Trap handler called from assembly (portASM.S).
 *
 * Parameters:
 *   pxContext = pointer to saved register frame on stack
 *   ulMcause  = mcause value
 *
 * Returns:
 *   pointer to context frame to restore (same or different task)
 *-----------------------------------------------------------*/
UBaseType_t *vTaskTrapHandler(UBaseType_t *pxContext, UBaseType_t ulMcause) {
    UBaseType_t ulCause = ulMcause & 0x7FFFFFFF;
    BaseType_t xSwitchRequired = pdFALSE;

    if (ulMcause & 0x80000000) {
        /* Interrupt */
        if (ulCause == 7) {
            /* Machine timer interrupt */
            /* Schedule next tick based on current mtime, not mepc */
            uint32_t now;
            __asm__ volatile ("csrr %0, 0xC01" : "=r"(now));
            uint32_t next = now + TICK_CYCLES;
            __asm__ volatile ("csrw 0xB02, %0" :: "r"(next));

            /* Call FreeRTOS tick handler */
            xSwitchRequired = xTaskIncrementTick();
        }
    } else {
        /* Synchronous exception */
        if (ulCause == 11) {
            /* ECALL from M-mode = yield */
            xSwitchRequired = pdTRUE;

            /* Skip over ecall instruction */
            pxContext[0] += 4;
        }
    }

    if (xSwitchRequired) {
        /* Use inline asm to read pxCurrentTCB from memory.
         * The compiler may cache it in a callee-saved register across
         * function calls, giving us a stale pointer. */
        volatile tskTCB *pxCur;
        __asm__ volatile ("lw %0, 0(%1)"
                          : "=r"(pxCur)
                          : "r"(&pxCurrentTCB)
                          : "memory");

        /* Save interrupted task's context to ITS OWN TCB FIRST.
         * Guard against NULL (can happen if trap fires during early init). */
        if (pxCur != NULL) {
            pxCur->pxTopOfStack = pxContext;
        }

        /* Now switch to the new task (updates pxCurrentTCB in memory). */
        vTaskSwitchContext();

        /* Return the NEW task's context pointer.
         * Force a fresh read from memory to avoid stale cached value. */
        volatile tskTCB *pxNewTCB;
        __asm__ volatile ("lw %0, 0(%1)"
                          : "=r"(pxNewTCB)
                          : "r"(&pxCurrentTCB)
                          : "memory");
        if (pxNewTCB != NULL) {
            pxContext = (UBaseType_t *)pxNewTCB->pxTopOfStack;
        }
    }

    return pxContext;
}

/*-----------------------------------------------------------
 * Yield from task (trigger ecall)
 *-----------------------------------------------------------*/
void vPortYield(void) {
    __asm__ volatile ("ecall");
}

/*-----------------------------------------------------------
 * End scheduler (not used in embedded)
 *-----------------------------------------------------------*/
void vPortEndScheduler(void) {
}
