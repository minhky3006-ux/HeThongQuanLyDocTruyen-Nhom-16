# Sprint 6 (tuần 11–12, 23 điểm) — Thống kê, ứng dụng mobile, kiểm thử tích hợp và hoàn thiện

Đã làm đủ 4 story và mục tiêu "kiểm thử tích hợp và hoàn thiện", xây tiếp trên Sprint 3–5 (cần đã chạy `db/migrations/ALL_sprint3-6.sql`). DB, `api.js` và các trang đã chạy thử trên máy (PostgreSQL + PostgREST cục bộ, API giả cho giao diện). **Chưa thử trên Supabase thật, chưa build/chạy ứng dụng trên thiết bị, chưa gọi VNPay thật.**

## Phân công (theo Product Backlog) và phần đã làm
| Người | Story | Đã làm |
|---|---|---|
| Đỗ Minh Kỳ (10đ) | 26 | `admin/revenue.html` tab **Gói đọc**: doanh thu, số đơn, người mua, giá trị trung bình; theo ngày hoặc tháng; **theo từng loại gói** (cột chồng); xuất CSV |
| | 27 | Tab **Theo truyện**: lượt mua và doanh thu theo thời gian; bảng truyện xếp theo doanh thu; bấm "Xem theo thời gian" để lọc một truyện; xuất CSV |
| Lê Quốc Thắng (5đ) | 28 | `admin/content.html`: truyện đọc nhiều, nhiều người theo dõi, chương nhiều lượt đọc, chương nhiều thảo luận, thể loại được quan tâm; chọn khoảng ngày; xuất CSV |
| Phạm Thanh Bình (8đ) | 41 | **Ứng dụng mobile**: PWA cài được (`sw.js`) và vỏ Android/iOS `mobile/` (Capacitor) dùng chung API/tài khoản với web; tài liệu API REST dùng chung `docs/API-REST.md` |
| Cả nhóm | Tích hợp & hoàn thiện | `db/tests/regression.sql` (52 kiểm tra tự động, không để lại dữ liệu), `docs/TEST-PLAN.md` (kiểm thử thủ công đủ 41 story), tab **Nhật ký kiểm duyệt** (khép giới hạn của Sprint 5), sửa lượt xem theo ngày giờ VN, tinh chỉnh giao diện cảm ứng |

Nhánh gợi ý: `feature/26-doanh-thu-goi`, `feature/27-doanh-thu-truyen`, `feature/28-thong-ke-noi-dung`, `feature/41-mobile`, `chore/kiem-thu-tich-hop`.

## Cách chạy
1. Sao lưu DB, chạy `db/migrations/ALL_sprint3-6.sql` (chạy lại an toàn), rồi `db/seed_test_ALL.sql` (60 ngày doanh thu và lượt xem giả; các đơn này được đánh dấu "bỏ qua" nên không hiện là bất thường ở trang Giao dịch).
2. Chạy `db/tests/regression.sql` → phải **0 lỗi**.
3. Mobile: làm theo `mobile/README.md`.

## Quy tắc đã chọn (Kỳ/PO xác nhận)
- **Doanh thu** = tổng đơn `paid`, tính theo **ngày thanh toán**, giờ Việt Nam. **Chưa có hoàn tiền** nên là doanh thu gộp; đơn "mua lẻ trùng" vẫn được tính cho tới khi admin xử lý ngoài hệ thống.
- Doanh thu gói và doanh thu mua lẻ tách riêng (hai tab); chưa có tổng gộp hai loại.
- **Thống kê nội dung** chỉ tính truyện đã đăng; lượt xem lấy từ bảng theo ngày (story 40), số người theo dõi là tổng hiện tại (kèm số theo dõi mới trong kỳ). Thể loại "được quan tâm" = tổng lượt xem các truyện thuộc thể loại trong kỳ.
- **Mobile** chọn hướng "vỏ Capacitor mở bản web đã triển khai" (một mã nguồn, một phiên đăng nhập, thanh toán không bị gián đoạn) thay vì viết lại ứng dụng native. `docs/API-REST.md` đủ để ai muốn làm native riêng vẫn dùng chung API. Nếu giảng viên yêu cầu ứng dụng native (Flutter/React Native), cần tách thành việc mới.

## Giới hạn đã biết
- Số liệu lượt xem **trước migration 005** được ghi theo ngày UTC (lệch tối đa 7 giờ so với ngày VN); từ nay ghi theo ngày VN.
- Thống kê chạy trực tiếp trên bảng giao dịch/lượt xem, đủ cho quy mô đồ án; dữ liệu rất lớn thì cần bảng tổng hợp.
- Chưa có tổng hợp doanh thu theo tác giả (chia sẻ doanh thu) hay hoàn tiền; ngoài phạm vi backlog.
- Ứng dụng mobile cần mạng, chưa có push, chưa có biểu tượng riêng (chi tiết ở `mobile/README.md`).
- Ảnh truyện tranh trả phí trên R2 và VNPay thật: giới hạn như Sprint 3–4.
