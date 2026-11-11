# Sprint 4 (tuần 7–8, 25 điểm) — Hoàn thiện thanh toán và quyền đọc

**Mục tiêu:** hoàn thiện luồng thanh toán (gói tháng, mua lẻ) và quyền đọc. Xây tiếp trên Sprint 3, cần đã chạy `db/migrations/ALL_sprint3-6.sql`.
Đã làm đủ 7 story. DB và `api.js` đã chạy thử với PostgreSQL + PostgREST cục bộ (phân quyền, cấp quyền, gia hạn, hẹn giờ, lượt đọc); các trang đã chạy thử với API giả. **Chưa thử trên Supabase/R2 thật, chưa thử Edge Function trên Supabase, chưa thử VNPay thật.**

## Phân công (theo Product Backlog) và phần đã làm
| Người | Story | Đã làm |
|---|---|---|
| Đỗ Minh Kỳ (6đ) | 22 | `admin/access.html` thêm ô **giá bán lẻ**; hàm DB `admin_set_story_price` ghi nhật ký đổi giá (`story_price_log`); đơn hàng chốt giá lúc tạo đơn |
| | 20 | Tác giả **hẹn giờ phát hành chương** (`author/chapters.html`) và đổi **tiến độ truyện** Đang ra / Hoàn thành / Tạm ngưng (`author/edit.html`); độc giả chỉ thấy chương đã tới giờ |
| Phạm Thanh Bình (10đ) | 33 | `grant_entitlement` cấp gói sau thanh toán; mua thêm cùng gói = **gia hạn nối tiếp**; `checkout.html` hiện gói đang dùng + nút Gia hạn |
| | 34 | Mua lẻ: `create-payment` nhận `kind:"story"`; `checkout.html?story=ID`; nút "Mua truyện" ở trang truyện và khung chặn của trang đọc |
| Lê Quốc Thắng (9đ) | 35 | `has_story_access_for`, `story_access_info`: quyền gộp gói + mua lẻ; trang truyện nói rõ "đọc được nhờ gói X đến ngày Y / đã mua"; **máy chủ từ chối bán lại (409)** nếu đã có quyền |
| | 36 | `member/billing.html`: gói đang dùng (ngày bắt đầu/hết hạn), truyện đã mua, lịch sử thanh toán; liên kết từ Tủ truyện |
| | 40 | `track_view` chỉ tính khi **đọc được thật** và chương đúng truyện; thêm `chapter_views_daily`; trang đọc chỉ tính sau 8 giây còn mở |

Nhánh gợi ý: `feature/22-gia-truyen`, `feature/20-hen-gio-chuong`, `feature/33-dang-ky-goi`, `feature/34-mua-le`, `feature/35-quyen-gop`, `feature/36-lich-su-mua`, `feature/40-luot-doc`.

## Cách chạy
1. Sao lưu DB, chạy `db/migrations/ALL_sprint3-6.sql` (an toàn khi chạy lại; tự **cấp bù** quyền cho các đơn `paid` từ Sprint 3), rồi `db/seed_test_ALL.sql`.
2. Deploy lại hàm: `npx supabase functions deploy create-payment` (có thêm nhánh mua lẻ). `payment-webhook` không đổi.
3. Khuyên dùng `pg_cron` cho chương hẹn giờ: `select cron.schedule('release-chapters','*/5 * * * *','select release_due_chapters()');`. Nếu chưa bật thì trang chủ tự gọi dự phòng (tối đa 1 lần/5 phút/trình duyệt).

## Kịch bản thử (mật khẩu `Test@123456`)
- **Mua lẻ (34):** `thanhvien1` mở truyện 102 → "Mua truyện 39.000 ₫" → cổng giả lập → thành công → đọc được 102; mở lại trang truyện thấy "Bạn đã mua truyện này", không còn nút mua; vào thẳng `checkout.html?story=102` bị báo không cần thanh toán lại.
- **Gói (33):** mua "Gói tuần thử nghiệm", mua lần nữa → trong Gói & giao dịch thấy hai dòng, dòng sau **bắt đầu đúng lúc dòng trước hết hạn**.
- **Gộp (35):** `thanhvien2` (đã có gói) mở 102: thấy "đọc được nhờ gói…", không có nút mua. Cho `thanhvien1` mua lẻ 102 rồi mua gói: trang truyện nói cả hai nguồn.
- **Hẹn giờ (20):** đăng nhập `tacgia1`, chương "Chương hẹn giờ (seed S4)" của truyện 101 hiện nhãn ⏰; khách không thấy chương này; sửa giờ về quá khứ/để trống thì khách thấy ngay.
- **Giá (22):** admin đổi giá 102 ở Quản trị › Chính sách truy cập; đơn tạo trước đó vẫn giữ giá cũ.
- **Lượt đọc (40):** mở chương 8 giây rồi xem `view_count`; người bị khóa không làm tăng lượt.
- Kiểm tra DB: `db/dev.sql` lệnh 5 xem đơn; bảng `subscriptions`, `story_purchases`, `story_price_log`, `chapter_views_daily`.

## Quy tắc nghiệp vụ đã chọn (Kỳ/PO xác nhận)
- **"Trạng thái truyện" (US 20)** hiểu là *tiến độ ra chương* (đang ra/hoàn thành/tạm ngưng), tách khỏi `stories.status` (nháp/chờ duyệt/đã đăng/gỡ) đã có.
- **Gia hạn:** chỉ nối tiếp khi mua lại **cùng một gói**; mua gói khác thì chạy song song. Gói đã ngừng bán không mua được nhưng người đã mua dùng đến hết hạn.
- **Không thanh toán lại (US 35):** chỉ chặn *mua lẻ* khi đã có quyền. Mua gói luôn được phép (để gia hạn). Quyền mua lẻ không hết hạn, gói hết hạn thì mất phần quyền do gói.
- Giá: `orders.amount` chốt lúc tạo đơn từ `stories.price`/`plans.price`; cổng báo sai số tiền thì đơn thành `failed`.
- Lỗi cấp quyền nằm cùng giao dịch với `fulfill_order`: lỗi thì đơn **vẫn `pending`** để cổng gọi lại (đối soát chi tiết ở Sprint 5, story 24).

## Giới hạn đã biết
- Số chương và mục "mới cập nhật" của chương hẹn giờ chỉ cập nhật khi `release_due_chapters()` chạy (pg_cron hoặc có người vào trang chủ), nên có thể trễ vài phút. Chính việc **ẩn/hiện chương và quyền đọc theo giờ thì chính xác ngay**, vì tính theo `now()` lúc truy vấn.
- Chưa có hoàn tiền/hủy gói. Chưa chống hai đơn mua lẻ cùng truyện được thanh toán gần như đồng thời (đơn thứ hai vẫn `paid` nhưng chỉ có một dòng sở hữu); Sprint 5 (US 24) nên đối soát trường hợp này.
- Ảnh truyện tranh trả phí trên R2 vẫn tải được nếu đoán đúng đường dẫn (xem `docs/SPRINT3.md`). VNPay sandbox vẫn chưa được gọi thật.
- Thông báo chương mới (US 39, Sprint 5) nên gắn vào `release_due_chapters()` và trigger `chapters_count`.
