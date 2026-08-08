#ifndef _AMOEBA_STUB_STDIO_H_
#define _AMOEBA_STUB_STDIO_H_
/* Minimal stdio stubs for freestanding FreeRTOS build when newlib is absent.
 * Actual implementations live in syscalls_amoeba.c. */
extern int printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
extern int sprintf(char *str, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
extern int puts(const char *s);
extern int putchar(int c);
#endif
