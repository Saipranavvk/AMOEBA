/*
 * syscalls_amoeba.c — minimal RISC-V BSP for AMOEBA/Wally simulation.
 *
 * Provides printf (via NS16550 UART at 0x10000000), exit() via the
 * standard RISC-V HTif tohost protocol, and basic string/memory helpers.
 *
 * tohost is declared extern; its address is fixed at 0x80800000 by
 * freertos_amoeba.ld.  The testbench monitors writes to that address.
 *
 * NOTE: handle_trap is intentionally NOT provided.  FreeRTOS installs
 * freertos_risc_v_trap_handler via mtvec before main() runs (freertos_crt.S).
 */

#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <limits.h>
#include <sys/signal.h>

extern volatile uint64_t tohost;
extern volatile uint64_t fromhost;

/* ---- UART output (NS16550 at 0x10000000) ---- */

void uartInit(void)
{
    volatile uint8_t *UART_LCR = (uint8_t *)0x10000003;
    *UART_LCR = 0x03; /* 8-bit, 1 stop bit, no parity */
}

void uartSend(char c)
{
    volatile uint8_t *UART_THR = (uint8_t *)0x10000000;
    volatile uint8_t *UART_LSR = (uint8_t *)0x10000005;
    while (!(*UART_LSR & (1 << 5)));
    *UART_THR = (uint8_t)c;
}

/* ---- Exit via HTif tohost ---- */

void __attribute__((noreturn)) tohost_exit(uintptr_t code)
{
    tohost = (code << 1) | 1;
    /* CVW's D-cache is write-back; the SD above stays dirty in cache and
     * never reaches the AHB bus unless explicitly evicted.  cbo.flush
     * (Zicbom, imm=2) writes the dirty cache line back to AHB so the
     * testbench can observe the write on mem_itf.  Using .insn bypasses
     * assembler ISA-extension checks. */
    asm volatile (".insn i 0xF, 2, zero, %0, 2"
                  : : "r" ((uintptr_t)&tohost) : "memory");
    while (1);
}

void exit(int code)
{
    tohost_exit((uintptr_t)(unsigned int)code);
}

void abort(void)
{
    exit(128 + SIGABRT);
}

/* ---- printf infrastructure ---- */

void printstr(const char *s)
{
    while (*s) uartSend(*s++);
}

int puts(const char *s)
{
    printstr(s);
    return 0;
}

#undef putchar
int putchar(int ch)
{
    uartSend((char)ch);
    return 0;
}

static void printnum(void (*putch)(int, void **), void **putdat,
                     unsigned long long num, unsigned base, int width, int padc)
{
    unsigned digs[sizeof(num) * CHAR_BIT];
    int pos = 0;
    while (1) {
        digs[pos++] = num % base;
        if (num < base) break;
        num /= base;
    }
    while (width-- > pos) putch(padc, putdat);
    while (pos-- > 0)
        putch(digs[pos] + (digs[pos] >= 10 ? 'a' - 10 : '0'), putdat);
}

static unsigned long long getuint(va_list *ap, int lflag)
{
    if (lflag >= 2) return va_arg(*ap, unsigned long long);
    if (lflag)      return va_arg(*ap, unsigned long);
    return va_arg(*ap, unsigned int);
}

static long long getint(va_list *ap, int lflag)
{
    if (lflag >= 2) return va_arg(*ap, long long);
    if (lflag)      return va_arg(*ap, long);
    return va_arg(*ap, int);
}

