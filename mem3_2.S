/* =============================================================================
 *  mem3.S  --  Bootrom + Memory test cho loi Rocket (RISC-V RV32) -- viet tay
 * -----------------------------------------------------------------------------
 *  File nay gom HAI phan, nam o HAI vung bo nho khac nhau:
 *
 *   (1) BOOTROM  -- section .text.start, dat tai ROM 0x10000000 (reset vector).
 *       Day la _start cua bootrom chuan: cau hinh CSR custom 0x7c1 roi NHAY
 *       toi 0x80000000. Tuong ung doan disassembly 100000..100016.
 *
 *   (2) MEMORY TEST -- section .text, dat tai RAM 0x80000000.
 *       Bootrom nhay toi day. Day moi la code test bo nho thuc su (_test_start).
 *
 *  BAN DO BO NHO:
 *    ROM 0x10000000 (256 KiB) : bootrom (.text.start) + DTB (.rodata.dtb)
 *    RAM 0x80000000 (256 MiB) :
 *        0x80000000  : code test (.text) -- bootrom nhay vao day
 *        sau do      : .tohost
 *        0x80010000..0x80020000 : vung test CACHED (64 KiB)
 *    UNCACHED 0x90000000..0x90001000 (4 KiB)  <-- SUA cho SoC cua ban
 *
 *  CAC PHASE (so phase luu trong gp/x3 = TESTNUM):
 *    2      : test do rong truy cap (sb/sh/sw, lb/lbu/lh/lhu/lw) -- CACHED
 *    3..6   : test 4 mau du lieu (0x00000000/FFFFFFFF/55555555/AAAAAAAA) -- CACHED
 *    7      : test dia-chi-la-du-lieu -- CACHED
 *    8      : test do rong truy cap -- UNCACHED
 *    9..12  : test 4 mau du lieu -- UNCACHED
 *    13     : test dia-chi-la-du-lieu -- UNCACHED
 *    14     : fence
 *    15     : fence.i
 *
 *  KET QUA (chuan riscv-tests, qua symbol tohost):
 *    tohost = 1 -> PASS ; tohost = (TESTNUM<<1)|1 -> FAIL ; trap -> +0x1000.
 *
 *  BUILD:
 *    riscv32-unknown-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 \
 *        -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -Wl,--no-relax \
 *        -T link3.ld -o mem3.elf mem3.S
 *    -> Nap file mem3.elf TRUC TIEP vao testbench (ELF co 2 vung ROM+RAM).
 *       KHONG dung objcopy -O binary: khoang trong giua 0x10000000 va 0x80000000
 *       se tao file nhi phan rat lon.
 *
 *  GHI CHU:
 *    - addiw (RV64) trong disassembly goc -> tren RV32 chi can `li s0,0x80000000`
 *      (mot lenh lui). Chuc nang giong het: s0 = 0x80000000.
 *    - 0x7c1 la CSR custom cua core (vd Feature Disable CSR cua SiFive: ghi 0 =
 *      bat cache/prefetch/...). Sua gia tri/CSR cho dung core cua ban.
 *    - Code khong dung stack.
 * ============================================================================= */

    .option norelax                 /* gp dung lam TESTNUM -> cam linker relax gp */

/* =============================================================================
 *  (1) BOOTROM  -- section .text.start, dat tai ROM 0x10000000 (reset vector).
 *      Tuong ung doan code 100000..100016 trong disassembly bootrom.elf.
 * =========================================================================== */
    .section .text.start, "ax", @progbits
    .globl _start
    .align 2
_start:
    csrwi 0x7c1, 0                  /* 100000: cau hinh CSR custom 0x7c1 = 0   */
    li    s0, 0x80000000            /* 100004+100008: s0 = dia chi nhay toi    */
    csrr  a0, mhartid               /* 10000a: a0 = hart id                    */
    la    a1, _dtb                  /* 10000e+100012: a1 = con tro DTB         */
    jr    s0                        /* 100016: nhay toi 0x80000000             */

/* -----------------------------------------------------------------------------
 *  DTB placeholder -- bootrom truyen con tro nay qua a1; code test bo qua a1.
 *  Thay bang Device Tree Blob that neu he thong cua ban can.
 * --------------------------------------------------------------------------- */
    .section .rodata.dtb, "a", @progbits
    .globl _dtb
    .align 5
_dtb:
    .ascii "DTB-PLACEHOLDER"
    .byte  0

/* =============================================================================
 *  (2) MEMORY TEST -- section .text, dat tai RAM 0x80000000.
 *      Bootrom o tren nhay toi _test_start (= 0x80000000).
 * =========================================================================== */
    .section .text, "ax", @progbits
    .globl _test_start
    .align 2
