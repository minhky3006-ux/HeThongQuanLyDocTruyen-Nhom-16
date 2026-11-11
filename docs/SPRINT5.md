# Sprint 5 (tuần 9–10, 23 điểm) — Thảo luận theo chương, thông báo, kiểm duyệt, đối soát

Đã làm đủ 6 story, xây tiếp trên Sprint 3–4 (cần đã chạy `db/migrations/ALL_sprint3-6.sql`). DB và `api.js` đã chạy thử với PostgreSQL + PostgREST cục bộ (phân quyền theo từng loại người dùng, báo cáo, hạn chế, thông báo, đối soát, thống kê); các trang đã chạy thử với API giả. **Chưa thử trên Supabase thật.** Sprint này không có Edge Function mới.

## Phân công (theo Product Backlog) và phần đã làm
| Người | Story | Đã làm |
|---|---|---|
| Đỗ Minh Kỳ (8đ) | 24 | `admin/orders.html`: danh sách giao dịch, thống kê bất thường, thao tác **cấp lại quyền / hủy đơn / xác nhận thủ công / bỏ qua**; mọi thao tác ghi vào `order_audit` |
| | 23 | `admin/reports.html`: hàng đợi báo cáo gộp theo bình luận → **ẩn bình luận / bỏ qua báo cáo**; **hạn chế bình luận có thời hạn** hoặc **khóa tài khoản** (cũng làm được ở `admin/users.html`); nhật ký `moderation_log` |
| Phạm Thanh Bình (10đ) | 37 | `stories/reader.html`: thảo luận riêng của từng chương; DB chỉ cho **người đọc được chương** xem/viết |
| | 39 | Chuông 🔔 trên menu + `member/notifications.html`; thông báo tự sinh trong DB khi chương được phát hành |
| Lê Quốc Thắng (5đ) | 38 | Nút **Báo cáo** ở mỗi bình luận (trang truyện và trang đọc), chọn lý do spam / xúc phạm / spoiler / khác |
| | 25 | `admin/members.html`: tổng thành viên, tác giả, bị khóa/hạn chế, đang dùng gói; đăng ký mới và gia hạn theo ngày/tháng; theo từng gói |

Nhánh gợi ý: `feature/24-doi-soat`, `feature/23-xu-ly-bao-cao`, `feature/37-thao-luan-chuong`, `feature/39-thong-bao`, `feature/38-bao-cao-binh-luan`, `feature/25-thong-ke-thanh-vien`.

## Cách chạy
1. Sao lưu DB, chạy `db/migrations/ALL_sprint3-6.sql` (an toàn khi chạy lại), rồi `db/seed_test_ALL.sql`.
2. Chương hẹn giờ gửi thông báo qua `release_due_chapters()`: nên bật `pg_cron` như ở Sprint 4. Chưa bật thì chỉ chạy khi có người vào trang chủ.

## Kịch bản thử (mật khẩu `Test@123456`)
- **Báo cáo (38 → 23):** `thanhvien2` bấm Báo cáo ở bình luận quảng cáo (chương 1 truyện 101) → `admin@example.com` vào Quản trị › Báo cáo, thấy bình luận gộp N báo cáo + lý do → **Ẩn bình luận** (người khác không còn thấy) → **Hạn chế 7 ngày** tác giả bình luận → người đó vào trang truyện thấy ô nhập bị khóa kèm lý do, **báo cáo/bình luận đều bị chặn ở DB**. Gỡ hạn chế ở Quản trị › Người dùng.
- **Thảo luận chương (37):** truyện 102 là trả phí: `thanhvien2` (có gói) thấy và viết được thảo luận chương 1; `thanhvien1`, khách thì không thấy gì. Bình luận cấp truyện ở trang truyện không lẫn thảo luận chương.
- **Thông báo (39):** `tacgia1` đăng chương mới cho 101 (hoặc hẹn giờ) → `thanhvien1`, `thanhvien2` (đang theo dõi) thấy số trên chuông; bấm vào mở đúng chương và đánh dấu đã đọc. Tác giả không tự nhận thông báo của mình; chương của truyện chưa duyệt không gửi.
- **Đối soát (24):** Quản trị › Giao dịch (seed có 4 loại bất thường): *Cấp lại quyền* cho đơn đã thu tiền; *Hủy đơn* cho đơn chờ quá lâu; *Xác nhận thủ công* (bắt buộc ghi chú) khi đã đối chiếu cổng; *Bỏ qua* cho trường hợp xử lý ngoài (vd. hoàn tiền mua lẻ trùng).
- **Thống kê (25):** Quản trị › Thống kê thành viên, thử đổi khoảng ngày và nhóm theo tháng.

## Quy tắc đã chọn (Kỳ/PO xác nhận)
- **Thảo luận chương chỉ dành cho người đọc được chương** (tránh lộ nội dung chương trả phí qua bình luận). Bình luận cấp truyện giữ nguyên.
- **Hạn chế ≠ khóa:** hạn chế (1–365 ngày, tự hết hạn) chỉ chặn *bình luận và báo cáo*; vẫn đọc, mua, đăng truyện bình thường. Khóa tài khoản vẫn là mức nặng như Sprint 2. Không hạn chế/khóa được quản trị viên.
- **Thông báo:** chỉ cho người đang theo dõi truyện, mỗi chương một lần; chương có sẵn trước migration không báo lại. Không có thông báo email/đẩy.
- **Bất thường giao dịch:** *đã thu tiền chưa có quyền* · *chờ quá 30 phút* · *cổng báo sai số tiền* · *mua lẻ trùng*. "Xác nhận thủ công" chỉ nên dùng sau khi đối chiếu với cổng; DB bắt buộc ghi chú.
- **Thống kê:** "đăng ký mới" = lần mua gói đầu tiên của một người với một loại gói; "gia hạn" = các lần sau của cùng gói. Ngày tính theo giờ Việt Nam.

## Giới hạn đã biết
- `moderation_log` (kiểm duyệt) chỉ xem được bằng SQL; `order_audit` hiện qua dòng "Đã xử lý" ở trang Giao dịch. Chưa có trang xem nhật ký đầy đủ.
- Số trên chuông chỉ cập nhật khi tải trang. Chưa tự xóa thông báo cũ.
- Chưa có hoàn tiền: đơn mua lẻ trùng chỉ được đánh dấu để xử lý ngoài hệ thống. Chưa gọi API truy vấn giao dịch của VNPay (đối soát vẫn dựa trên dữ liệu hệ thống và quyết định của quản trị viên).
- Một người báo cáo tối đa 30 lần/giờ; mỗi bình luận 1 lần/người.
- Ảnh truyện tranh trả phí và VNPay thật: giới hạn như Sprint 3–4.
