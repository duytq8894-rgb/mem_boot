# ============================================================================
#  rvv_csr_demo.S
#  RISC-V ISA: rv64imafdcv  (RV64GCV)
#
#  Chuong trinh assembly chi gom:
#    1) Cac lenh setup CSR can thiet de bat va cau hinh khoi Vector (V)
#    2) Cac lenh vector (RVV 1.0): config, load/store, so hoc int/float,
#       reduction, mask, permutation, va doc cac CSR cua vector.
#
#  Build (RVV 1.0):
#    riscv64-unknown-elf-gcc -march=rv64imafdcv -mabi=lp64d \
#         -nostdlib -static rvv_csr_demo.S -o rvv_csr_demo
#  Chay:
#    qemu-riscv64 -cpu rv64,v=true,vlen=128 ./rvv_csr_demo
# ============================================================================

# ---- mstatus bit fields ----------------------------------------------------
#   FS  = bits [14:13]   (Float  unit state)
#   VS  = bits [10:9]    (Vector unit state)
#   state: 0=Off, 1=Initial, 2=Clean, 3=Dirty
.equ MSTATUS_FS_INITIAL, (1 << 13)
.equ MSTATUS_VS_INITIAL, (1 << 9)

# ---- CSR addresses (vector) ------------------------------------------------
.equ CSR_VSTART, 0x008
.equ CSR_VXSAT,  0x009
.equ CSR_VXRM,   0x00A
.equ CSR_VCSR,   0x00F
.equ CSR_VL,     0xC20
.equ CSR_VTYPE,  0xC21
.equ CSR_VLENB,  0xC22

    .section .text
    .globl _start

# ============================================================================
# 1. SETUP CSR  -- bat khoi vector (va float, vi co D/F trong ISA)
# ============================================================================
_start:
    # --- Bat Vector unit + Float unit trong mstatus ---
    li      t0, (MSTATUS_FS_INITIAL | MSTATUS_VS_INITIAL)
    csrs    mstatus, t0            # set FS=Initial, VS=Initial -> V/F enabled

    # --- Khoi tao cac CSR vector ve trang thai sach ---
    csrw    vstart, x0             # vstart = 0 (bat dau tu element 0)
    csrwi   vxsat,  0              # xoa co bao hoa (fixed-point saturate)
    csrwi   vxrm,   0             # vxrm = 0 (round-to-nearest-up, rnu)

    # --- Cap phat con tro vung du lieu ---
    la      a0, vec_a              # nguon A
    la      a1, vec_b             # nguon B
    la      a2, vec_out           # ket qua
    li      a3, 16                # so phan tu can xu ly (AVL)

# ============================================================================
# 2. CAU HINH VECTOR  -- vsetvli (SEW=32, LMUL=1, ta/ma)
# ============================================================================
    vsetvli t1, a3, e32, m1, ta, ma   # t1 = vl thuc te; vtype: e32,m1
    csrr    t2, vl                     # doc lai VL  (CSR 0xC20)
    csrr    t3, vtype                  # doc lai VTYPE (CSR 0xC21)
    csrr    t4, vlenb                  # doc VLENB = VLEN/8 (CSR 0xC22)

# ============================================================================
# 3. VECTOR LOAD / STORE
# ============================================================================
    vle32.v   v0, (a0)            # unit-stride load  A -> v0
    vle32.v   v1, (a1)            # unit-stride load  B -> v1

    li      t5, 8
    vlse32.v  v2, (a0), t5        # strided load (stride = 8 byte)

# ============================================================================
# 4. VECTOR INTEGER ARITHMETIC
# ============================================================================
    vadd.vv   v3, v0, v1          # v3 = A + B
    vsub.vv   v4, v1, v0          # v4 = B - A
    vmul.vv   v5, v0, v1          # v5 = A * B
    vadd.vi   v6, v0, 5          # v6 = A + 5  (immediate)
    vadd.vx   v7, v0, a3          # v7 = A + a3 (scalar)
    vmacc.vv  v3, v0, v1          # v3 += A * B  (multiply-accumulate)
    vand.vv   v8, v0, v1          # bitwise AND
    vor.vv    v9, v0, v1          # bitwise OR
    vxor.vv   v10, v0, v1         # bitwise XOR
    vsll.vi   v11, v0, 2          # shift-left logical theo immediate
    vsrl.vx   v12, v0, t5         # shift-right logical theo scalar
    vmin.vv   v13, v0, v1         # element-wise min (signed)
    vmax.vv   v14, v0, v1         # element-wise max (signed)

# ============================================================================
# 5. VECTOR FLOATING-POINT (su dung D/F trong ISA)
# ============================================================================
    vfcvt.f.x.v v15, v0           # convert int -> float
    vfcvt.f.x.v v16, v1
    vfadd.vv    v17, v15, v16     # float add
    vfmul.vv    v18, v15, v16     # float multiply
    vfmacc.vv   v17, v15, v16     # float multiply-accumulate

# ============================================================================
# 6. VECTOR REDUCTION
# ============================================================================
    vmv.v.i     v20, 0           # khoi tao accumulator = 0
    vredsum.vs  v21, v0, v20      # sum-reduction cua A
    vredmax.vs  v22, v0, v20      # max-reduction cua A
    vfredusum.vs v23, v15, v20    # float sum-reduction

# ============================================================================
# 7. VECTOR MASK
# ============================================================================
    vmseq.vv  v0, v3, v4          # mask: v3 == v4  -> v0 (mask register)
    vmslt.vv  v24, v0, v1         # mask: set-less-than
    vadd.vv   v25, v0, v1, v0.t   # masked add (chi cac element co mask=1)

# ============================================================================
# 8. VECTOR PERMUTATION / MOVE
# ============================================================================
    vslideup.vi   v26, v0, 1      # dich element len 1 vi tri
    vslidedown.vi v27, v0, 1      # dich element xuong 1 vi tri
    vrgather.vv   v28, v0, v1     # gather theo chi so trong v1
    vmv.v.v       v29, v0         # vector copy
    vmv.x.s       a4, v21         # lay element[0] cua v21 ra scalar a4

# ============================================================================
# 9. VECTOR STORE ket qua
# ============================================================================
    vse32.v   v3, (a2)           # store v3 -> vec_out (unit-stride)
    vsse32.v  v5, (a2), t5        # strided store v5

# ============================================================================
# 10. Doc lai cac CSR vector sau khi xu ly
# ============================================================================
    csrr    a5, vstart            # vstart
    csrr    a6, vxsat             # co bao hoa
    csrr    a7, vxrm              # rounding mode
    csrr    s2, vcsr              # vcsr = {vxrm, vxsat}

# ============================================================================
# Ket thuc -- exit syscall (Linux/QEMU user-mode)
# ============================================================================
exit:
    li      a7, 93                # __NR_exit
    li      a0, 0
    ecall

# ============================================================================
#  DATA
# ============================================================================
    .section .data
    .align 6
vec_a:
    .word 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15,16
vec_b:
    .word 16,15,14,13,12,11,10, 9, 8, 7, 6, 5, 4, 3, 2, 1

    .align 6
vec_out:
    .zero 64                      # 16 phan tu * 4 byte
