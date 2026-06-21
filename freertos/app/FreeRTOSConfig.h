#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* Core config */
#define configUSE_PREEMPTION                1
#define configUSE_IDLE_HOOK                 0
#define configUSE_TICK_HOOK                 0
#define configCPU_CLOCK_HZ                  100000000   /* 100 MHz */
#define configTICK_RATE_HZ                  1000        /* 1ms tick */
#define configMAX_PRIORITIES                4
#define configMINIMAL_STACK_SIZE            24          /* 24 words = 96 bytes */
#define configMAX_TASK_NAME_LEN             8
#define configMAX_TASKS                     4
#define configTOTAL_HEAP_SIZE               1024        /* 1KB heap */

/* Hooks */
#define configUSE_MALLOC_FAILED_HOOK        0
#define configCHECK_FOR_STACK_OVERFLOW      0

/* Co-routines (unused) */
#define configUSE_CO_ROUTINES               0

/* Optional functions */
#define INCLUDE_vTaskDelay                  1
#define INCLUDE_vTaskDelete                 1
#define INCLUDE_vTaskSuspend                1
#define INCLUDE_xTaskGetTickCount           1

/* Port-specific */
#define portBYTE_ALIGNMENT                  4
#define portMAX_DELAY                       0xFFFFFFFF

#endif /* FREERTOS_CONFIG_H */