static void vprintfmt(void (*putch)(int, void **), void **putdat,
                      const char *fmt, va_list ap)
{
    register const char *p;
    const char *last_fmt;
    register int ch;
    unsigned long long num;
    int base, lflag, width, precision;
    char padc;

    while (1) {
        while ((ch = *(unsigned char *)fmt) != '%') {
            if (ch == '\0') return;
            fmt++;
            putch(ch, putdat);
        }
        fmt++;
        last_fmt = fmt;
        padc = ' '; width = -1; precision = -1; lflag = 0;
    reswitch:
        switch (ch = *(unsigned char *)fmt++) {
        case '-': padc = '-'; goto reswitch;
        case '0': padc = '0'; goto reswitch;
        case '1': case '2': case '3': case '4': case '5':
        case '6': case '7': case '8': case '9':
            for (precision = 0; ; ++fmt) {
                precision = precision * 10 + ch - '0';
                ch = *fmt;
                if (ch < '0' || ch > '9') break;
            }
            goto process_precision;
        case '*':  precision = va_arg(ap, int); goto process_precision;
        case '.':  if (width < 0) width = 0; goto reswitch;
        case '#':  goto reswitch;
        process_precision:
            if (width < 0) { width = precision; precision = -1; }
            goto reswitch;
        case 'l': lflag++; goto reswitch;
        case 'c': putch(va_arg(ap, int), putdat); break;
        case 's':
            if ((p = va_arg(ap, char *)) == NULL) p = "(null)";
            if (width > 0 && padc != '-')
                for (width -= (int)strnlen(p, (size_t)(precision < 0 ? INT_MAX : precision));
                     width > 0; width--)
                    putch(padc, putdat);
            for (; (ch = *p) != '\0' && (precision < 0 || --precision >= 0); width--) {
                putch(ch, putdat); p++;
            }
            for (; width > 0; width--) putch(' ', putdat);
            break;
        case 'd':
            num = (unsigned long long)getint(&ap, lflag);
            if ((long long)num < 0) { putch('-', putdat); num = (unsigned long long)(-(long long)num); }
            base = 10; goto number;
        case 'u': base = 10; goto unsigned_number;
        case 'o': base = 8;  goto unsigned_number;
        case 'p':
            lflag = 1; putch('0', putdat); putch('x', putdat);
            /* fall through */
        case 'x': base = 16;
        unsigned_number:
            num = getuint(&ap, lflag);
        number:
            printnum(putch, putdat, num, (unsigned)base, width, padc);
            break;
        case '%': putch(ch, putdat); break;
        default:  putch('%', putdat); fmt = last_fmt; break;
        }
    }
}

static void putch_wrapper(int ch, void **ignored)
{
    (void)ignored;
    uartSend((char)ch);
}

int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprintfmt(putch_wrapper, NULL, fmt, ap);
    va_end(ap);
    return 0;
}

/* sprintf: collect into buffer */
struct sprintf_state { char *ptr; };

static void sprintf_putch(int ch, void **data)
{
    struct sprintf_state *s = (struct sprintf_state *)*data;
    *s->ptr++ = (char)ch;
}

int sprintf(char *str, const char *fmt, ...)
{
    va_list ap;
    struct sprintf_state s = { str };
    void *p = &s;
    va_start(ap, fmt);
    vprintfmt(sprintf_putch, &p, fmt, ap);
    *s.ptr = '\0';
    va_end(ap);
    return (int)(s.ptr - str);
}

/* ---- Memory helpers ---- */

void *memcpy(void *dest, const void *src, size_t len)
{
    if ((((uintptr_t)dest | (uintptr_t)src | len) & (sizeof(uintptr_t) - 1)) == 0) {
        const uintptr_t *s = src;
        uintptr_t *d = dest;
        while (d < (uintptr_t *)(dest + len)) *d++ = *s++;
    } else {
        const char *s = src;
        char *d = dest;
        while (d < (char *)(dest + len)) *d++ = *s++;
    }
    return dest;
}

void *memset(void *dest, int byte, size_t len)
{
    if ((((uintptr_t)dest | len) & (sizeof(uintptr_t) - 1)) == 0) {
        uintptr_t word = (unsigned char)byte;
        word |= word << 8; word |= word << 16; word |= word << 16 << 16;
        uintptr_t *d = dest;
        while (d < (uintptr_t *)(dest + len)) *d++ = word;
    } else {
        char *d = dest;
        while (d < (char *)(dest + len)) *d++ = (char)byte;
    }
    return dest;
}

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

size_t strnlen(const char *s, size_t n)
{
    const char *p = s;
    while (n-- && *p) p++;
    return (size_t)(p - s);
}

int strcmp(const char *s1, const char *s2)
{
    unsigned char c1, c2;
    do { c1 = (unsigned char)*s1++; c2 = (unsigned char)*s2++; } while (c1 && c1 == c2);
    return (int)c1 - (int)c2;
}

char *strcpy(char *dest, const char *src)
{
    char *d = dest;
    while ((*d++ = *src++));
    return dest;
}
