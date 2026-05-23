/* =============================================================================
 *  link.ld  --  Linker script cho mem_test.S (Rocket RV64 boot-ROM memory test)
 * -----------------------------------------------------------------------------
 *  SUA cac dia chi trong khoi MEMORY ben duoi cho dung SoC cua ban.
 *
 *  RANG BUOC BAT BUOC:
 *    - Vung ROM (chua code) KHONG duoc trung vung test cached 0x80000..0x90000,
 *      cung KHONG trung vung UNCACHED khai bao trong mem_test.S.
 *    - Section .tohost PHAI nam trong RAM GHI DUOC ma testbench giam sat
 *      (HTIF tim symbol `tohost` trong bang symbol cua ELF).
 *    - ORIGIN(ROM) phai bang dia chi reset (boot address) cua loi Rocket.
 *
 *  GHI CHU CHO ROCKET-CHIP:
 *    - BootROM cua rocket-chip mac dinh nam o 0x10000 (xem BootROMParams).
 *    - DRAM mac dinh bat dau tu 0x80000000.
 *    - Neu ban chay file nay nhu mot bare-metal test thong thuong (qua HTIF)
 *      thay vi nhu boot ROM that, cach pho bien la link toan bo (.text + .tohost)
 *      vao DRAM 0x80000000 -- khi do dat ORIGIN(ROM)=ORIGIN(RAM)=0x80000000.
 * ============================================================================= */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    /* boot ROM: chua code .text (rocket-chip thuong boot tu 0x10000) */
    ROM (rx)  : ORIGIN = 0x00010000, LENGTH = 192K

    /* RAM ghi duoc: chua section .tohost / .bss                       */
    RAM (rw)  : ORIGIN = 0x00040000, LENGTH = 128K
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
        *(.tohost)                  /* symbol tohost / fromhost  */
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
