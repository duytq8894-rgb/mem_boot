/* =============================================================================
 *  mem_test.S  --  Boot-ROM memory self-test cho loi Rocket (RISC-V, RV32)
 * -----------------------------------------------------------------------------
 *  CHUC NANG  (cac phase danh so lien tuc 2..19)
 *    Phase 2      : test truy cap theo do rong (sb/sh/sw, lb/lbu/lh/lhu/lw,
 *                   ca sign-extend) -- vung CACHED
 *    Phase 3..6   : test 4 mau du lieu (0x00000000/0xFFFFFFFF/0x55555555/
 *                   0xAAAAAAAA) -- vung CACHED
 *    Phase 7      : test "dia-chi-la-du-lieu" (phat hien loi addressing) -- CACHED
 *    Phase 8      : test truy cap theo do rong -- vung UNCACHED
 *    Phase 9..12  : test 4 mau du lieu -- vung UNCACHED
 *    Phase 13     : test "dia-chi-la-du-lieu" -- vung UNCACHED
 *    Phase 14     : fence      -- kiem tra ordering store/load
 *    Phase 15     : fence.i    -- dong bo instruction stream
 *    Phase 16..19 : cbo.clean/flush/inval/zero  -- CHI khi ENABLE_CMO = 1
 *
 *  BAO KET QUA  (chuan riscv-tests, qua symbol `tohost`)
 *    tohost == 1                  -> PASS
 *    tohost == (TESTNUM << 1) | 1 -> FAIL tai buoc TESTNUM (luu trong gp/x3)
 *    Neu FAIL do TRAP bat thuong  -> TESTNUM duoc cong them 0x1000
 *                                    (doc CSR mcause -- giu trong t0 -- de biet
 *                                     ly do: 1=instr access, 2=illegal instr,
 *                                     5=load access, 7=store access ...)
 *
 *  BUILD  (RV32)
 *    riscv32-unknown-elf-gcc -march=rv32imc_zicsr -mabi=ilp32 -mcmodel=medany \
 *        -nostdlib -nostartfiles -ffreestanding -Wl,--no-relax \
 *        -T link.ld -o mem_test.elf mem_test.S
 *    riscv32-unknown-elf-objcopy -O binary mem_test.elf mem_test.bin
 *    (_zicsr can cho lenh CSR csrr/csrw tren toolchain moi. Co the dung
 *     riscv64-unknown-elf-gcc voi cung -march/-mabi neu co rv32 multilib.)
 *
 *  GHI CHU CHO ROCKET (RV32)
 *    - Phien ban RV32: CHI dung lw/sw (truy cap 32-bit). KHONG dung ld/sd 64-bit
 *      => KHONG can extension Zilsd. Do rong truy cap lon nhat la 32-bit (word).
 *    - Da bo extension A: KHONG test AMO / LR-SC.
 *    - Rocket "co dien" KHONG implement CMO (Zicbom/Zicboz) => ENABLE_CMO mac
 *      dinh = 0; chi bat = 1 neu config Chipyard/rocket-chip cua ban CO Zicbom/
 *      Zicboz (neu khong, cbo.* se trap illegal-instruction).
 *    - Cac lenh CBO.* va FENCE.I duoc ma hoa bang `.insn` => build duoc voi MOI
 *      toolchain rv32, khong phu thuoc -march co _zicbom/_zicboz/_zifencei.
 *    - Toan bo code KHONG dung stack (stackless) => an toan chay tu boot ROM.
 * ============================================================================= */

    .option norelax                 /* gp/x3 dung lam TESTNUM -> cam linker relax */

/* -----------------------------------------------------------------------------
 *  CAU HINH -- SUA CAC HANG SO NAY CHO SoC CUA BAN
 * --------------------------------------------------------------------------- */
    .equ  CACHED_BASE,    0x00080000     /* vung cached : dia chi dau            */
    .equ  CACHED_END,     0x00090000     /* vung cached : dia chi cuoi (loai tru)*/

    /* >>> EDIT: dien base + size vung UNCACHED (phai la RAM uncached,        */
    /*           khong phai thanh ghi thiet bi I/O)                          <<< */
    .equ  UNCACHED_BASE,  0x00100000
    .equ  UNCACHED_SIZE,  0x00001000     /* 4 KiB                                */
    .equ  UNCACHED_END,   UNCACHED_BASE + UNCACHED_SIZE

    .equ  CACHE_LINE,     64             /* kich thuoc cache block Zicbom/Zicboz */
    .equ  ENABLE_CMO,     0              /* Rocket co dien KHONG co CMO -> de 0   */
                                         /* (=1 neu config co them Zicbom/Zicboz) */
    .equ  TRAP_MARK,      0x1000         /* cong vao TESTNUM khi gap trap        */

    /* dia chi scratch cho test do rong (1 token -> tranh loi tach macro arg) */
    .equ  CACHED_WTEST,   CACHED_BASE + 0x100

