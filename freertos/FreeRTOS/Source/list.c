/*
 * FreeRTOS List implementation (minimal)
 * Doubly-linked sorted list used by the task scheduler.
 */
#include "FreeRTOS.h"
#include "list.h"

void vListInitialise(List_t * const pxList) {
    pxList->pxIndex = (ListItem_t *)&(pxList->xListEnd);
    pxList->xListEnd.xItemValue = portMAX_DELAY;
    pxList->xListEnd.pxNext = (ListItem_t *)&(pxList->xListEnd);
    pxList->xListEnd.pxPrevious = (ListItem_t *)&(pxList->xListEnd);
    pxList->uxNumberOfItems = 0;
}

void vListInitialiseItem(ListItem_t * const pxItem) {
    pxItem->pvContainer = NULL;
}

void vListInsert(List_t * const pxList, ListItem_t * const pxNewListItem) {
    ListItem_t *pxIterator;
    const TickType_t xValueOfInsertion = pxNewListItem->xItemValue;

    if (xValueOfInsertion == portMAX_DELAY) {
        pxIterator = pxList->xListEnd.pxPrevious;
    } else {
        for (pxIterator = (ListItem_t *)&(pxList->xListEnd);
             pxIterator->pxNext->xItemValue <= xValueOfInsertion;
             pxIterator = pxIterator->pxNext) {
            /* Iterate to find correct position */
        }
    }

    pxNewListItem->pxNext = pxIterator->pxNext;
    pxNewListItem->pxNext->pxPrevious = pxNewListItem;
    pxNewListItem->pxPrevious = pxIterator;
    pxIterator->pxNext = pxNewListItem;
    pxNewListItem->pvContainer = pxList;
    (pxList->uxNumberOfItems)++;
}

void vListInsertEnd(List_t * const pxList, ListItem_t * const pxNewListItem) {
    ListItem_t * const pxIndex = pxList->pxIndex;

    pxNewListItem->pxNext = pxIndex;
    pxNewListItem->pxPrevious = pxIndex->pxPrevious;
    pxIndex->pxPrevious->pxNext = pxNewListItem;
    pxIndex->pxPrevious = pxNewListItem;
    pxNewListItem->pvContainer = pxList;
    (pxList->uxNumberOfItems)++;
}

UBaseType_t uxListRemove(ListItem_t * const pxItemToRemove) {
    List_t * const pxList = pxItemToRemove->pvContainer;

    pxItemToRemove->pxNext->pxPrevious = pxItemToRemove->pxPrevious;
    pxItemToRemove->pxPrevious->pxNext = pxItemToRemove->pxNext;

    if (pxList->pxIndex == pxItemToRemove) {
        pxList->pxIndex = pxItemToRemove->pxPrevious;
    }

    pxItemToRemove->pvContainer = NULL;
    (pxList->uxNumberOfItems)--;
    return pxList->uxNumberOfItems;
}
