/* =============================================================================
 *  link3.ld  --  Linker script cho mem3.S (Rocket RV32 boot-ROM memory test)
 * -----------------------------------------------------------------------------
 *  Toan bo code chay trong ROM. _start (cau hinh CSR + cac buoc set up) nam dau
 *  ROM va chay tiep ngay vao phan test -- KHONG nhay di dau.
 *
 *  BAN DO BO NHO:
 *    ROM 0x10000000 (256 KiB) : toan bo code (.text). ORIGIN(ROM) = dia chi
 *                               reset cua core.
 *    RAM 0x80000000 (256 MiB) : .tohost ; .bss ; vung stack.
 *
 *  SYMBOL do linker script nay dinh nghia (mem3.S dung trong cac buoc set up):
 *    __bss_start , __bss_end : dau/cuoi vung .bss (de _start xoa .bss).
 *    __stack_top             : dinh stack (de _start lap sp).
 *
 *  Vung test do mem3.S truy cap luc CHAY (khong phai section cua linker):
 *    VUNG TEST = 0x80090000 .. 0x800A0000  (64 KiB, trong RAM)
 *    Marker cafebabe/deadbeef = 0x80008000
 *
 *  RANG BUOC:
 *    - ORIGIN(ROM) phai bang dia chi reset cua core.
 *    - .tohost / .bss / stack phai nam trong RAM ghi duoc.
 *    - Vung test va marker khong duoc trung .tohost/.bss/stack.
 *      (.tohost+.bss+stack ~5 KiB dau RAM; vung test bat dau 0x80090000.)
 * ============================================================================= */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    /* boot ROM: toan bo code -- ORIGIN = dia chi reset cua core */
    ROM (rx)  : ORIGIN = 0x10000000, LENGTH = 256K

    /* RAM ghi duoc: chua .tohost / .bss / stack */
    RAM (rw)  : ORIGIN = 0x80000000, LENGTH = 256M
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
    } > RAM

    .bss (NOLOAD) : {
        __bss_start = .;            /* _start xoa .bss tu day ... */
        *(.bss .bss.* COMMON)
        __bss_end = .;              /* ... toi day */
    } > RAM

    .stack (NOLOAD) : {
        . = ALIGN(16);
        . = . + 0x1000;             /* vung stack 4 KiB */
        __stack_top = .;            /* dinh stack -> _start lap sp = day */
    } > RAM

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
