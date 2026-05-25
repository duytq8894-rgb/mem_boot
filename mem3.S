/* =============================================================================
 *  mem3.S  --  Boot-ROM memory test cho loi Rocket (RISC-V RV32) -- viet tay
 * -----------------------------------------------------------------------------
 *  Toan bo code chay TRONG ROM tai 0x10000000. _start: cau hinh CSR custom,
 *  lam cac buoc set up kieu crt0, roi chay tiep vao phan test (khong nhay di).
 *
 *  BAN DO BO NHO:
 *    ROM 0x10000000 (256 KiB) : toan bo code (.text)
 *    RAM 0x80000000 (256 MiB) : .tohost ; .bss ; vung stack ; marker
 *    VUNG TEST : 0x80090000 .. 0x800A0000  (64 KiB, trong RAM)
 *    Marker cafebabe/deadbeef : 0x80008000  (xem ghi chu ben duoi)
 *
 *  CAC BUOC SET UP trong _start (trich tu crt0 mau, tru buoc nhay vao main):
 *    - csrwi 0x7c1,0      : cau hinh CSR custom (cache/feature) -- tu bootrom
 *    - magic 0xCAFEBABE   : ghi marker "bat dau" ra 0x80008000
 *    - sp = __stack_top   : lap stack pointer (symbol do link3.ld dinh nghia)
 *    - s0 = 0             : xoa frame pointer
 *    - mstatus.FS = 0b11  : bat FPU
 *    - xoa .bss           : ghi 0 tu __bss_start toi __bss_end
 *    (Buoc nap gp BI LOAI: mem3.S dung gp/x3 lam TESTNUM.)
 *    Khi PASS: ghi magic 0xDEADBEEF ra 0x80008000.
 *
 *  CAC PHASE (gp/x3 = TESTNUM) -- mot vung test duy nhat:
 *    2     : test do rong truy cap (sb/sh/sw, lb/lbu/lh/lhu/lw)
 *    3..6  : test 4 mau du lieu (0x00000000/FFFFFFFF/55555555/AAAAAAAA)
 *    7     : test dia-chi-la-du-lieu
 *    8     : fence
 *    9     : fence.i
 *
 *  KET QUA (chuan riscv-tests, qua symbol tohost):
 *    tohost = 1 -> PASS ; tohost = (TESTNUM<<1)|1 -> FAIL ; trap -> +0x1000.
 *
 *  BUILD:
 *    riscv32-unknown-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 \
 *        -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -Wl,--no-relax \
 *        -T link3.ld -o mem3.elf mem3.S
 *
 *  GHI CHU:
 *    - csrwi 0x7c1,0 : ghi 0 vao CSR custom 0x7c1 (cache/feature). Sua cho dung
 *      core cua ban.
 *    - Dia chi marker 0x80008000 chi la mac dinh -- doi cho dung testbench.
 *    - Code khong dung stack (sp duoc lap nhung phan test khong dung toi).
 * ============================================================================= */

    .option norelax                 /* gp dung lam TESTNUM -> cam linker relax gp */

/* =============================================================================
 *  DIEM VAO -- reset vector @ ROM 0x10000000.
 *  Cau hinh CSR custom -> cac buoc set up -> chay tiep vao test.
 * =========================================================================== */
    .section .text.init, "ax", @progbits
    .globl _start
    .align 2
_start:
    csrwi 0x7c1, 0                  /* cau hinh CSR custom 0x7c1 (cache/feature)*/

    csrr  t0, mhartid               /* chi hart 0 lam set up + chay test        */
    bnez  t0, park_hart

    /* ===== CAC BUOC SET UP (trich tu crt0, tru buoc nhay vao main) ===== */
    /* (1) magic marker "bat dau" = 0xCAFEBABE */
    li    t0, 0xCAFEBABE
    li    t1, 0x80008000            /* >>> SUA: dia chi marker neu can <<<     */
    sw    t0, 0(t1)
    /* (2) lap stack pointer = __stack_top (symbol trong link3.ld) */
    la    sp, __stack_top
    /* (3) xoa frame pointer s0 */
    li    s0, 0
    /* (4) bat FPU : mstatus.FS = 0b11 (0x6000) */
    li    t0, 0x6000
    csrs  mstatus, t0
    /* (5) xoa vung .bss ve 0 (tu __bss_start toi __bss_end) */
    la    t0, __bss_start
    la    t1, __bss_end
1:  bgeu  t0, t1, 2f                /* .bss rong -> bo qua                     */
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:
    /* ===== HET CAC BUOC SET UP ===== */

    csrw  mie, zero                 /* tat interrupt                           */
    la    t0, trap_handler
    csrw  mtvec, t0                 /* trap vector (direct mode)               */
    li    gp, 0                     /* TESTNUM = 0                             */
    j     main

park_hart:                          /* cac hart khac dung yen                  */
    wfi
    j     park_hart

/* =============================================================================
 *  THAN CHUONG TRINH TEST -- vung test 0x80090000 .. 0x800A0000 (64 KiB)
 * =========================================================================== */
    .section .text, "ax", @progbits
    .align 2
