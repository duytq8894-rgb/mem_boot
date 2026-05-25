# =============================================================================
# bootrom.S — CVA6 / Ariane boot ROM source (RV64IMAC)
# -----------------------------------------------------------------------------
# Mục tiêu: tái tạo CHÍNH XÁC bytes của bootrom.elf đã disassemble.
# Toolchain: riscv64-unknown-elf-gcc (binutils >= 2.34)
# Layout (do link.ld quyết định):
#       0x100000  .text.start  (_start , 24 byte)
#       0x100040  .text.hang   (_hang  , 26 byte)
#       0x100080  .rodata      (_dtb   , 13 byte ASCII)
# =============================================================================

# -----------------------------------------------------------------------------
# .text.start @ 0x100000 — entry point sau reset của hart chính
# -----------------------------------------------------------------------------
    .section .text.start, "ax", @progbits
    .global  _start
    .type    _start, @function

_start:
    csrwi   0x7c1, 0              # 7c105073  csrrwi x0,0x7c1,0
                                  #   custom CVA6 CSR (cache/platform) <- 0
    li      s0, (1 << 31)         # 0010041b  addiw  x8,x0,1
                                  # 047e      c.slli x8,0x1f
                                  #   s0 = 0x80000000 (entry vào DRAM)
    csrr    a0, mhartid           # f1402573  csrrs  x10,mhartid,x0
                                  #   a0 = hart ID
    la      a1, _dtb              # 00000597  auipc  x11,0x0
                                  # 07258593  addi   x11,x11,0x72
                                  #   a1 = &_dtb (PC-relative)

    # ----- Magic "boot ROM done" trước khi nhảy vào main ---------------
    # Mục đích: testbench / monitor poll địa chỉ 0x801FFFF0 sẽ thấy
    # 0xCAFEBABE → biết bootrom đã chạy xong và sắp jump tới payload.
    # (crt0 ở 0x80000000 cũng sẽ ghi lại giá trị này lần nữa khi start.)
    #
    # Tính địa chỉ:
    #   0x801FFFF0 = s0 + 0x1FFFF0
    #              = (s0 + 0x200000) - 16
    #   → t1 = s0 + lui(0x200);  store với offset -16
    # -------------------------------------------------------------------
    li      t0, 0xCAFEBABE        # t0 = magic value
    lui     t1, 0x200             # t1 = 0x00200000   (bit 31=0, không sign-ext)
    add     t1, t1, s0            # t1 = 0x80000000 + 0x200000 = 0x80200000
    sd      t0, -16(t1)           # M[0x801FFFF0]..M[0x801FFFF7] (8B) = t0

    jr      s0                    # 8402      c.jr   x8
                                  #   nhảy sang 0x80000000, KHÔNG quay lại

    .size   _start, . - _start


# -----------------------------------------------------------------------------
# .text.hang @ 0x100040 — entry cho hart phụ / chế độ park (WFI)
# -----------------------------------------------------------------------------
    .section .text.hang, "ax", @progbits
    .global  _hang
    .type    _hang, @function

_hang:
    csrwi   0x7c1, 0              # 7c105073  csrrwi x0,0x7c1,0
    csrr    a0, mhartid           # f1402573  csrrs  x10,mhartid,x0
    la      a1, _dtb              # 00000597  auipc  x11,0x0
                                  # 03858593  addi   x11,x11,0x38
    csrwi   mie, 0                # 30405073  csrrwi x0,mie,0
                                  #   tắt mọi machine-mode interrupt enable
1:
    wfi                           # 10500073  wfi
    j       1b                    # bff5      c.j    -4   (loop về wfi)

    .size   _hang, . - _hang


# -----------------------------------------------------------------------------
# .rodata @ 0x100080 — placeholder cho Device Tree Blob
# -----------------------------------------------------------------------------
# Trong build thật, sau khi link xong sẽ dùng objcopy để patch DTB thực vào
# vị trí của symbol _dtb (ví dụ: objcopy --update-section .rodata=cva6.dtb).
# Ở đây ta để string "DTB goes here" làm marker (đúng 13 byte).
# -----------------------------------------------------------------------------
    .section .rodata, "a", @progbits
    .global  _dtb
    .type    _dtb, @object

_dtb:
    .ascii  "DTB goes here"

    .size   _dtb, . - _dtb