/* -----------------------------------------------------------------------------
 *  MACRO -- lenh quan ly cache, ma hoa thu cong bang `.insn`
 *  MISC-MEM opcode = 0x0F ; funct3 = 0x2 (CBO) / 0x1 (FENCE.I) ; rd = x0
 *    cbo.inval imm=0x0 ; cbo.clean imm=0x1 ; cbo.flush imm=0x2 ; cbo.zero imm=0x4
 * --------------------------------------------------------------------------- */
    .macro CBO_INVAL reg
    .insn i 0x0F, 0x2, x0, 0x0(\reg)     /* cbo.inval (\reg) */
    .endm
    .macro CBO_CLEAN reg
    .insn i 0x0F, 0x2, x0, 0x1(\reg)     /* cbo.clean (\reg) */
    .endm
    .macro CBO_FLUSH reg
    .insn i 0x0F, 0x2, x0, 0x2(\reg)     /* cbo.flush (\reg) */
    .endm
    .macro CBO_ZERO reg
    .insn i 0x0F, 0x2, x0, 0x4(\reg)     /* cbo.zero  (\reg) */
    .endm
    .macro FENCE_I
    .insn i 0x0F, 0x1, x0, 0x0(x0)       /* fence.i */
    .endm

/* -----------------------------------------------------------------------------
 *  MACRO -- ghi 1 mau du lieu (32-bit) ra ca vung [baseC, endC) roi doc lai.
 *  patReg : thanh ghi chua san mau 32-bit.   Dung tam t0/t1/t2.   Buoc = 4 byte.
 * --------------------------------------------------------------------------- */
    .macro MT_PATTERN baseC, endC, patReg
    li    t0, \baseC
    li    t1, \endC
.Lpw\@:
    sw    \patReg, 0(t0)             /* ghi mau (32-bit)                       */
    addi  t0, t0, 4
    bltu  t0, t1, .Lpw\@
    fence                           /* dam bao store hoan tat truoc khi doc   */
    li    t0, \baseC
.Lpr\@:
    lw    t2, 0(t0)                 /* doc lai                                */
    bne   t2, \patReg, fail         /* khac mau -> FAIL                       */
    addi  t0, t0, 4
    bltu  t0, t1, .Lpr\@
    .endm

/* -----------------------------------------------------------------------------
 *  MACRO -- ghi "dia chi lam du lieu" ra ca vung roi doc lai doi chieu.
 *  Phat hien loi giai ma dia chi (address aliasing / stuck address bit).
 * --------------------------------------------------------------------------- */
    .macro MT_ADDR baseC, endC
    li    t0, \baseC
    li    t1, \endC
.Law\@:
    sw    t0, 0(t0)                 /* moi o nho luu chinh dia chi cua no     */
    addi  t0, t0, 4
    bltu  t0, t1, .Law\@
    fence
    li    t0, \baseC
.Lar\@:
    lw    t2, 0(t0)
    bne   t2, t0, fail
    addi  t0, t0, 4
    bltu  t0, t1, .Lar\@
    .endm

