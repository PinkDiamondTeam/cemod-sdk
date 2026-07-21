OUTPUT_ARCH(powerpc)
ENTRY(entry)

PHDRS
{
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
  dynamic PT_DYNAMIC FLAGS(6);
}

SECTIONS
{
  . = 0;
  __payload_start = .;

  .text : ALIGN(16)
  {
    KEEP(*(.entry))
    *(.text .text.* .gnu.linkonce.t.*)
  } :text

  .rodata : ALIGN(16)
  {
    *(.rodata .rodata.* .gnu.linkonce.r.*)
    *(.sdata2 .sdata2.* .gnu.linkonce.s2.*)
    *(.sbss2 .sbss2.* .gnu.linkonce.sb2.*)
    *(.gcc_except_table .gcc_except_table.*)
    *(.gnu_extab*)
    . = ALIGN(4);
    __eh_frame_start = .;
    KEEP(*(.eh_frame .eh_frame.*))
    LONG(0);
    __eh_frame_end = .;

    . = ALIGN(4);
    __preinit_array_start = .;
    KEEP(*(.preinit_array))
    __preinit_array_end = .;
    __init_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    KEEP(*(.init_array))
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors.*)))
    KEEP(*(.ctors))
    __init_array_end = .;
    __fini_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
    KEEP(*(.fini_array))
    KEEP(*(SORT_BY_INIT_PRIORITY(.dtors.*)))
    KEEP(*(.dtors))
    __fini_array_end = .;
  } :text

  .cemod.bootstrap : ALIGN(16)
  {
    KEEP(*(.cemod.bootstrap))
  } :text

  .data : ALIGN(16)
  {
    *(.data .data.* .gnu.linkonce.d.*)
    *(.sdata .sdata.* .gnu.linkonce.s.*)
    *(.got1 .got2 .got .got.* .plt .branch_lt .tm_clone_table)
  } :data

  .dynamic : ALIGN(4) { *(.dynamic) } :data :dynamic

  .bss (NOLOAD) : ALIGN(16)
  {
    __bss_start = .;
    *(.sbss .sbss.* .gnu.linkonce.sb.*)
    *(.bss .bss.* .gnu.linkonce.b.*)
    *(COMMON)
    __bss_end = .;
    . = ALIGN(16);
    __heap_start = .;
    . += 2M;
    __heap_end = .;
  } :data

  __payload_end = .;
  data_end = .;
  __end__ = .;

  /DISCARD/ :
  {
    *(.comment)
    *(.gnu.attributes)
    *(.note*)
  }
}
