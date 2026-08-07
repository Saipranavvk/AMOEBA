.section ".init"
.globl _start
_start:
    .cfi_startproc
    .cfi_undefined ra

    # x0 is hardwired to zero; initialize all other integer registers
    li x1,  0
    li x2,  0
    li x3,  0
    li x4,  0
    li x5,  0
    li x6,  0
    li x7,  0
    li x8,  0
    li x9,  0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0

_initbss:
    la t1, _bss_vma_start
    la t2, _bss_vma_end
    beq t1, t2, _setup
_initbss_loop:
    sd x0, 0(t1)
    addi t1, t1, 8
    bltu t1, t2, _initbss_loop

_setup:
    # Point mtvec at halt so any unexpected trap stops simulation cleanly
    la t0, _trap_halt
    csrw mtvec, t0
    # Disable machine-level interrupts (timer/external)
    csrwi mie, 0
    la sp, _stack_top
    add s0, sp, zero
    call main
    # Signal exit via HTif tohost protocol: write 1 (exit(0)) to tohost
    li t0, 1
    la t1, tohost
    sd t0, 0(t1)
    # Fallback halt for monitor
    slti x0, x0, -256
_fini:
    beq zero, zero, _fini
_trap_halt:
    slti x0, x0, -256
    beq zero, zero, _trap_halt
    .cfi_endproc

.globl _sbrk
_sbrk:
    ld t0, _heap_ptr
    add a0, a0, t0
    sd a0, _heap_ptr, t1
    mv a0, t0
    ret

.section ".data.sbrk"
_heap_ptr:
    .dword __global_pointer$
