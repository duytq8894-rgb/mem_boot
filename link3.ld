/* =============================================================================
 *  link2.ld  --  Linker script cho mem.S (Rocket RV32 boot-ROM memory test)
 * -----------------------------------------------------------------------------
 *  BAN DO BO NHO:
 *    ROM : 0x10000000 , 256 KiB   -- chua code .text ; ORIGIN = dia chi reset core
 *    RAM : 0x80000000 , 256 MiB   -- chua section .tohost (o 0x80000000) va .bss
 *
 *  Vung test do mem.S truy cap luc CHAY (khong phai section cua linker):
 *    CACHED   = 0x80010000 .. 0x80020000   (trong RAM, ngay sau .tohost)
 *    UNCACHED = do .equ UNCACHED_BASE trong mem.S quy dinh (cua so non-cacheable)
 *
 *  RANG BUOC BAT BUOC:
 *    - ORIGIN(ROM) phai bang dia chi reset (boot address) cua loi Rocket.
 *    - Section .tohost phai nam trong RAM ghi duoc; HTIF tim symbol `tohost`.
 *    - Vung test CACHED/UNCACHED KHONG duoc trung .text, .tohost, .bss.
 *      (.tohost rat nho, nam o 0x80000000; CACHED bat dau o 0x80010000 -> an toan.)
 * ============================================================================= */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    /* boot ROM: chua code .text -- ORIGIN = dia chi reset cua core */
    ROM (rx)  : ORIGIN = 0x10000000, LENGTH = 256K

    /* RAM ghi duoc: chua section .tohost / .bss                    */
    RAM (rw)  : ORIGIN = 0x80000000, LENGTH = 256M
}

SECTIONS
{
    . = ORIGIN(ROM);

    .text : {
        KEEP(*(.text.init))         /* reset vector phai nam dau */
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > ROM

    .tohost ALIGN(64) : {
        *(.tohost)                  /* nam o dau RAM -> tohost = 0x80000000 */
    } > RAM

    .bss (NOLOAD) : {
        *(.bss .bss.* COMMON)
    } > RAM

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