_test_start:
    csrr  t0, mhartid               /* chi hart 0 chay test                   */
    bnez  t0, park_hart
    csrw  mie, zero                 /* tat interrupt                          */
    la    t0, trap_handler
    csrw  mtvec, t0                 /* trap vector (direct mode)              */
    li    gp, 0                     /* TESTNUM = 0                            */
    j     main

park_hart:                          /* cac hart khac dung yen                 */
    wfi
    j     park_hart

main:

/* ---- Phase 2 : test do rong truy cap -- vung CACHED ----------------------- */
    li    gp, 2
    li    a0, 0x80010100            /* dia chi scratch trong vung cached      */
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

/* ---- Phase 3 : mau 0x00000000 -- vung CACHED ------------------------------ */
    li    gp, 3
    li    t0, 0x80010000            /* con tro = dau vung                     */
    li    t1, 0x80020000            /* dia chi cuoi (loai tru)                */
    li    a2, 0x00000000            /* mau du lieu                            */
1:  sw    a2, 0(t0)                 /* ghi mau ra toan vung                   */
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80010000
2:  lw    t3, 0(t0)                 /* doc lai va so sanh                     */
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 4 : mau 0xFFFFFFFF -- vung CACHED ------------------------------ */
    li    gp, 4
    li    t0, 0x80010000
    li    t1, 0x80020000
    li    a2, 0xFFFFFFFF
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80010000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 5 : mau 0x55555555 -- vung CACHED ------------------------------ */
    li    gp, 5
    li    t0, 0x80010000
    li    t1, 0x80020000
    li    a2, 0x55555555
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80010000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 6 : mau 0xAAAAAAAA -- vung CACHED ------------------------------ */
    li    gp, 6
    li    t0, 0x80010000
    li    t1, 0x80020000
    li    a2, 0xAAAAAAAA
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80010000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 7 : test dia-chi-la-du-lieu -- vung CACHED --------------------- */
    li    gp, 7
    li    t0, 0x80010000
    li    t1, 0x80020000
1:  sw    t0, 0(t0)                 /* moi o luu chinh dia chi cua no         */
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x80010000
2:  lw    t3, 0(t0)
    bne   t3, t0, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 8 : test do rong truy cap -- vung UNCACHED --------------------- */
    li    gp, 8
    li    a0, 0x90000000            /* dia chi scratch trong vung uncached    */
    /* byte khong dau */
    li    t1, 0xA5
    sb    t1, 0(a0)
    lbu   t2, 0(a0)
    bne   t2, t1, fail
    /* byte co dau */
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
    /* halfword co dau */
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

/* ---- Phase 9 : mau 0x00000000 -- vung UNCACHED ---------------------------- */
    li    gp, 9
    li    t0, 0x90000000
    li    t1, 0x90001000
    li    a2, 0x00000000
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x90000000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 10 : mau 0xFFFFFFFF -- vung UNCACHED --------------------------- */
    li    gp, 10
    li    t0, 0x90000000
    li    t1, 0x90001000
    li    a2, 0xFFFFFFFF
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x90000000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 11 : mau 0x55555555 -- vung UNCACHED --------------------------- */
    li    gp, 11
    li    t0, 0x90000000
    li    t1, 0x90001000
    li    a2, 0x55555555
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x90000000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 12 : mau 0xAAAAAAAA -- vung UNCACHED --------------------------- */
    li    gp, 12
    li    t0, 0x90000000
    li    t1, 0x90001000
    li    a2, 0xAAAAAAAA
1:  sw    a2, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x90000000
2:  lw    t3, 0(t0)
    bne   t3, a2, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 13 : test dia-chi-la-du-lieu -- vung UNCACHED ------------------ */
    li    gp, 13
    li    t0, 0x90000000
    li    t1, 0x90001000
1:  sw    t0, 0(t0)
    addi  t0, t0, 4
    bltu  t0, t1, 1b
    fence
    li    t0, 0x90000000
2:  lw    t3, 0(t0)
    bne   t3, t0, fail
    addi  t0, t0, 4
    bltu  t0, t1, 2b

/* ---- Phase 14 : fence -- kiem tra ordering store/load --------------------- */
    li    gp, 14
    li    a0, 0x80010000
    li    t1, 0x0FE00014
    sw    t1, 0(a0)
    fence                           /* store truoc fence hoan tat truoc load  */
    lw    t2, 0(a0)
    bne   t2, t1, fail

/* ---- Phase 15 : fence.i -- dong bo instruction stream --------------------- */
    li    gp, 15
    fence.i

/* ---- Tat ca phase deu PASS ------------------------------------------------ */
    j     pass

/* =============================================================================
 *  BAO KET QUA
 * =========================================================================== */
    .align 2
pass:
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
 *  HOST INTERFACE -- tohost/fromhost nam trong RAM (sau .text), xem link3.ld.
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
