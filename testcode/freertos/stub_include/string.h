#ifndef _AMOEBA_STUB_STRING_H_
#define _AMOEBA_STUB_STRING_H_
#include <stddef.h>
/* Minimal string stubs for freestanding FreeRTOS build when newlib is absent.
 * All implementations live in syscalls_amoeba.c. */
extern void  *memcpy(void *dest, const void *src, size_t n);
extern void  *memset(void *dest, int c, size_t n);
extern size_t strlen(const char *s);
extern size_t strnlen(const char *s, size_t n);
extern int    strcmp(const char *s1, const char *s2);
extern char  *strcpy(char *dest, const char *src);
#endif
