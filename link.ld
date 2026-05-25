/* =========================================================================
 * link.ld — Linker script cho CVA6 boot ROM
 * -------------------------------------------------------------------------
 * - ELF64 little-endian RISC-V
 * - ROM bắt đầu tại 0x100000 (đây là reset vector của CPU)
 * - 3 output section RIÊNG BIỆT, mỗi cái có địa chỉ tuyệt đối:
 *      .text.start  @ 0x100000   (_start)
 *      .text.hang   @ 0x100040   (_hang)
 *      .rodata      @ 0x100080   (_dtb)
 * - Bytes giữa các section được linker tự pad bằng 0x00 (default fill).
 * ========================================================================= */

OUTPUT_ARCH(riscv)
OUTPUT_FORMAT("elf64-littleriscv")
ENTRY(_start)

MEMORY
{
    /* boot ROM: chứa code .text -- ORIGIN = địa chỉ reset của core */
    ROM (rx) : ORIGIN = 0x100000, LENGTH = 256K
}

SECTIONS
{
    /* -------- _start tại 0x100000 ------------------------------------- */
    .text.start 0x100000 : {
        KEEP(*(.text.start))
    } > ROM

    /* -------- _hang  tại 0x100040 ------------------------------------- */
    .text.hang  0x100040 : {
        KEEP(*(.text.hang))
    } > ROM

    /* -------- _dtb   tại 0x100080 ------------------------------------- */
    .rodata     0x100080 : {
        KEEP(*(.rodata))
        KEEP(*(.rodata.*))
    } > ROM

    /* -------- Bỏ các section thừa ------------------------------------- */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
