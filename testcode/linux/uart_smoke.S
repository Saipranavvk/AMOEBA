# Console-path smoke test for the Linux boot tier.
#
# Runs in M-mode straight off the reset vector and drives the CVW NS16550 at
# UART_BASE directly.  It exists to answer one question before any firmware is
# built: does a store to the transmit holding register actually reach the
# testbench's RVFI tap and come out as a "[UART]" line?  Everything downstream
# -- OpenSBI's banner, the kernel console, the pass/fail matcher -- depends on
# that path working.
#
# The THRE poll is deliberately bounded.  If the UART turned out to be backed by
# behavioural memory rather than the real peripheral, an unbounded poll would
# hang until the cycle timeout and tell us nothing; storing anyway means the
# byte still reaches the tap, and the LSR value printed at the end says which
# world we are in (0x60 = a live 16550 with an empty transmitter).

.equ UART_BASE, 0x10000000
.equ UART_THR,  0          # transmit holding register  (DLL when DLAB=1)
.equ UART_IER,  1          # interrupt enable           (DLM when DLAB=1)
.equ UART_FCR,  2          # FIFO control (write-only)
.equ UART_LCR,  3          # line control
.equ UART_LSR,  5          # line status; bit 5 = THRE
.equ LSR_THRE,  0x20

.section .init
.globl _start
_start:
    li      sp, 0x8ff00000
    li      s0, UART_BASE

    # 8N1, divisor 1, FIFOs on, interrupts off -- polled operation only.
    li      t1, 0x83               # LCR: DLAB=1 | 8 data bits
    sb      t1, UART_LCR(s0)
    li      t1, 1
    sb      t1, UART_THR(s0)       # DLL = 1
    sb      x0, UART_IER(s0)       # DLM = 0
    li      t1, 0x03               # LCR: DLAB=0 | 8N1
    sb      t1, UART_LCR(s0)
    li      t1, 0x07               # FCR: enable FIFOs, clear both
    sb      t1, UART_FCR(s0)
    sb      x0, UART_IER(s0)       # no interrupts

    la      s1, msg
    jal     ra, puts

    # Dump the whole 8-register file.  If every offset reads back zero the
    # peripheral is not answering at all; a live 16550 shows LSR (offset 5) as
    # 0x60 -- transmitter empty and holding register empty.
    la      s1, regs_msg
    jal     ra, puts
    li      s2, 0                  # offset
1:  add     t0, s0, s2
    lbu     s3, 0(t0)
    srli    a0, s3, 4
    jal     ra, puthex
    andi    a0, s3, 0xf
    jal     ra, puthex
    li      a0, 32                 # ' '
    jal     ra, putc
    addi    s2, s2, 1
    li      t0, 8
    blt     s2, t0, 1b
    li      a0, 10                 # '\n'
    jal     ra, putc

    slti    x0, x0, -256           # halt: testbench ends the simulation here
1:  j       1b

# s1 = NUL-terminated string.  Clobbers a0, s1, t1, t2.
puts:
    mv      t3, ra
1:  lbu     a0, 0(s1)
    beqz    a0, 2f
    jal     ra, putc
    addi    s1, s1, 1
    j       1b
2:  mv      ra, t3
    ret

# a0 = byte to transmit.  Clobbers t1, t2.
putc:
    li      t2, 1000               # bounded THRE poll -- see header comment
1:  lbu     t1, UART_LSR(s0)
    andi    t1, t1, LSR_THRE
    bnez    t1, 2f
    addi    t2, t2, -1
    bnez    t2, 1b
2:  sb      a0, UART_THR(s0)
    ret

# a0 = low nibble.  Tail-calls putc, so it returns to puthex's caller.
puthex:
    li      t1, 10
    blt     a0, t1, 1f
    addi    a0, a0, 87             # 'a' - 10
    j       putc
1:  addi    a0, a0, 48             # '0'
    j       putc

.section .rodata
msg:     .string "AMOEBA_UART_OK\n"
regs_msg: .string "UARTREGS="