/* -----------------------------------------------------------------------------
 *  MACRO -- test do rong truy cap tai 1 dia chi (can chia het cho 4).
 *  Kiem tra sb/sh/sw va lb/lbu/lh/lhu/lw (gom ca sign-extend).
 *  RV32: do rong lon nhat la 32-bit (word) -- khong co doubleword.
 * --------------------------------------------------------------------------- */
    .macro MT_WIDTH addrC
    li    a0, \addrC
    /* --- byte: unsigned --- */
    li    t1, 0xA5
    sb    t1, 0(a0)
    lbu   t2, 0(a0)
    bne   t2, t1, fail
    /* --- byte: signed (0x80 -> sign-extend = 0xFFFFFF80) --- */
    li    t1, 0x80
    sb    t1, 0(a0)
    lb    t2, 0(a0)
    li    t3, -128
    bne   t2, t3, fail
    /* --- halfword: unsigned --- */
    li    t1, 0x1234
    sh    t1, 0(a0)
    lhu   t2, 0(a0)
    bne   t2, t1, fail
    /* --- halfword: signed (0x8000 -> sign-extend = 0xFFFF8000) --- */
    li    t1, 0x8000
    sh    t1, 0(a0)
    lh    t2, 0(a0)
    li    t3, 0xFFFF8000
    bne   t2, t3, fail
    /* --- word (32-bit): bit31 = 0 --- */
    li    t1, 0x0123CDEF
    sw    t1, 0(a0)
    lw    t2, 0(a0)
    bne   t2, t1, fail
    /* --- word (32-bit): bit31 = 1 --- */
    li    t1, 0xC0DE1234
    sw    t1, 0(a0)
    lw    t2, 0(a0)
    bne   t2, t1, fail
    .endm

/* =============================================================================
 *  DIEM VAO -- reset vector
 * =========================================================================== */
    .section .text.init, "ax", @progbits
    .globl _start
    .align 2
_start:
    csrr  t0, mhartid               /* chi hart 0 chay test                   */
    bnez  t0, park_hart
    csrw  mie, zero                 /* tat interrupt                          */
    la    t0, trap_handler
    csrw  mtvec, t0                 /* trap vector, direct mode (2 bit thap=0)*/
    li    gp, 0                     /* TESTNUM = 0                            */
    j     main

park_hart:                          /* cac hart khac dung yen                 */
    wfi
    j     park_hart

/* =============================================================================
 *  THAN CHUONG TRINH TEST
 * =========================================================================== */
    .section .text, "ax", @progbits
    .align 2
main:
/* ---- Phase 2 : truy cap theo do rong -- vung CACHED ------------------------ */
    li    gp, 2
    MT_WIDTH CACHED_WTEST

/* ---- Phase 3..6 : 4 mau du lieu -- vung CACHED ----------------------------- */
    li    gp, 3
    li    a4, 0x00000000
    MT_PATTERN CACHED_BASE, CACHED_END, a4
    li    gp, 4
    li    a4, 0xFFFFFFFF
    MT_PATTERN CACHED_BASE, CACHED_END, a4
    li    gp, 5
    li    a4, 0x55555555
    MT_PATTERN CACHED_BASE, CACHED_END, a4
    li    gp, 6
    li    a4, 0xAAAAAAAA
    MT_PATTERN CACHED_BASE, CACHED_END, a4

/* ---- Phase 7 : dia-chi-la-du-lieu -- vung CACHED --------------------------- */
    li    gp, 7
    MT_ADDR CACHED_BASE, CACHED_END

/* ---- Phase 8 : truy cap theo do rong -- vung UNCACHED ---------------------- */
    li    gp, 8
    MT_WIDTH UNCACHED_BASE

/* ---- Phase 9..12 : 4 mau du lieu -- vung UNCACHED -------------------------- */
    li    gp, 9
    li    a4, 0x00000000
    MT_PATTERN UNCACHED_BASE, UNCACHED_END, a4
    li    gp, 10
    li    a4, 0xFFFFFFFF
    MT_PATTERN UNCACHED_BASE, UNCACHED_END, a4
    li    gp, 11
    li    a4, 0x55555555
    MT_PATTERN UNCACHED_BASE, UNCACHED_END, a4
    li    gp, 12
    li    a4, 0xAAAAAAAA
    MT_PATTERN UNCACHED_BASE, UNCACHED_END, a4

/* ---- Phase 13 : dia-chi-la-du-lieu -- vung UNCACHED ------------------------ */
    li    gp, 13
    MT_ADDR UNCACHED_BASE, UNCACHED_END

/* ---- Phase 14 : fence -- ordering store/load ------------------------------ */
    li    gp, 14
    li    a0, CACHED_BASE
    li    t1, 0x0FE00014
    sw    t1, 0(a0)
    fence                           /* moi store/load truoc hoan tat truoc    */
    lw    t2, 0(a0)
    bne   t2, t1, fail

