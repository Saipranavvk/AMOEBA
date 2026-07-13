OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

__freertos_irq_stack_top = ORIGIN(RAM) + LENGTH(RAM);

/*
 * HTif tohost/fromhost at a fixed, well-known address (8 MB above RAM base).
 * The testbench monitors writes here to detect exit() calls.
 * Placed well above any realistic code+data+heap+stack footprint so it
 * never collides with program sections.
 */
PROVIDE(tohost   = 0x80800000);
PROVIDE(fromhost = 0x80800008);

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
