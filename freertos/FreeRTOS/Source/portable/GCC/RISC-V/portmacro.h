#ifndef PORTMACRO_H
#define PORTMACRO_H

#include <stdint.h>

/* Type definitions */
typedef uint32_t StackType_t;
typedef uint32_t UBaseType_t;
typedef int32_t  BaseType_t;
typedef uint32_t TickType_t;

/* Architecture specifics */
#define portSTACK_GROWTH            (-1)
#define portTICK_PERIOD_MS          ((TickType_t)1000 / configTICK_RATE_HZ)
#define portBYTE_ALIGNMENT          4
#define portMAX_DELAY               0xFFFFFFFF
#define portNOP()                   __asm__ volatile ("nop")

/* Critical section - disable/enable interrupts via mstatus.MIE */
#define portDISABLE_INTERRUPTS()    __asm__ volatile ("csrc mstatus, %0" :: "r"(1 << 3))
#define portENABLE_INTERRUPTS()     __asm__ volatile ("csrs mstatus, %0" :: "r"(1 << 3))

#endif /* PORTMACRO_H */
