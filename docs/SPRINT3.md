# Sprint 3 (tuần 5–6, 25 điểm) — Bộ khung

**Mục tiêu:** nền tảng chính sách truy cập, gói đọc và kiểm tra quyền đọc.
Khung đã nối sẵn DB → `API.xxx()` → trang. Phần DB và `api.js` đã được chạy thử với PostgreSQL + PostgREST cục bộ (phân quyền theo từng loại người dùng, đơn hàng, upsert nội dung chương); các trang đã chạy thử với API giả. **Chưa thử trên Supabase/R2 thật và chưa thử với cổng VNPay thật.**

## Phân công (theo Product Backlog)
| Người | Story | File chính | Việc còn lại (tìm `TODO(tên)` trong code) |
|---|---|---|---|
| Đỗ Minh Kỳ (10đ) | 19, 21 | `pages/admin/access.html`, `pages/admin/plans.html`, `db/migrations/ALL_sprint3-6.sql` | Nút "chọn N chương đầu"; rà lại giao diện, thông báo lỗi; **chạy file migration gộp đầu tiên** để Bình/Thắng không bị chặn |
| Phạm Thanh Bình (10đ) | 31, 32 | `pages/stories/reader.html`, `getChapter` trong `api.js`, `supabase/functions/create-payment`, `payment-webhook`, `_shared/payment.ts`, `pages/member/checkout.html` | Thử VNPay sandbox thật; nội dung khung paywall (tên gói, gói hết hạn) |
| Lê Quốc Thắng (5đ) | 29, 30 | `index.html`, `pages/stories/list.html`, `pages/stories/detail.html`, `ui.js` (`accessBadge`) | Đổi sắp xếp sang 3 tab; nút đảo thứ tự chương |

Nhánh: `feature/19-chinh-sach-truy-cap`, `feature/21-goi-doc`, `feature/31-quyen-doc`, `feature/32-thanh-toan`, `feature/29-danh-sach-truyen`, `feature/30-trang-thai-chuong`.
Thứ tự: Kỳ chạy file migration gộp + seed → Bình/Thắng làm song song (cột `access_policy`, `is_free_preview` đã có từ migration nên **US 30, 31 không phải chờ UI của US 19**).

## Thay đổi cơ sở dữ liệu (`db/migrations/ALL_sprint3-6.sql`)
- `stories.access_policy` (`free` mặc định / `paid` / `mixed`), `chapters.is_free_preview`, `stories.published_at` (mốc "mới phát hành").
- Bảng mới: `plans`, `plan_stories`, `orders`, `subscriptions`, `story_purchases` (hai bảng cuối do Sprint 4 điền dữ liệu).
- **Nội dung chương chuyển sang bảng `chapter_contents`** và cột `chapters.content` bị xóa, để RLS chặn được. `api.getChapter/addChapter/updateChapter` đã sửa theo; trang tác giả không phải đổi. Ai viết SQL tay phải ghi vào `chapter_contents`.
- Quyền đọc do DB quyết định: `can_read_chapter(chapter_id)` và `has_story_access(story_id)`. Giao diện chỉ hiển thị theo kết quả.
- Quy tắc: `free` = mọi chương miễn phí · `paid` = mọi chương trả phí · `mixed` = chương có `is_free_preview` miễn phí, còn lại trả phí. Người được đọc: admin, tác giả của truyện, người có gói còn hạn bao phủ truyện (`scope='all'` hoặc nằm trong `plan_stories`), người đã mua lẻ.
- Client không ghi được `orders`/`subscriptions`/`story_purchases`; chỉ Edge Function (service role) gọi `fulfill_order`, `fail_order` (idempotent, kiểm tra số tiền).
- `grant_entitlement()` ở Sprint 3 để trống; **đã hoàn thiện ở Sprint 4** (xem `docs/SPRINT4.md`). Đơn `paid` chưa cấp quyền; thử US 31 bằng `db/dev.sql` lệnh 4 hoặc `db/seed_test_ALL.sql`.

