OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { KEEP(*(.tohost)) }
  . = ALIGN(0x1000);
  .text : { *(.text*) }
  . = ALIGN(0x1000);
  .data : { *(.data*) *(.sdata*) }
  .bss : { *(.bss*) *(COMMON) }
  _end = .;
}
