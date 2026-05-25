/* =============================================================================
 *  link3.ld  --  Linker script cho mem3.S (Rocket RV32 boot-ROM memory test)
 * -----------------------------------------------------------------------------
 *  TAT CA section deu nam trong ROM (.text, .tohost, .bss, stack).
 *  Khong dung region RAM cho linker -> tranh loi "section not within region".
 *
 *    ROM 0x10000000 (256 KiB) : .text + .tohost + .bss + stack
 *
 *  Symbol do linker dinh nghia (mem3.S dung): __bss_start, __bss_end, __stack_top.
 *
 *  RAM 0x80000000 : KHONG do linker quan ly. Nhung mem3.S VAN truy cap luc CHAY:
 *      VUNG TEST = 0x80090000 .. 0x800A0000 (64 KiB)
 *      Marker cafebabe/deadbeef = 0x80008000
 *    => testbench phai co RAM ghi duoc tai cac dia chi do.
 *
 *  LUU Y: .tohost nam trong ROM nhung test van GHI vao no (sw). Testbench cua
 *  ban phai cho phep ghi vung bo nho ROM nay (binh thuong trong mo phong).
 * ============================================================================= */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    /* Tat ca o trong ROM. ORIGIN(ROM) = dia chi reset cua core. */
    ROM (rwx) : ORIGIN = 0x10000000, LENGTH = 256K
}

SECTIONS
{
    . = ORIGIN(ROM);

    .text : {
        KEEP(*(.text.init))         /* _start phai nam dau */
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > ROM

    .tohost ALIGN(64) : {
        *(.tohost)                  /* symbol tohost / fromhost */
    } > ROM

    .bss (NOLOAD) : {
        __bss_start = .;            /* _start xoa .bss tu day ... */
        *(.bss .bss.* COMMON)
        __bss_end = .;              /* ... toi day */
    } > ROM

    .stack (NOLOAD) : {
        . = ALIGN(16);
        . = . + 0x1000;             /* vung stack 4 KiB */
        __stack_top = .;            /* dinh stack -> _start lap sp = day */
    } > ROM

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
