/* ==========================================================================
 *  link.ld  --  Linker script cho rvv_csr_demo.S  (rv64imafdcv, bare-metal)
 *
 *  Phu hop voi QEMU 'virt' machine:
 *      DRAM bat dau tai 0x8000_0000
 *
 *  Build:
 *    riscv64-unknown-elf-gcc -march=rv64imafdcv -mabi=lp64d \
 *        -nostdlib -nostartfiles -static \
 *        -T link.ld rvv_csr_demo.S -o rvv_csr_demo.elf
 *
 *  Chay (bare-metal, M-mode):
 *    qemu-system-riscv64 -machine virt -nographic -bios none \
 *        -cpu rv64,v=true,vlen=128 -kernel rvv_csr_demo.elf
 * ========================================================================== */

OUTPUT_ARCH( "riscv" )
ENTRY( _start )

/* --- Bo nho vat ly --------------------------------------------------------- */
MEMORY
{
    RAM (rwxa) : ORIGIN = 0x80000000, LENGTH = 128M
}

/* Kich thuoc stack danh cho chuong trinh */
__stack_size = 0x4000;     /* 16 KiB */

SECTIONS
{
    . = ORIGIN(RAM);

    /* ------------------------------------------------------------------ */
    /* Code                                                               */
    /* ------------------------------------------------------------------ */
    .text : ALIGN(4)
    {
        PROVIDE(__text_start = .);
        *(.text.init)        /* entry _start neu dat trong section rieng  */
        *(.text)
        *(.text.*)
        . = ALIGN(4);
        PROVIDE(__text_end = .);
    } > RAM

    /* ------------------------------------------------------------------ */
    /* Read-only data                                                     */
    /* ------------------------------------------------------------------ */
    .rodata : ALIGN(8)
    {
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(8);
    } > RAM

    /* ------------------------------------------------------------------ */
    /* Initialized data  (vec_a, vec_b ...)                               */
    /* ------------------------------------------------------------------ */
    .data : ALIGN(64)        /* align 64 cho du lieu vector               */
    {
        PROVIDE(__data_start = .);
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(8);
        PROVIDE(__data_end = .);
    } > RAM

    /* ------------------------------------------------------------------ */
    /* BSS  (vec_out / .zero)                                             */
    /* ------------------------------------------------------------------ */
    .bss (NOLOAD) : ALIGN(64)
    {
        PROVIDE(__bss_start = .);
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(8);
        PROVIDE(__bss_end = .);
    } > RAM

    /* ------------------------------------------------------------------ */
    /* Stack  (m`oc tu tren xuong)                                        */
    /* ------------------------------------------------------------------ */
    .stack (NOLOAD) : ALIGN(16)
    {
        PROVIDE(__stack_bottom = .);
        . += __stack_size;
        . = ALIGN(16);
        PROVIDE(__stack_top = .);
    } > RAM

    PROVIDE(__heap_start = .);
    PROVIDE(end = .);

    /* Loai bo cac section khong can thiet */
    /DISCARD/ :
    {
        *(.comment)
        *(.note)
        *(.note.*)
        *(.eh_frame)
        *(.eh_frame_hdr)
    }
}
