/*
 * freertos_pynq.ld -- FreeRTOS on the PYNQ-Z2, against block RAM.
 *
 * The difference from freertos_wally.ld is that the memory here is REAL and
 * small.  The simulation testbench backs 128 MB, so tohost at RAM_BASE + 8 MB
 * and a stack top at RAM_BASE + 128 MB are both perfectly good addresses.  On
 * the FPGA the memory is MEM_KB (128 KiB by default) and fpga/pynq/rtl/
 * amoeba_mem_bram.sv truncates the index rather than faulting, so every address
 * above the array ALIASES BACK INTO IT:
 *
 *   tohost   0x80800000 & 0x1FFFF = 0x00000   <- the reset vector
 *   sp       0x87FFF000 & 0x1FFFF = 0x1F000   <- the top page
 *
 * The exit write would overwrite the first instructions of the program it is
 * reporting on, and the stack would land wherever it happened to land.  Neither
 * is visible in simulation.
 *
 * Layout, from the top of a 128 KiB array:
 *
 *   0x8001F000  tohost / fromhost      (top page, HTIF only)
 *   0x8001E000  free guard page
 *   0x8001D000  IRQ stack top          (grows down to 0x8001D000)
 *   0x8001D000  main stack top         (crt0 sets sp = irq_stack_top - 4096)
 *      ...      ~37 KiB of slack
 *   0x80013AA0  _end (top of .bss / FreeRTOS heap)
 *   0x80000000  .text
 *
 * KEEP tohost 4 KiB-ALIGNED.  htif_writeback() in syscalls_amoeba.c flushes it
 * by conflict eviction, and with 4 KiB ways and 64-byte lines the set index is
 * (addr >> 6) & 63 -- which is 0 for every 4 KiB-aligned address, and the sweep
 * is written assuming set 0.
 *
 * These addresses are DERIVED IN THE RTL from MEM_KB (see TOHOST_ADDR in
 * fpga/pynq/rtl/amoeba_pynq_top.sv).  If MEM_KB changes, both move.  If they
 * drift apart, the run prints correct console output and then hangs forever
 * waiting for an exit the bus monitor never saw.
 */

OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K
}

/* Top page reserved for HTIF; guard page below it; stack under that. */
__freertos_irq_stack_top = ORIGIN(RAM) + LENGTH(RAM) - 0x2000;

PROVIDE(tohost   = 0x8001F000);
PROVIDE(fromhost = 0x8001F008);

SECTIONS
{
  . = 0x80000000;

  .text :
  {
    *(.text.init)
    *(.text)
    *(.text.*)
    . = ALIGN(8);
  } > RAM

  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
    . = ALIGN(8);
  } > RAM

  .data :
  {
    __global_pointer$ = . + 0x800;
    *(.sdata)
    *(.sdata.*)
    *(.data)
    *(.data.*)
    . = ALIGN(8);
  } > RAM

  .tdata :
  {
    _tdata_begin = .;
    *(.tdata)
    *(.tdata.*)
    _tdata_end = .;
    . = ALIGN(8);
  } > RAM

  .tbss :
  {
    *(.tbss)
    *(.tbss.*)
    _tbss_end = .;
    . = ALIGN(8);
  } > RAM

  .bss :
  {
    _bss_start = .;
    *(.sbss)
    *(.sbss.*)
    *(.bss)
    *(.bss.*)
    . = ALIGN(8);
    _bss_end = .;
  } > RAM

  _end = .;
}
