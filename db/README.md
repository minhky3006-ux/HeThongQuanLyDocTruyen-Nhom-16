# Cơ sở dữ liệu TruyệnXanh (dùng chung cho web và app)

## Kiến trúc: tách dữ liệu và ảnh
```
Web / App ──► Supabase (PostgreSQL + Auth + API tự sinh) ── chỉ lưu chữ + "key" ảnh
   │
   └───────► Cloudflare R2 + CDN (domain img.xxx) ── lưu file ảnh thật, tải ảnh miễn phí băng thông
```
- **Supabase** (gói Free): 500 MB database, 50.000 người dùng/tháng, 1 GB file, 5 GB băng thông. Web (JS), Android (Kotlin), iOS (Swift), Flutter, React Native đều có thư viện chính thức, nên web và app gọi cùng một backend.
- **Cloudflare R2** (gói miễn phí): 10 GB lưu trữ, 1 triệu thao tác ghi, 10 triệu thao tác đọc mỗi tháng, **không tính phí băng thông tải ảnh**. Đây là lý do chọn R2 cho ảnh, vì Supabase Free chỉ có 1 GB file và 5 GB băng thông.
- Không dùng Firebase Storage: từ 03/02/2026 nó bắt buộc gói Blaze (phải liên kết thanh toán).
- Số liệu gói miễn phí lấy tháng 9–10/2026, nhà cung cấp có thể đổi, hãy kiểm tra lại trên trang giá trước khi dựa vào.

## Cài đặt (làm một lần, một người làm rồi chia sẻ khóa cho nhóm)
1. **Supabase**: tạo project tại supabase.com. Vào *SQL Editor* chạy `db/schema.sql`, rồi `db/seed.sql` (chỉ chạy seed sau khi đã đăng ký ít nhất 1 tài khoản).
2. **Đăng ký email**: vào *Authentication > Providers > Email*, tắt **Confirm email** khi phát triển để đăng ký xong dùng được ngay.
3. **Cloudflare R2**: tạo bucket `truyenxanh`, gắn domain riêng (vd `img.tenmien.com`) để ảnh qua CDN (link `r2.dev` chỉ để thử). Trong *Settings > CORS policy* dán nội dung `supabase/r2-cors.json` (sửa domain thật). Tạo *API Token* quyền Object Read & Write, ghi lại Account ID, Access Key ID, Secret Access Key. Chưa xác nhận được R2 có đòi thẻ thanh toán khi đăng ký hay không, bạn kiểm tra lúc tạo.
4. **Deploy hàm cấp link upload** (cần Node.js):
   ```bash
   npx supabase login
   npx supabase link --project-ref <mã-project>        # mã nằm trong URL dashboard
   npx supabase secrets set R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_BUCKET=truyenxanh
   npx supabase functions deploy r2-upload-url
   ```
5. **Cấu hình web**: copy `assets/js/config.example.js` thành `assets/js/config.js`, điền `SUPABASE_URL`, `SUPABASE_ANON_KEY` (Project Settings > API) và `IMG_BASE` (domain R2, có dấu `/` ở cuối). File này không commit, mỗi thành viên tự tạo trên máy mình.
   - **Đã có DB chạy bản `schema.sql` cũ?** Chạy thêm `db/migrations/001_sprint1_hardening.sql` (chạy lại nhiều lần vẫn an toàn). DB mới tạo từ `schema.sql` hiện tại không cần.
5b. **Phần mở rộng (trả phí, gói đọc, thanh toán, kiểm duyệt, thống kê)**: sau `schema.sql` chạy **một file** `db/migrations/ALL_sprint3-6.sql`. **Sao lưu trước**: file chuyển nội dung chương sang bảng `chapter_contents` và xóa cột `chapters.content`. Chạy lại nhiều lần vẫn an toàn. Dữ liệu thử: `db/seed_test_ALL.sql` (chỉ dùng môi trường thử).
5c. **Thanh toán**: deploy hai hàm và đặt secret:
   ```bash
   npx supabase secrets set PAYMENT_PROVIDER=mock SITE_URL=http://127.0.0.1:5500
   npx supabase functions deploy create-payment
   npx supabase functions deploy payment-webhook --no-verify-jwt
   ```
   `mock` = cổng giả lập (`pages/member/mock-gateway.html`), thử được không cần tài khoản. Dùng VNPay sandbox: `PAYMENT_PROVIDER=vnpay` cùng `VNPAY_TMN_CODE`, `VNPAY_HASH_SECRET` (lấy từ sandbox.vnpayment.vn), rồi khai báo URL IPN `https://<mã-project>.supabase.co/functions/v1/payment-webhook` trong trang quản trị VNPay. Chạy thật phải dùng `vnpay` để tắt cổng giả lập.
5d. **Chương hẹn giờ**: nên bật extension `pg_cron` (Dashboard > Database > Extensions) rồi chạy `select cron.schedule('release-chapters','*/5 * * * *','select release_due_chapters()');` để chương hẹn giờ và thông báo chương mới cập nhật đúng hạn.
5e. **Kiểm thử hồi quy**: dán `db/tests/regression.sql` vào SQL Editor, phải 0 lỗi, không để lại dữ liệu.
6. **Chạy thử**: mở bằng Live Server, đăng ký tài khoản có tick "tác giả", đăng truyện, rồi chạy `db/dev.sql` (lệnh 1 và 2) để làm admin và duyệt truyện.

