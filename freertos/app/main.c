/*
 * FreeRTOS Demo Application for RISC-V SoC
 * Two tasks: one writes to GPIO, one writes to UART
 * Demonstrates preemptive scheduling and peripheral access
 */
#include "FreeRTOS.h"
#include "task.h"

/* Peripheral base addresses */
#define GPIO_BASE   0x00003000
#define UART_BASE   0x00002000

/* GPIO registers */
#define GPIO_OUT    (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_IN     (*(volatile uint32_t *)(GPIO_BASE + 0x04))

/* UART registers */
#define UART_TX     (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_RX     (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_STATUS (*(volatile uint32_t *)(UART_BASE + 0x08))

/* Data memory for test results */
#define DMEM_BASE   0x00001000
#define DMEM(x)     (*(volatile uint32_t *)(DMEM_BASE + (x)))

/* Debug register addresses (for testbench verification) */
#define DBG_X12     (*(volatile uint32_t *)0x00003000)  /* Mapped to GPIO for debug */

/*-----------------------------------------------------------
 * Task 1: GPIO blink pattern
 * Writes alternating patterns to GPIO output
 *-----------------------------------------------------------*/
void vTaskGPIO(void *pvParameters) {
    (void)pvParameters;
    uint32_t pattern = 0xAAAA5555;
    uint32_t count = 0;

    for (;;) {
        /* Write pattern to GPIO */
        GPIO_OUT = pattern;

        /* Read back (loopback in simulation) */
        uint32_t readback = GPIO_IN;

        /* Store result for testbench verification */
        if (count == 0) {
            DMEM(0xFE0) = readback;  /* Test result at DMEM[0x1FE0] - past stack */
        }

        /* Toggle pattern */
        pattern = ~pattern;
        count++;

        /* Delay 3 ticks */
        vTaskDelay(3);
    }
}

/*-----------------------------------------------------------
 * Task 2: UART TX
 * Sends a byte via UART and verifies loopback
 *-----------------------------------------------------------*/
void vTaskUART(void *pvParameters) {
    (void)pvParameters;

    /* Wait a bit for GPIO task to run first */
    vTaskDelay(2);

    /* Send test byte */
    UART_TX = 0x55;

    /* Wait for TX to complete */
    vTaskDelay(2);

    /* Read RX (loopback) */
    uint32_t rx_data = UART_RX;

    /* Store result for testbench verification */
    DMEM(0xFE4) = rx_data;  /* Test result at DMEM[0x1FE4] - past stack */

    /* Task done - delete self */
    vTaskDelete(NULL);
}

/*-----------------------------------------------------------
 * Main - creates tasks and starts scheduler
 *-----------------------------------------------------------*/
int main(void) {
    /* Create Task 1: GPIO (priority 2 - higher) */
    /* Stack depth = 40 words usable; xTaskCreate adds 36 words for context frame + trap save */
    xTaskCreate(vTaskGPIO, "GPIO", 40, NULL, 2, NULL);

    /* Create Task 2: UART (priority 1 - lower) */
    xTaskCreate(vTaskUART, "UART", 40, NULL, 1, NULL);

    /* Start scheduler (never returns) */
    vTaskStartScheduler();

    /* Should never reach here */
    for (;;) {}
}
