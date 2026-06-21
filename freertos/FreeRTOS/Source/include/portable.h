#ifndef PORTABLE_H
#define PORTABLE_H

#include "portmacro.h"

/* Portable functions */
StackType_t *pxPortInitialiseStack(StackType_t *pxTopOfStack,
                                   void (*pxCode)(void *),
                                   void *pvParameters);

BaseType_t xPortStartScheduler(void);
void vPortEndScheduler(void);
void vPortYield(void);
void vPortSetupTimerInterrupt(void);

/* Memory management */
void *pvPortMalloc(size_t xWantedSize);
void vPortFree(void *pv);
size_t xPortGetFreeHeapSize(void);

#endif /* PORTABLE_H */