## Dùng dữ liệu trong code
Mọi truy vấn nằm trong `assets/js/api.js`, các trang chỉ gọi `API.tênHàm()`, ví dụ `API.listStories({ q: "kiếm", sort: "hot" })`, `API.getChapter(storyId, 3)`, `API.toggleFollow(storyId)`. Đã có sẵn cả hàm cho Sprint 2 (bình luận, đánh giá, lịch sử, thống kê, quản trị). Chữ do người dùng nhập luôn phải qua `esc()` trước khi chèn vào HTML.

## Quy ước ảnh (để tải nhanh, tiết kiệm dung lượng)
| Loại | Đường dẫn trong R2 | Quy cách |
|---|---|---|
| Ảnh bìa | `covers/<story_id>.webp` | rộng 600 px, WebP |
| Thumbnail | `covers/<story_id>_s.webp` | rộng 300 px (dùng cho lưới danh sách) |
| Trang truyện tranh | `s<story_id>/c<số chương>/<001>.webp` | rộng tối đa 1080 px, WebP chất lượng ~80 |
| Avatar | `avatars/<user_id>.webp` | 128 px |

- Nén và đổi sang WebP ngay trên trình duyệt (canvas có sẵn, hàm `API.compressImage`) trước khi upload, không upload ảnh gốc. Hàm cấp link từ chối ảnh khai báo trên 3 MB.
- DB lưu `width`, `height` của từng trang nên có thể giữ chỗ trước, trang không bị giật khi ảnh tải về.
- Thẻ ảnh dùng `loading="lazy"`. (Chưa làm: tải trước 2 trang kế tiếp.)
- Ước tính (giả định mỗi trang ~150 KB): 10 GB chứa được khoảng 65.000 trang, tức hơn 2.000 chương 30 trang.

## Tốc độ truy vấn
- Danh sách và tìm kiếm có index sẵn (`status + updated_at`, `status + view_count`, tìm tên bằng `pg_trgm`).
- `view_count`, `follow_count`, `chapter_count`, `rating_avg` được cập nhật bằng trigger, nên danh sách không phải `count(*)`.
- Luôn phân trang (`.range(0, 19)`), không tải toàn bộ bảng.
- Danh sách truyện: chỉ `select` các cột cần (id, title, cover_key, rating_avg), không lấy `description` hay `content`.

## Phân quyền (Row Level Security)
Quy tắc nằm ngay trong DB nên web và app dùng chung, ai cũng không qua mặt được:
- Khách chỉ thấy truyện `published` và bình luận chưa bị ẩn.
- Thành viên chỉ sửa được dữ liệu của chính mình (theo dõi, lịch sử, bình luận, đánh giá). Không tự sửa `role`, `is_locked` hay bộ đếm.
- Gọi `become_author()` để thành tác giả. Tác giả đăng truyện ở trạng thái `pending`, chỉ admin mới đổi sang `published` hoặc `removed` (story 16).
- Admin khóa tài khoản bằng `admin_set_locked(uid, true)`; tài khoản bị khóa không đăng truyện, bình luận, đánh giá được.
- Gọi `track_view(story_id, chapter_id)` khi mở chương để ghi lượt xem (story 14). DB chỉ tính 1 lượt/người (user hoặc IP)/chương/giờ nên không bơm lượt đọc bằng cách gọi lặp được.
- Tác giả sửa được tên/mô tả/bìa truyện đã duyệt, nhưng chỉ admin đổi được trạng thái sang `published`/`removed` (trigger `stories_status_guard`). Truyện bị gỡ không tự đặt lại thành chờ duyệt.
- Số chương do DB gán (trigger `chapters_number`): thêm cùng lúc không bị trùng. Xóa chương giữa chừng để lại chỗ trống số (vd 1, 3, 4) vì khóa ảnh trên R2 gắn với số chương; trang đọc dùng thứ tự nên không lỗi.

## Lưu ý gói miễn phí
- Project Supabase Free **tự tạm dừng sau 7 ngày không có truy cập**. Khi demo thì mở lại trước đó, hoặc đặt một lịch gọi API định kỳ.
- Gói Free **không có backup tự động**. Định kỳ chạy `pg_dump` (hoặc xuất từ Dashboard) và giữ `schema.sql` trong Git.
- Vượt 500 MB database thì DB chuyển sang chỉ đọc. Vì vậy không lưu ảnh trong DB, chỉ lưu key.
- Vượt giới hạn băng thông của Supabase, dịch vụ có thể bị chặn đến kỳ sau. Ảnh đã đi qua R2 nên phần này chủ yếu là dữ liệu JSON, rất nhẹ.

## Giới hạn đã biết
- Nội dung chữ của chương đã tách sang `chapter_contents` và chặn bằng RLS (`can_read_chapter`, Sprint 3). **Ảnh truyện tranh trả phí chưa bảo vệ thật**: DB giấu danh sách ảnh nhưng file trên R2 vẫn tải được nếu đoán đúng đường dẫn; cần bucket riêng + link đọc có chữ ký.
- Từ Sprint 4 `grant_entitlement()` tự cấp quyền khi đơn thanh toán thành công; `db/dev.sql` lệnh 4 chỉ còn để cấp quyền thử không qua thanh toán.
- Giới hạn dung lượng ở hàm cấp link dựa trên số khai báo của web, chưa phải giới hạn cứng phía R2. Nên đặt thêm quy tắc/cảnh báo dung lượng trên dashboard Cloudflare.
- Xóa chương chỉ xóa dữ liệu trong DB, ảnh cũ vẫn còn trong R2 (tốn chỗ). Cần thêm hàm xóa ảnh ở Sprint sau.
- Truyện tranh chưa hỗ trợ sửa ảnh của chương đã đăng: xóa chương rồi đăng lại.
- Trình duyệt cần hỗ trợ xuất ảnh WebP (Chrome, Edge, Firefox, Android đều được; Safari cũ có thể không).
