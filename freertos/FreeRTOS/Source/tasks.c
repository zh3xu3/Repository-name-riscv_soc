/*
 * FreeRTOS Task Scheduler (minimal implementation)
 * Supports: task create/delete, preemptive scheduling, delay, yield
 */
#include "FreeRTOS.h"
#include "task.h"
#include "list.h"

/* mstatus.MIE bit for critical sections */
#define MSTATUS_MIE  (1 << 3)

/* ---- Private types ---- */
typedef struct tskTaskControlBlock {
    volatile StackType_t *pxTopOfStack;  /* Must be first member - accessed by port.c */
    ListItem_t            xStateListItem;
    StackType_t          *pxStack;
    char                  pcTaskName[configMAX_TASK_NAME_LEN];
    UBaseType_t           uxPriority;
    TickType_t            xDelayUntil;
    eTaskState            eCurrentState;
} tskTCB;

/* ---- Private data ---- */
static tskTCB *pxCurrentTCB_local = NULL;
static List_t xReadyLists[configMAX_PRIORITIES];
static List_t xDelayedTaskList;
static volatile TickType_t xTickCount = 0;
static volatile UBaseType_t uxTopReadyPriority = 0;
static volatile UBaseType_t uxCurrentNumberOfTasks = 0;
static UBaseType_t uxTaskNumber = 0;
static BaseType_t xSchedulerInitialized = pdFALSE;

/* TCB array - static allocation */
static tskTCB pxTaskTCBs[configMAX_TASKS];

/* ---- Current TCB pointer (used by port.c) ---- */
volatile tskTCB * volatile pxCurrentTCB = NULL;

/* ---- Helper macros ---- */
#define taskSELECT_HIGHEST_PRIORITY_TASK() \
    do { \
        UBaseType_t uxTopPriority = uxTopReadyPriority; \
        while (listLIST_IS_EMPTY(&xReadyLists[uxTopPriority])) { \
            uxTopPriority--; \
        } \
        listGET_OWNER_OF_NEXT_ENTRY(pxCurrentTCB_local, &xReadyLists[uxTopPriority]); \
        uxTopReadyPriority = uxTopPriority; \
        pxCurrentTCB = pxCurrentTCB_local; \
    } while (0)

/* ---- List accessor macros ---- */
#define listGET_OWNER_OF_NEXT_ENTRY(pxTCB, pxList) \
    do { \
        (pxList)->pxIndex = (pxList)->pxIndex->pxNext; \
        if ((pxList)->pxIndex == (ListItem_t *)&((pxList)->xListEnd)) { \
            (pxList)->pxIndex = (pxList)->pxIndex->pxNext; \
        } \
        (pxTCB) = (tskTCB *)(pxList)->pxIndex->pvOwner; \
    } while (0)

#define listLIST_IS_EMPTY(pxList) ((pxList)->uxNumberOfItems == 0)

#define listGET_OWNER_OF_HEAD_ENTRY(pxList) \
    ((tskTCB *)(pxList)->uxNumberOfItems ? \
     (tskTCB *)(pxList)->xListEnd.pxNext->pvOwner : NULL)

/*-----------------------------------------------------------
 * Initialize task lists
 *-----------------------------------------------------------*/
static void prvInitialiseTaskLists(void) {
    UBaseType_t uxPriority;
    for (uxPriority = 0; uxPriority < configMAX_PRIORITIES; uxPriority++) {
        vListInitialise(&xReadyLists[uxPriority]);
    }
    vListInitialise(&xDelayedTaskList);
}

/*-----------------------------------------------------------
 * Add task to ready list
 *-----------------------------------------------------------*/
static void prvAddTaskToReadyList(tskTCB *pxTCB) {
    if (pxTCB->uxPriority > uxTopReadyPriority) {
        uxTopReadyPriority = pxTCB->uxPriority;
    }
    vListInsertEnd(&xReadyLists[pxTCB->uxPriority], &pxTCB->xStateListItem);
    pxTCB->eCurrentState = eReady;
}

