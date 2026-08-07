.section .text.init
  .global _start
  .extern freertos_risc_v_trap_handler

_start:
  # Install FreeRTOS trap handler immediately at reset.
  # freertos_risc_v_trap_handler handles ecall, timer, and exceptions.
  la    t0, freertos_risc_v_trap_handler
  csrw  mtvec, t0               # direct mode (bits[1:0] = 00)

  # Set up global pointer for linker relaxation
  .option push
  .option norelax
  la    gp, __global_pointer$
  .option pop

  # Set up initial stack pointer (4 KB below top of RAM)
  la    sp, __freertos_irq_stack_top
  li    t0, 4096
  sub   sp, sp, t0

  # Zero BSS
  la    t0, _bss_start
  la    t1, _bss_end
.bss_loop:
  beq   t0, t1, .bss_done
  sd    zero, 0(t0)
  addi  t0, t0, 8
  j     .bss_loop
.bss_done:

  call  main

.hang:
  j     .hang
