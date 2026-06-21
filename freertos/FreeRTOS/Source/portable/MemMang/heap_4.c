/*
 * FreeRTOS heap_4 - first-fit with coalescing (minimal version)
 */
#include "FreeRTOS.h"
#include "task.h"

/* Heap memory - statically allocated */
static uint8_t ucHeap[configTOTAL_HEAP_SIZE];

/* Block header */
typedef struct A_BLOCK_LINK {
    struct A_BLOCK_LINK *pxNextFreeBlock;
    size_t xBlockSize;
} BlockLink_t;

static const size_t heapSTRUCT_SIZE = (sizeof(BlockLink_t) + (portBYTE_ALIGNMENT - 1)) & ~((size_t)portBYTE_ALIGNMENT - 1);
static BlockLink_t xStart, *pxEnd = NULL;
static size_t xFreeBytesRemaining = 0;
static size_t xMinimumEverFreeBytesRemaining = 0;

static void prvInsertBlockIntoFreeList(BlockLink_t *pxBlockToInsert);

/*-----------------------------------------------------------
 * Initialize the heap
 *-----------------------------------------------------------*/
static void prvHeapInit(void) {
    BlockLink_t *pxFirstFreeBlock;
    uint8_t *pucAlignedHeap;
    size_t uxAddress = (size_t)ucHeap;
    size_t xTotalHeapSize = configTOTAL_HEAP_SIZE;

    /* Align heap start */
    if ((uxAddress & (portBYTE_ALIGNMENT - 1)) != 0) {
        uxAddress += (portBYTE_ALIGNMENT - 1);
        uxAddress &= ~((size_t)portBYTE_ALIGNMENT - 1);
        xTotalHeapSize -= uxAddress - (size_t)ucHeap;
    }
    pucAlignedHeap = (uint8_t *)uxAddress;

    /* Create end marker */
    uxAddress = (size_t)pucAlignedHeap + xTotalHeapSize;
    uxAddress -= heapSTRUCT_SIZE;
    uxAddress &= ~((size_t)portBYTE_ALIGNMENT - 1);
    pxEnd = (BlockLink_t *)uxAddress;
    pxEnd->xBlockSize = 0;
    pxEnd->pxNextFreeBlock = NULL;

    /* Create first free block */
    xStart.pxNextFreeBlock = (BlockLink_t *)pucAlignedHeap;
    xStart.xBlockSize = 0;

    pxFirstFreeBlock = (BlockLink_t *)pucAlignedHeap;
    pxFirstFreeBlock->xBlockSize = (size_t)pxEnd - (size_t)pxFirstFreeBlock;
    pxFirstFreeBlock->pxNextFreeBlock = pxEnd;

    xFreeBytesRemaining = pxFirstFreeBlock->xBlockSize;
    xMinimumEverFreeBytesRemaining = xFreeBytesRemaining;
}

/*-----------------------------------------------------------
 * Allocate memory
 *-----------------------------------------------------------*/
void *pvPortMalloc(size_t xWantedSize) {
    BlockLink_t *pxBlock, *pxPreviousBlock, *pxNewBlockLink;
    void *pvReturn = NULL;

    if (pxEnd == NULL) {
        prvHeapInit();
    }

    if (xWantedSize > 0) {
        /* Add header size and align */
        xWantedSize += heapSTRUCT_SIZE;
        if ((xWantedSize & (portBYTE_ALIGNMENT - 1)) != 0) {
            xWantedSize += (portBYTE_ALIGNMENT - 1);
            xWantedSize &= ~((size_t)portBYTE_ALIGNMENT - 1);
        }
    }

    if (xWantedSize > 0 && xWantedSize <= xFreeBytesRemaining) {
        pxPreviousBlock = &xStart;
        pxBlock = xStart.pxNextFreeBlock;

        while ((pxBlock->xBlockSize < xWantedSize) && (pxBlock->pxNextFreeBlock != NULL)) {
            pxPreviousBlock = pxBlock;
            pxBlock = pxBlock->pxNextFreeBlock;
        }

        if (pxBlock != pxEnd) {
            pvReturn = (void *)(((uint8_t *)pxPreviousBlock->pxNextFreeBlock) + heapSTRUCT_SIZE);
            pxPreviousBlock->pxNextFreeBlock = pxBlock->pxNextFreeBlock;

            if ((pxBlock->xBlockSize - xWantedSize) > (heapSTRUCT_SIZE << 1)) {
                pxNewBlockLink = (BlockLink_t *)(((uint8_t *)pxBlock) + xWantedSize);
                pxNewBlockLink->xBlockSize = pxBlock->xBlockSize - xWantedSize;
                pxBlock->xBlockSize = xWantedSize;
                prvInsertBlockIntoFreeList(pxNewBlockLink);
            }

            xFreeBytesRemaining -= pxBlock->xBlockSize;
            if (xFreeBytesRemaining < xMinimumEverFreeBytesRemaining) {
                xMinimumEverFreeBytesRemaining = xFreeBytesRemaining;
            }
        }
    }

    return pvReturn;
}

/*-----------------------------------------------------------
 * Free memory
 *-----------------------------------------------------------*/
void vPortFree(void *pv) {
    uint8_t *puc = (uint8_t *)pv;
    BlockLink_t *pxLink;

    if (pv != NULL) {
        puc -= heapSTRUCT_SIZE;
        pxLink = (BlockLink_t *)puc;

        vTaskEnterCritical();
        {
            xFreeBytesRemaining += pxLink->xBlockSize;
            prvInsertBlockIntoFreeList(pxLink);
        }
        vTaskExitCritical();
    }
}

/*-----------------------------------------------------------
 * Insert block into free list (sorted by address for coalescing)
 *-----------------------------------------------------------*/
static void prvInsertBlockIntoFreeList(BlockLink_t *pxBlockToInsert) {
    BlockLink_t *pxIterator;
    uint8_t *puc;

    for (pxIterator = &xStart;
         pxIterator->pxNextFreeBlock != NULL && pxIterator->pxNextFreeBlock < pxBlockToInsert;
         pxIterator = pxIterator->pxNextFreeBlock) {
        /* Walk to find insertion point */
    }

    /* Check if we can merge with previous block */
    puc = (uint8_t *)pxIterator;
    if ((puc + pxIterator->xBlockSize) == (uint8_t *)pxBlockToInsert) {
        pxIterator->xBlockSize += pxBlockToInsert->xBlockSize;
        pxBlockToInsert = pxIterator;
    }

    /* Check if we can merge with next block */
    puc = (uint8_t *)pxBlockToInsert;
    if ((puc + pxBlockToInsert->xBlockSize) == (uint8_t *)pxIterator->pxNextFreeBlock) {
        if (pxIterator->pxNextFreeBlock != pxEnd) {
            pxBlockToInsert->xBlockSize += pxIterator->pxNextFreeBlock->xBlockSize;
            pxBlockToInsert->pxNextFreeBlock = pxIterator->pxNextFreeBlock->pxNextFreeBlock;
        } else {
            pxBlockToInsert->pxNextFreeBlock = pxEnd;
        }
    } else {
        pxBlockToInsert->pxNextFreeBlock = pxIterator->pxNextFreeBlock;
    }

    if (pxIterator != pxBlockToInsert) {
        pxIterator->pxNextFreeBlock = pxBlockToInsert;
    }
}

/*-----------------------------------------------------------
 * Get free heap size
 *-----------------------------------------------------------*/
size_t xPortGetFreeHeapSize(void) {
    return xFreeBytesRemaining;
}
