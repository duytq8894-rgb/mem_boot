.section .text
    .globl _start

_start:
    /* =========================================================
     * BƯỚC 1: KHỞI TẠO ĐỊA CHỈ & MỞ KHÓA QUYỀN CSR
     * ========================================================= */
    
    # Mở khóa các lệnh Cache cho các mode thấp hơn (nếu code này chạy ở M-mode)
    # Bật CBIE, CBCFE, CBZE trong thanh ghi menvcfg để không bị lỗi Illegal Instruction
    li t0, 0x000000F0        # Gán các bit cho phép CBO
    csrs menvcfg, t0         # Set vào CSR Machine Environment Configuration

    # Nạp địa chỉ cơ sở vùng test vào thanh ghi a0
    li a0, 0x80000000

    /* =========================================================
     * BƯỚC 2: TEST LỆNH cbo.zero (Zicboz)
     * ========================================================= */
     
    # Điền toàn bộ số 0 vào 64 byte đầu tiên của dòng cache tại 0x80000000
    # Không cần phải đọc rác từ RAM lên, phần cứng tự động set 0 ngay trong cache.
    cbo.zero 0(a0)
    fence rw, rw             # Rào chắn: đợi lệnh zero hoàn tất

    /* =========================================================
     * BƯỚC 3: GHI DỮ LIỆU ĐỂ TEST CLEAN VÀ FLUSH
     * ========================================================= */
     
    # Nạp một giá trị ngẫu nhiên 64-bit (8 byte)
    li t1, 0x1122334455667788
    
    # Ghi dữ liệu vào đầu dòng cache 0 (tại 0x80000000)
    sd t1, 0(a0)
    
    # Ghi dữ liệu vào đầu dòng cache 1 (tại 0x80000040 tức là offset 64)
    sd t1, 64(a0)
    
    # Ghi dữ liệu vào đầu dòng cache 2 (tại 0x80000080 tức là offset 128)
    sd t1, 128(a0)

    /* =========================================================
     * BƯỚC 4: TEST CÁC LỆNH Zicbom (CLEAN, FLUSH, INVAL)
     * ========================================================= */
     
    # 1. CLEAN: Đẩy dữ liệu của dòng cache 0 (đã ghi ở trên) xuống RAM
    # Nhưng VẪN GIỮ LẠI trong Cache để CPU dùng tiếp.
    cbo.clean 0(a0)
    fence rw, rw

    # 2. FLUSH: Đẩy dữ liệu của dòng cache 1 xuống RAM
    # Sau đó XÓA SỔ (invalidate) dòng đó khỏi Cache.
    cbo.flush 64(a0)
    fence rw, rw

    # 3. INVAL: Xóa sổ trực tiếp dòng cache 2 khỏi bộ đệm
    # KHÔNG đẩy dữ liệu đang có xuống RAM. (Mất luôn dữ liệu vừa ghi bằng sd ở trên).
    # Thường dùng khi DMA ngoại vi vừa ghi dữ liệu mới tinh xuống thẳng RAM vật lý.
    cbo.inval 128(a0)
    fence rw, rw

    /* =========================================================
     * BƯỚC 5: KẾT THÚC TEST
     * ========================================================= */
park_hart:
    wfi                      # Đưa CPU vào trạng thái ngủ chờ ngắt
    j park_hart
