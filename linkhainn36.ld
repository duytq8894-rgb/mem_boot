OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text*) }
  . = ALIGN(0x1000);
  .data      : { *(.data*) *(.sdata*) *(.rodata*) }
  . = ALIGN(0x40);
  .tohost    : { *(.tohost) }
  .bss       : { *(.bss*) *(COMMON) }
  _end = .;
}
