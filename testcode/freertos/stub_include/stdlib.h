#ifndef _AMOEBA_STUB_STDLIB_H_
#define _AMOEBA_STUB_STDLIB_H_
#include <stddef.h>
/* Minimal stdlib stubs for freestanding FreeRTOS build when newlib is absent.
 * malloc/free are satisfied by FreeRTOS heap_4; exit/abort by syscalls_amoeba.c. */
extern void *malloc(size_t n);
extern void  free(void *p);
extern void  exit(int code) __attribute__((noreturn));
extern void  abort(void)    __attribute__((noreturn));
#endif