/*-----------------------------------------------------------
 * Create a new task
 *-----------------------------------------------------------*/
BaseType_t xTaskCreate(TaskFunction_t pxTaskCode,
                       const char * const pcName,
                       const uint16_t usStackDepth,
                       void * const pvParameters,
                       UBaseType_t uxPriority,
                       TaskHandle_t * const pxCreatedTask) {
    tskTCB *pxNewTCB;
    StackType_t *pxStack;

    if (!xSchedulerInitialized) {
        prvInitialiseTaskLists();
        xSchedulerInitialized = pdTRUE;
    }

    if (uxCurrentNumberOfTasks >= configMAX_TASKS) {
        return errCOULD_NOT_ALLOCATE_REQUIRED_MEMORY;
    }

    /* Allocate TCB from static array */
    pxNewTCB = &pxTaskTCBs[uxTaskNumber++];

    /* Allocate stack — extra words for the 33-word context frame + alignment */
    pxStack = pvPortMalloc((usStackDepth + 36) * sizeof(StackType_t));
    if (pxStack == NULL) {
        return errCOULD_NOT_ALLOCATE_REQUIRED_MEMORY;
    }

    /* Initialize TCB */
    pxNewTCB->pxStack = pxStack;
    pxNewTCB->uxPriority = uxPriority;
    pxNewTCB->eCurrentState = eSuspended;

    /* Copy task name */
    for (int i = 0; i < configMAX_TASK_NAME_LEN - 1; i++) {
        pxNewTCB->pcTaskName[i] = pcName[i];
        if (pcName[i] == '\0') break;
    }
    pxNewTCB->pcTaskName[configMAX_TASK_NAME_LEN - 1] = '\0';

    /* Initialize state list item */
    vListInitialiseItem(&pxNewTCB->xStateListItem);
    listSET_LIST_ITEM_OWNER(&pxNewTCB->xStateListItem, pxNewTCB);

    /* Initialize stack (creates initial context frame).
     * Use full allocation (usStackDepth + extra) so the trap handler's
     * 132-byte save area fits below the task's stack without overflowing. */
    pxNewTCB->pxTopOfStack = pxPortInitialiseStack(pxStack + usStackDepth + 36,
                                                    pxTaskCode, pvParameters);

    /* Add to ready list */
    taskENTER_CRITICAL();
    prvAddTaskToReadyList(pxNewTCB);
    uxCurrentNumberOfTasks++;
    taskEXIT_CRITICAL();

    if (pxCreatedTask != NULL) {
        *pxCreatedTask = (TaskHandle_t)pxNewTCB;
    }

    return pdPASS;
}

/*-----------------------------------------------------------
 * Delete a task
 *-----------------------------------------------------------*/
void vTaskDelete(TaskHandle_t xTaskToDelete) {
    tskTCB *pxTCB = (tskTCB *)xTaskToDelete;

    if (pxTCB == NULL) {
        pxTCB = (tskTCB *)pxCurrentTCB;
    }

    taskENTER_CRITICAL();

    /* Remove from ready list */
    uxListRemove(&pxTCB->xStateListItem);
    uxCurrentNumberOfTasks--;

    /* Free stack memory */
    vPortFree(pxTCB->pxStack);

    /* If deleting current task, switch context */
    if (pxTCB == (tskTCB *)pxCurrentTCB) {
        pxCurrentTCB = NULL;
        taskEXIT_CRITICAL();
        vPortYield();
    } else {
        taskEXIT_CRITICAL();
    }
}

/*-----------------------------------------------------------
 * Idle task - keeps the ready list non-empty
 *-----------------------------------------------------------*/
static void prvIdleTask(void *pvParameters) {
    (void)pvParameters;
    for (;;) {
        /* Idle loop - nothing to do */
    }
}

/*-----------------------------------------------------------
 * Start the scheduler
 *-----------------------------------------------------------*/
