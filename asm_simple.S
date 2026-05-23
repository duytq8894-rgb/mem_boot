# =============================================================================
# mem_test.S
# -----------------------------------------------------------------------------
# RISC-V memory access test  (RV32I  -  KHONG dung extension A va C)
# Tuong thich voi link.ld:
#       ROM : ORIGIN = 0x00100000, LENGTH = 256K   (chua .text.start)
#       RAM : ORIGIN = 0x80000000, LENGTH = 256M   (chua .tohost / .bss)
#
# Noi dung test:
#   T1  - Ghi/Doc cached DRAM (1 word)
#   T2  - Burst 16 word lien tiep + fence w,w  (kiem tra flush du lieu)
#   T3  - Truy cap byte/halfword/word (sb/sh/sw, lb/lbu/lh/lhu/lw)
#   T4  - Cac bien the cua fence (r,r / w,w / rw,rw / iorw,iorw / mac dinh)
#   T5  - fence.i  - dong bo I-cache / instruction stream
#   T6  - Ghi/Doc uncached MMIO  (chinh UNCACHED_BASE neu can)
#   T7  - Xen ke cached + uncached + fence rw,rw
#
# Ket qua bao ve qua mailbox tohost (chuan riscv-tests):
#   tohost = 1                   -> PASS
#   tohost = (test_id << 1) | 1  -> FAIL  (test_id luu trong a0 khi loi)
# =============================================================================

    .option norvc                   # CAM phat instruction nen 16-bit (no C)

# ----- Memory map constants --------------------------------------------------
    .equ CACHED_BASE,   0x80000000  # vung DRAM cached
    .equ UNCACHED_BASE, 0x10000000  # vung MMIO uncached -- chinh lai neu khac
    .equ STACK_TOP,     0x80100000  # day stack tai 1 MiB tinh tu dau RAM

# =============================================================================
# Text section - bat buoc dat trong .text.start de linker script KEEP
# =============================================================================
    .section .text.start, "ax", @progbits
    .global _start
    .type   _start, @function

_start:
    # ------- Khoi tao toi thieu -------------------------------------------
    li      sp, STACK_TOP           # stack pointer
    li      gp, 0                   # tat thread pointer / global ptr

    # =====================================================================
    # T1 : Ghi/Doc 1 word vao vung cached
    # =====================================================================
test1:
    li      a0, 1                   # test id (de bao loi)
    li      t0, CACHED_BASE
    li      t1, 0xDEADBEEF
    sw      t1, 0(t0)               # store word
    fence   rw, rw                  # bao dam thu tu truoc khi load
    lw      t2, 0(t0)               # load back
    bne     t1, t2, fail

    # =====================================================================
    # T2 : Ghi lien tiep 16 word -> fence w,w -> doc kiem tra
    # =====================================================================
test2:
    li      a0, 2
    li      t0, CACHED_BASE + 0x100 # base cho khoi du lieu
    li      t1, 0xA5A5A5A5
    li      t3, 16                  # so word can ghi
t2_wr:
    sw      t1, 0(t0)
    addi    t0, t0, 4
    addi    t3, t3, -1
    bnez    t3, t2_wr

    fence   w, w                    # flush tat ca write pending

    # doc lai kiem tra
    li      t0, CACHED_BASE + 0x100
    li      t3, 16
t2_rd:
    lw      t2, 0(t0)
    bne     t1, t2, fail
    addi    t0, t0, 4
    addi    t3, t3, -1
    bnez    t3, t2_rd

    # =====================================================================
    # T3 : Truy cap byte / halfword / word
    # =====================================================================