## API mới trong `api.js`
`canReadChapter`, `hasStoryAccess`, `adminAccessStories`, `adminSetStoryAccess`, `listPlans`, `adminListPlans`, `savePlan`, `setPlanStories`, `setPlanActive`, `deletePlan`, `createPayment`, `getOrder`, `mockPay` (chỉ để thử). `getChapter` trả thêm `canRead`; `listChapters` trả thêm `is_free_preview`; `listStories` nhận `sort: "released"`.

## Luồng thanh toán (story 32)
`checkout.html?plan=ID` → `create-payment` (giá lấy từ bảng `plans`, tạo đơn `pending`) → cổng → `payment-webhook` kiểm tra chữ ký, gọi `fulfill_order` → `checkout.html?order=ID` hỏi DB trạng thái đơn. Trang kết quả **không tin tham số `vnp_*` trên URL**.
Mặc định `PAYMENT_PROVIDER=mock`: `pages/member/mock-gateway.html` giả lập cổng, thử được ngay không cần tài khoản. Cấu hình xem `db/README.md`.

## Cách chạy thử
1. Sao lưu DB (gói Free không có backup), chạy `db/migrations/ALL_sprint3-6.sql`, rồi `db/seed_test_ALL.sql`.
2. Deploy 2 hàm (lệnh trong `db/README.md`), đặt `SITE_URL` đúng địa chỉ Live Server.
3. Kịch bản (mật khẩu `Test@123456`):
   - Khách: truyện 102 (trả phí) hiện khung paywall; 103 đọc được chương 1–2, khóa từ chương 3; 101 đọc tự do.
   - `thanhvien2@example.com` (gói còn hạn): đọc được 102, 103, 104. `thanhvien3@example.com` (gói hết hạn) và `thanhvien1@example.com`: bị khóa.
   - `admin@example.com`: Quản trị › Chính sách truy cập / Gói đọc. Đổi chính sách rồi kiểm tra lại bằng khách.
   - Thanh toán giả lập bằng `thanhvien1`: chọn gói → Thanh toán → "thành công" → đơn `paid` (chạy `db/dev.sql` lệnh 5 để xem).

## Tiêu chí hoàn thành (gợi ý cho cuối sprint)
- [ ] 19: đổi chính sách và chương đọc thử có hiệu lực ngay với khách. [ ] 21: thêm/sửa/ngừng bán gói; gói đã bán không xóa được.
- [ ] 31: khách/thành viên không có quyền không lấy được nội dung (kiểm tra cả tab Network, không chỉ giao diện). [ ] 32: đơn thành công/thất bại/gọi lặp đều ghi đúng; sai số tiền không thành `paid`.
- [ ] 29: ba danh sách hoạt động. [ ] 30: nhãn chương đúng với cả ba chính sách.
- [ ] Cập nhật cột Act Start/End/Points trong Sprint Backlog.

## Cần PO (Kỳ) xác nhận / giới hạn đã biết
- **Nghĩa của "kết hợp"** đang được hiểu như trên (có chương đọc thử). Nếu nhóm hiểu khác (vd: N chương đầu miễn phí) thì sửa `can_read_chapter` trước khi làm tiếp.
- **Ảnh truyện tranh trả phí chưa được bảo vệ thật:** DB giấu danh sách ảnh, nhưng file nằm trên domain R2 công khai, ai đoán đúng đường dẫn (`s102/c1/001.webp`) vẫn tải được. Muốn khóa hẳn cần bucket riêng + link đọc có chữ ký. Văn bản chữ thì đã được RLS chặn thật.
- Đơn kiểu mua lẻ (`kind='story'`) chưa dùng được: cần giá truyện (story 22, Sprint 4); `create-payment` trả 501.
- Nhà cung cấp VNPay: phần ký/kiểm tra chữ ký đã tự kiểm tra vòng ký–xác minh, chưa gọi sandbox thật. Tên biến môi trường tự có của Edge Function (`SUPABASE_SERVICE_ROLE_KEY`...) hãy đối chiếu tài liệu Supabase hiện hành khi deploy.
- Khi lên production phải đặt `PAYMENT_PROVIDER=vnpay` để tắt cổng giả lập.