void vTaskStartScheduler(void) {
    /* Create idle task at lowest priority (0)
     * Needs enough stack for trap handler (132 bytes save + C handler overhead).
     * 60 words usable + 36 extra = 96 words = 384 bytes total allocation. */
    xTaskCreate(prvIdleTask, "IDLE", 60, NULL, 0, NULL);

    /* Select the first task to run */
    taskSELECT_HIGHEST_PRIORITY_TASK();

    /* Start the first task (never returns) */
    xPortStartScheduler();
}

/*-----------------------------------------------------------
 * Switch context - called from trap handler
 *-----------------------------------------------------------*/
void vTaskSwitchContext(void) {
    /* Select highest priority ready task.
     * Do NOT remove/re-insert the current task here — if it was moved to the
     * delayed list by vTaskDelay, this would corrupt that list. */
    taskSELECT_HIGHEST_PRIORITY_TASK();
}

/*-----------------------------------------------------------
 * Increment tick - called from timer interrupt handler
 * Returns pdTRUE if context switch required
 *-----------------------------------------------------------*/
BaseType_t xTaskIncrementTick(void) {
    BaseType_t xSwitchRequired = pdFALSE;
    TickType_t xItemValue;

    xTickCount++;

    /* Check delayed tasks */
    if (!listLIST_IS_EMPTY(&xDelayedTaskList)) {
        ListItem_t *pxItem = xDelayedTaskList.xListEnd.pxNext;
        xItemValue = listGET_LIST_ITEM_VALUE(pxItem);

        if (xTickCount >= xItemValue) {
            /* Task delay expired - move to ready list */
            tskTCB *pxTCB = (tskTCB *)listGET_LIST_ITEM_OWNER(pxItem);
            uxListRemove(&pxTCB->xStateListItem);
            prvAddTaskToReadyList(pxTCB);

            /* Check if woken task has higher priority */
            if (pxTCB->uxPriority > ((tskTCB *)pxCurrentTCB)->uxPriority) {
                xSwitchRequired = pdTRUE;
            }
        }
    }

    return xSwitchRequired;
}

/*-----------------------------------------------------------
 * Delay the current task for a number of ticks
 *-----------------------------------------------------------*/
void vTaskDelay(const TickType_t xTicksToDelay) {
    TickType_t xTimeToWake;
    tskTCB *pxCurrent;

    if (xTicksToDelay > 0) {
        taskENTER_CRITICAL();

        pxCurrent = (tskTCB *)pxCurrentTCB;
        xTimeToWake = xTickCount + xTicksToDelay;

        /* Remove from ready list, add to delayed list */
        uxListRemove(&pxCurrent->xStateListItem);
        listSET_LIST_ITEM_VALUE(&pxCurrent->xStateListItem, xTimeToWake);
        vListInsert(&xDelayedTaskList, &pxCurrent->xStateListItem);
        pxCurrent->eCurrentState = eBlocked;

        taskEXIT_CRITICAL();

        /* Trigger context switch */
        vPortYield();
    }
}

/*-----------------------------------------------------------
 * Get current tick count
 *-----------------------------------------------------------*/
TickType_t xTaskGetTickCount(void) {
    return xTickCount;
}

/*-----------------------------------------------------------
 * Get current task handle
 *-----------------------------------------------------------*/
TaskHandle_t xTaskGetCurrentTaskHandle(void) {
    return (TaskHandle_t)pxCurrentTCB;
}

/*-----------------------------------------------------------
 * Enter/Exit critical sections
 *-----------------------------------------------------------*/
static UBaseType_t uxCriticalNesting = 0;

void vTaskEnterCritical(void) {
    __asm__ volatile ("csrc mstatus, %0" :: "r"(MSTATUS_MIE));
    uxCriticalNesting++;
}

void vTaskExitCritical(void) {
    if (uxCriticalNesting > 0) {
        uxCriticalNesting--;
        if (uxCriticalNesting == 0) {
            __asm__ volatile ("csrs mstatus, %0" :: "r"(MSTATUS_MIE));
        }
    }
}
