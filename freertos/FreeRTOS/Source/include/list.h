#ifndef LIST_H
#define LIST_H

#include "portmacro.h"

/* List item */
struct xLIST_ITEM {
    TickType_t xItemValue;
    struct xLIST_ITEM *pxNext;
    struct xLIST_ITEM *pxPrevious;
    void *pvOwner;
    void *pvContainer;
};
typedef struct xLIST_ITEM ListItem_t;

/* Mini list item (used as list end marker) */
struct xMINI_LIST_ITEM {
    TickType_t xItemValue;
    struct xLIST_ITEM *pxNext;
    struct xLIST_ITEM *pxPrevious;
};
typedef struct xMINI_LIST_ITEM MiniListItem_t;

/* List */
typedef struct xLIST {
    volatile UBaseType_t uxNumberOfItems;
    ListItem_t *pxIndex;
    MiniListItem_t xListEnd;
} List_t;

/* List item macros */
#define listGET_LIST_ITEM_OWNER(pxListItem) ((pxListItem)->pvOwner)

/* List functions */
void vListInitialise(List_t * const pxList);
void vListInitialiseItem(ListItem_t * const pxItem);
void vListInsert(List_t * const pxList, ListItem_t * const pxNewListItem);
void vListInsertEnd(List_t * const pxList, ListItem_t * const pxNewListItem);
UBaseType_t uxListRemove(ListItem_t * const pxItemToRemove);

#endif /* LIST_H */
