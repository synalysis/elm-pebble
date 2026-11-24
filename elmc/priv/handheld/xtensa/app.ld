/* One contiguous image linked at address 0. The firmware adds the load
 * address to each absolute pointer and copies the bytes to executable RAM. */
OUTPUT_ARCH(xtensa)
ENTRY(meow_app_start)

SECTIONS {
  . = MEOW_ORIGIN;
  .text : {
    KEEP(*(.literal .literal.* .text.literal .text.literal.*))
    *(.text .text.*)
    *(.rodata .rodata.*)
    *(.data .data.*)
    . = ALIGN(4);
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    _end = .;
  }
}
