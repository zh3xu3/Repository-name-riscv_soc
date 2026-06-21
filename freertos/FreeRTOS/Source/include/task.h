#ifndef TASK_H
#define TASK_H

#include "FreeRTOSConfig.h"
#include "portmacro.h"
#include "list.h"

/* Task states */
typedef enum {
    eRunning = 0,
    eReady,
    eBlocked,
    eSuspended,
    eDeleted
} eTaskState;

/* Task function type */
typedef void (*TaskFunction_t)(void *);

/* Task handle */
typedef void * TaskHandle_t;

/* Error codes */
#define errCOULD_NOT_ALLOCATE_REQUIRED_MEMORY  (-1)

/* Task API */
BaseType_t xTaskCreate(TaskFunction_t pxTaskCode,
                       const char * const pcName,
                       const uint16_t usStackDepth,
                       void * const pvParameters,
                       UBaseType_t uxPriority,
                       TaskHandle_t * const pxCreatedTask);

void vTaskDelete(TaskHandle_t xTaskToDelete);
void vTaskStartScheduler(void);
void vTaskSwitchContext(void);
BaseType_t xTaskIncrementTick(void);
void vTaskDelay(const TickType_t xTicksToDelay);
TickType_t xTaskGetTickCount(void);
TaskHandle_t xTaskGetCurrentTaskHandle(void);

/* Critical sections */
void vTaskEnterCritical(void);
void vTaskExitCritical(void);

/* Port functions (implemented in port.c) */
StackType_t *pxPortInitialiseStack(StackType_t *pxTopOfStack,
                                   TaskFunction_t pxCode,
                                   void *pvParameters);
BaseType_t xPortStartScheduler(void);
void vPortYield(void);
void vPortSetupTimerInterrupt(void);
void vPortEndScheduler(void);

/* Task yield macro */
#define taskYIELD() vPortYield()

/* Critical section macros */
#define taskENTER_CRITICAL() vTaskEnterCritical()
#define taskEXIT_CRITICAL()  vTaskExitCritical()

/* List item macros */
#define listSET_LIST_ITEM_OWNER(pxListItem, pxOwner) \
    ((pxListItem)->pvOwner = (void *)(pxOwner))

#define listGET_LIST_ITEM_VALUE(pxListItem) ((pxListItem)->xItemValue)

#define listSET_LIST_ITEM_VALUE(pxListItem, xValue) \
    ((pxListItem)->xItemValue = (xValue))

#endif /* TASK_H */
