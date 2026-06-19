# Comprehensive RVV-1.0 vector test for the synth tracer vs Spike golden.
# Uses `vsetvl rd,rs1,rs2` with explicit vtype (avoids GCC 9.2 draft vtype-imm
# bug). vtype byte = vma<<7|vta<<6|vsew<<3|vlmul. e8=0xC0 e16=0xC8 e32=0xD0 e64=0xD8
.section .text.init,"ax",@progbits
.global _start
_start:
    li      t0, 0x6600
    csrs    mstatus, t0                 # enable vector (VS) + float (FS)
    la      a1, vdata                   # load/store base

    # ---- e32, m1, vl=4 : arithmetic / moves -------------------------------
    li      a0, 4
    li      a3, 0xD0
    vsetvl  t1, a0, a3                  # e32 m1 ta ma, vl=4
    vid.v   v8                          # §3.9  [3,2,1,0]
    vadd.vv v2, v8, v8                  # §3.2  [6,4,2,0]
    li      a2, 7
    vadd.vx v3, v8, a2                  # §3.3  [10,9,8,7]
    vmv.v.x v1, a2                      # vmv   [7,7,7,7]
    vsub.vv v4, v3, v8                  # [7,7,7,7]
    vand.vv v5, v3, v8                  # logical
    vor.vv  v6, v8, v1                  # logical
    vxor.vv v7, v3, v3                  # [0,0,0,0]
    vsll.vi v9, v8, 2                   # shift  [12,8,4,0]
    vmul.vv v10, v8, v8                 # [9,4,1,0]
    vmv.s.x v11, a2                     # §3.11 scalar->vec elem0
    vredsum.vs v12, v8, v8              # §3.12 reduction (sum=6 + v8[0]=0)

    # ---- masks (§3.13) ----------------------------------------------------
    vmseq.vv v0, v8, v8                 # all equal -> mask 0xF
    vmslt.vv v13, v8, v3                # v8<v3 ? -> mask
    vmsne.vv v14, v8, v2                # v8!=v2

    # ---- load / store (§3.4 / §3.5) ---------------------------------------
    vle32.v v15, (a1)                   # §3.4 load (no mem token)
    vse32.v v2,  (a1)                   # §3.5 store (mem tokens)

    # ---- different SEW (de-shuffle width) ---------------------------------
    li      a0, 8
    li      a3, 0xC8
    vsetvl  t1, a0, a3                  # e16 m1, vl=8
    vid.v   v16                         # [7..0] at e16
    li      a0, 2
    li      a3, 0xD8
    vsetvl  t1, a0, a3                  # e64 m1, vl=2
    vid.v   v17                         # [1,0] at e64
    li      a0, 16
    li      a3, 0xC0
    vsetvl  t1, a0, a3                  # e8 m1, vl=16
    vid.v   v18                         # [15..0] at e8

    # ---- float (§3.14) ----------------------------------------------------
    li      a0, 4
    li      a3, 0xD0
    vsetvl  t1, a0, a3                  # back to e32
    vfadd.vv v19, v8, v8                # float add -> fflags

    # exit
    la      t0, tohost
    li      t1, 1
    sd      t1, 0(t0)
1:  j       1b

.section .data
.align 6
vdata:  .word 0x11111111, 0x22222222, 0x33333333, 0x44444444
        .word 0x55555555, 0x66666666, 0x77777777, 0x88888888
store_area: .zero 256

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.global fromhost
fromhost: .dword 0