main:

/* ---- Phase 2 : test do rong truy cap -------------------------------------- */
    li    gp, 2
    li    a0, 0x80090100            /* dia chi scratch trong vung test        */
    /* byte khong dau */
    li    t1, 0xA5
    sb    t1, 0(a0)
    lbu   t2, 0(a0)
    bne   t2, t1, fail
    /* byte co dau: 0x80 -> mo rong dau = 0xFFFFFF80 */
    li    t1, 0x80
    sb    t1, 0(a0)
    lb    t2, 0(a0)
    li    t3, 0xFFFFFF80
    bne   t2, t3, fail
    /* halfword khong dau */
    li    t1, 0x1234
    sh    t1, 0(a0)
    lhu   t2, 0(a0)
    bne   t2, t1, fail
    /* halfword co dau: 0x8000 -> mo rong dau = 0xFFFF8000 */
    li    t1, 0x8000
    sh    t1, 0(a0)
    lh    t2, 0(a0)
    li    t3, 0xFFFF8000
    bne   t2, t3, fail
    /* word 32-bit */
    li    t1, 0x0123CDEF
    sw    t1, 0(a0)
    lw    t2, 0(a0)
    bne   t2, t1, fail
    li    t1, 0xC0DE1234
    sw    t1, 0(a0)
    lw    t2, 0(a0)
    bne   t2, t1, fail

/* ---- Phase 3 : mau 0x00000000 --------------------------------------------- */
    li    gp, 3
    li    t0, 0x80090000            /* con tro = dau vung                     */
    li    t1, 0x800A0000            /* dia chi cuoi (loai tru)                */
    li    a2, 0x00000000            /* mau du lieu                            */
1:  sw    a2, 0(t0)                 /* ghi mau ra toan vung                   */
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80090000
2:  lw    t3, 0(t0)                 /* doc lai va so sanh                     */
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 4 : mau 0xFFFFFFFF --------------------------------------------- */
    li    gp, 4
    li    t0, 0x80090000
    li    t1, 0x800A0000
    li    a2, 0xFFFFFFFF
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80090000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 5 : mau 0x55555555 --------------------------------------------- */
    li    gp, 5
    li    t0, 0x80090000
    li    t1, 0x800A0000
    li    a2, 0x55555555
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80090000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 6 : mau 0xAAAAAAAA --------------------------------------------- */
    li    gp, 6
    li    t0, 0x80090000
    li    t1, 0x800A0000
    li    a2, 0xAAAAAAAA
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80090000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 7 : test dia-chi-la-du-lieu ------------------------------------ */
    li    gp, 7
    li    t0, 0x80090000
    li    t1, 0x800A0000
1:  sw    t0, 0(t0)                 /* moi o luu chinh dia chi cua no         */
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80090000
2:  lw    t3, 0(t0)
    bne   t3, t0, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 8 : fence -- kiem tra ordering store/load ---------------------- */
    li    gp, 8
    li    a0, 0x80090000
    li    t1, 0x0FE00008
    sw    t1, 0(a0)
    fence                           /* store truoc fence hoan tat truoc load  */
    lw    t2, 0(a0)
    bne   t2, t1, fail

/* ---- Phase 9 : fence.i -- dong bo instruction stream ---------------------- */
    li    gp, 9
    fence.i

/* ---- Tat ca phase deu PASS ------------------------------------------------ */
    j     pass

/* =============================================================================
 *  BAO KET QUA
 * =========================================================================== */
    .align 2
pass:
    li    t0, 0xDEADBEEF            /* magic marker "ket thuc" -> 0x80008000  */
    li    t1, 0x80008000            /* >>> SUA: dia chi marker neu can <<<     */
    sw    t0, 0(t1)
    li    t0, 1                     /* tohost = 1 -> PASS                     */
    la    t1, tohost
    sw    t0, 0(t1)
    fence
1:  j     1b                        /* dung tai cho                           */

    .align 2
fail:
    slli  gp, gp, 1                 /* tohost = (TESTNUM << 1) | 1            */
    ori   gp, gp, 1
    la    t1, tohost
    sw    gp, 0(t1)
    fence
1:  j     1b

/* -----------------------------------------------------------------------------
 *  TRAP HANDLER -- moi trap bat thuong deu coi la FAIL.
 *  mcause giu trong t0 de debug ; TESTNUM (gp) cong them 0x1000.
 * --------------------------------------------------------------------------- */
    .align 2
trap_handler:
    csrr  t0, mcause                /* t0 = ly do trap                        */
    li    t1, 0x1000
    add   gp, gp, t1                /* danh dau loi do trap tai phase gp      */
    j     fail

/* =============================================================================
 *  HOST INTERFACE -- tohost/fromhost nam o RAM (xem link3.ld).
 *  Giu 8 byte (chuan HTIF 64-bit) ; RV32 ghi 32-bit thap bang sw.
 * =========================================================================== */
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .quad 0
    .align 6
    .globl fromhost
fromhost:
    .quad 0