test3:
    li      a0, 3
    li      t0, CACHED_BASE + 0x200

    # ---- 4 lan sb: little-endian -> word = 0xABCDEF12 ----
    li      t1, 0x12
    sb      t1, 0(t0)
    li      t1, 0xEF
    sb      t1, 1(t0)
    li      t1, 0xCD
    sb      t1, 2(t0)
    li      t1, 0xAB
    sb      t1, 3(t0)
    fence   rw, rw
    lw      t2, 0(t0)
    li      t4, 0xABCDEF12
    bne     t2, t4, fail

    # ---- 2 lan sh ----
    li      t1, 0x1234
    sh      t1, 4(t0)
    li      t1, 0x5678
    sh      t1, 6(t0)
    fence   rw, rw
    lw      t2, 4(t0)
    li      t4, 0x56781234
    bne     t2, t4, fail

    # ---- lb / lbu kiem tra sign-extend ----
    lbu     t2, 0(t0)               # 0x00000012
    li      t4, 0x00000012
    bne     t2, t4, fail
    lb      t2, 3(t0)               # 0xAB -> sign ext -> 0xFFFFFFAB
    li      t4, 0xFFFFFFAB
    bne     t2, t4, fail

    # ---- lh / lhu ----
    lhu     t2, 4(t0)               # 0x00001234
    li      t4, 0x00001234
    bne     t2, t4, fail
    lh      t2, 6(t0)               # 0x5678 -> sign ext -> 0x00005678
    li      t4, 0x00005678
    bne     t2, t4, fail

    # =====================================================================
    # T4 : Cac bien the FENCE  (chi exercise pipeline, khong kiem tra state)
    # =====================================================================
test4:
    li      a0, 4
    fence   r,    r
    fence   w,    w
    fence   rw,   rw
    fence   iorw, iorw
    fence                           # mac dinh = iorw, iorw

    # =====================================================================
    # T5 : FENCE.I  (dong bo instruction stream / I-cache)
    # =====================================================================
test5:
    li      a0, 5
    # Ghi 1 pattern vao 1 vung "code-like" trong RAM (chi de test fence.i;
    # khong jump vao vi RAM la non-executable trong linker script)
    li      t0, CACHED_BASE + 0x400
    li      t1, 0x00000013          # nop (RV32I)
    sw      t1, 0(t0)
    fence   w, w                    # bao dam write hoan tat
    fence.i                         # invalidate I-fetch buffer
    lw      t2, 0(t0)
    bne     t1, t2, fail

    # =====================================================================
    # T6 : Vung UNCACHED  (MMIO / peripheral)
    # =====================================================================
test6:
    li      a0, 6
    li      t0, UNCACHED_BASE
    li      t1, 0xCAFEBABE
    sw      t1, 0(t0)
    fence   rw, rw                  # bat buoc voi I/O
    lw      t2, 0(t0)
    bne     t1, t2, fail

    # =====================================================================
    # T7 : Xen ke cached + uncached + fence
    # =====================================================================
test7:
    li      a0, 7
    li      t0, CACHED_BASE   + 0x300
    li      t5, UNCACHED_BASE + 0x10
    li      t1, 0x11111111
    li      t6, 0x22222222

    sw      t1, 0(t0)               # store cached
    sw      t6, 0(t5)               # store uncached
    fence   rw, rw                  # full ordering

    lw      t2, 0(t0)
    bne     t1, t2, fail
    lw      t2, 0(t5)
    bne     t6, t2, fail

# =============================================================================
# PASS:  tohost = 1
# =============================================================================
pass:
    li      a0, 0                   # bao no error
    la      t0, tohost
    li      t1, 1
    sw      t1, 0(t0)
    sw      zero, 4(t0)             # clear upper 32-bit cua dword tohost
    fence   rw, rw
hang_pass:
    j       hang_pass

# =============================================================================
# FAIL:  tohost = (a0 << 1) | 1   (a0 = test id bi loi)
# =============================================================================
fail:
    slli    a0, a0, 1
    ori     a0, a0, 1
    la      t0, tohost
    sw      a0, 0(t0)
    sw      zero, 4(t0)
    fence   rw, rw
hang_fail:
    j       hang_fail

    .size   _start, . - _start

# =============================================================================
# Mailbox tohost / fromhost
# -----------------------------------------------------------------------------
# Cac section nay co flag "aw" (allocatable + writable) nen orphan-section
# placement cua GNU ld se TU DONG dat vao region RAM (vi ROM la rx).
# Neu muon CHAC AN, them vao link.ld:
#
#     .tohost (NOLOAD) : { *(.tohost) } > RAM
#     .bss    (NOLOAD) : { *(.bss*)   } > RAM
#
# =============================================================================
    .section .tohost, "aw", @progbits
    .align  6
    .global tohost
tohost:
    .dword  0
    .align  6
    .global fromhost
fromhost:
    .dword  0