/* ---- Phase 15 : fence.i -- dong bo instruction stream --------------------- */
    li    gp, 15
    FENCE_I

.if ENABLE_CMO
/* ===========================================================================
 *  LENH QUAN LY CACHE (Zicbom/Zicboz) -- chi chay khi ENABLE_CMO = 1.
 *  Rocket co dien KHONG ho tro -> mac dinh phan nay bi tat.
 * ========================================================================= */
/* ---- Phase 16 : cbo.clean -- write-back, dong cache van hop le ------------- */
    li    gp, 16
    li    a0, CACHED_BASE + 0*CACHE_LINE
    li    t1, 0x0C1EA016
    sw    t1, 0(a0)
    fence
    CBO_CLEAN a0                    /* day du lieu dirty xuong bo nho         */
    fence
    lw    t2, 0(a0)                 /* clean KHONG invalidate -> du lieu con  */
    bne   t2, t1, fail

/* ---- Phase 17 : cbo.flush -- write-back + invalidate ----------------------- */
    li    gp, 17
    li    a0, CACHED_BASE + 1*CACHE_LINE
    li    t1, 0x0F105017
    sw    t1, 0(a0)
    fence
    CBO_FLUSH a0                    /* write-back roi invalidate dong cache   */
    fence
    lw    t2, 0(a0)                 /* lan doc nay nap lai tu bo nho          */
    bne   t2, t1, fail

/* ---- Phase 18 : cbo.inval -- invalidate dong SACH ------------------------- */
    li    gp, 18
    li    a0, CACHED_BASE + 2*CACHE_LINE
    li    t1, 0x01A0E018
    sw    t1, 0(a0)
    fence
    CBO_CLEAN a0                    /* dua du lieu xuong bo nho -> dong sach   */
    fence
    CBO_INVAL a0                    /* bo ban sao sach (khong mat du lieu)    */
    fence
    lw    t2, 0(a0)                 /* nap lai tu bo nho -> phai dung          */
    bne   t2, t1, fail

/* ---- Phase 19 : cbo.zero -- ghi 0 nguyen mot cache block ------------------ */
    li    gp, 19
    li    a0, CACHED_BASE + 3*CACHE_LINE
    li    t1, 0xFFFFFFFF
    addi  t3, a0, CACHE_LINE        /* t3 = cuoi block                        */
    mv    t0, a0
.Lzfill:
    sw    t1, 0(t0)                 /* do day block bang gia tri khac 0       */
    addi  t0, t0, 4
    bltu  t0, t3, .Lzfill
    fence
    CBO_ZERO a0                     /* zero ca block                          */
    fence
    mv    t0, a0
.Lzchk:
    lw    t2, 0(t0)                 /* moi word phai = 0                      */
    bnez  t2, fail
    addi  t0, t0, 4
    bltu  t0, t3, .Lzchk
.endif

/* ---- Tat ca phase PASS ---------------------------------------------------- */
    j     pass

/* =============================================================================
 *  BAO KET QUA
 * =========================================================================== */
    .align 2
pass:
    li    t0, 1                     /* tohost = 1 -> PASS                     */
    la    t1, tohost
    sw    t0, 0(t1)                 /* RV32: ghi 32-bit thap cua tohost       */
    fence
1:  j     1b                        /* dung tai cho                           */

    .align 2
fail:
    slli  gp, gp, 1                 /* tohost = (TESTNUM << 1) | 1 -> FAIL    */
    ori   gp, gp, 1
    la    t1, tohost
    sw    gp, 0(t1)
    fence
1:  j     1b

/* -----------------------------------------------------------------------------
 *  TRAP HANDLER -- moi trap bat thuong deu coi la FAIL.
 *  mcause duoc giu trong t0 de debug; TESTNUM (gp) cong them TRAP_MARK.
 * --------------------------------------------------------------------------- */
    .align 2
trap_handler:
    csrr  t0, mcause                /* t0 = ly do trap (de quan sat)          */
    li    t1, TRAP_MARK
    add   gp, gp, t1                /* danh dau: loi do trap tai phase gp     */
    j     fail

/* =============================================================================
 *  HOST INTERFACE -- dat trong RAM ghi duoc (xem link.ld)
 *  tohost/fromhost giu 8 byte (chuan HTIF 64-bit); RV32 ghi 32-bit thap bang sw.
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
