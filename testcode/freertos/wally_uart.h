#ifndef WALLY_UART_H
#define WALLY_UART_H

#include <stdint.h>

/* NS16550 UART at UART_BASE = 0x10000000 (wallypipelinedsoc default) */
#define UART_BASE   0x10000000UL

/* Registers (DLAB=0) */
#define UART_RBR    (*(volatile uint8_t *)(UART_BASE + 0x0))  /* Receive buffer  (R) */
#define UART_THR    (*(volatile uint8_t *)(UART_BASE + 0x0))  /* Transmit holding (W) */
#define UART_IER    (*(volatile uint8_t *)(UART_BASE + 0x1))  /* Interrupt enable */
#define UART_IIR    (*(volatile uint8_t *)(UART_BASE + 0x2))  /* Interrupt ID    (R) */
#define UART_FCR    (*(volatile uint8_t *)(UART_BASE + 0x2))  /* FIFO control    (W) */
#define UART_LCR    (*(volatile uint8_t *)(UART_BASE + 0x3))  /* Line control */
#define UART_MCR    (*(volatile uint8_t *)(UART_BASE + 0x4))  /* Modem control */
#define UART_LSR    (*(volatile uint8_t *)(UART_BASE + 0x5))  /* Line status */
#define UART_MSR    (*(volatile uint8_t *)(UART_BASE + 0x6))  /* Modem status */

#define UART_LSR_DR     0x01   /* Data ready */
#define UART_LSR_THRE   0x20   /* Transmit holding register empty */
#define UART_LSR_TEMT   0x40   /* Transmitter empty */

static inline void uart_putc(char c) {
    while (!(UART_LSR & UART_LSR_THRE));
    UART_THR = (uint8_t)c;
}

static inline void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

#endif /* WALLY_UART_H */
