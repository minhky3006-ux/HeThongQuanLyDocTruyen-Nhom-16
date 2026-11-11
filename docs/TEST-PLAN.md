# Kế hoạch kiểm thử tích hợp (Sprint 6)

## 1. Kiểm thử tự động ở tầng DB (làm trước)
Dán `db/tests/regression.sql` vào Supabase SQL Editor và bấm Run. Kết quả là danh sách `PASS | …` / `FAIL | …` và dòng tổng. **Không để lại dữ liệu** (mọi thay đổi bị hoàn tác).
Bộ này kiểm 52 điều quan trọng nhất: quyền đọc theo từng loại người dùng và loại gói, chặn ghi trái phép vào đơn/gói/giá, thanh toán và gia hạn, chương hẹn giờ, thông báo, thảo luận chương, báo cáo/hạn chế, đối soát, và đối chiếu số liệu thống kê với SQL trực tiếp.
- Điều kiện: đã chạy `schema.sql`, `db/migrations/ALL_sprint3-6.sql` và `db/seed_test_ALL.sql`.
- **Quy tắc nhóm:** trước khi nộp hoặc gộp nhánh vào `main`, chạy lại và phải **0 lỗi**. Thêm tính năng mới thì thêm kiểm tra vào file này.
- Đã thử: 52/52 đạt trên DB mới chạy đủ chuỗi, chạy lặp lại cho cùng kết quả; khi cố ý phá hàm `can_read_chapter` thì 12 kiểm tra báo lỗi (tức bộ kiểm thử bắt được lỗi thật).

## 2. Kiểm thử thủ công theo story
Tài khoản test (mật khẩu `Test@123456`): `admin@`, `tacgia1@`, `tacgia2@`, `thanhvien1@`, `thanhvien2@` (có gói), `thanhvien3@` (gói hết hạn) `…@example.com`. Cần đã nạp seed 1, 3, 4, 5, 6. Mỗi dòng: làm bước → thấy kết quả mong đợi.

### Khách vãng lai
| Story | Bước | Mong đợi |
|---|---|---|
| 1, 2, 29 | Mở trang chủ; vào Danh sách, đổi sắp xếp Mới cập nhật / Mới phát hành / Đọc nhiều | Có đủ ba mục; `?sort=released` đúng; truyện trả phí có 🔒 |
| 3, 30 | Mở truyện 103 (kết hợp) | Danh sách chương: chương 1–2 "Miễn phí", từ chương 3 "🔒 Trả phí"; thấy tiến độ truyện |
| 4 | Tìm theo tên truyện, tên tác giả, lọc thể loại | Kết quả đúng; không lỗi khi không có kết quả |
| 5 | Đăng ký tài khoản mới | Tạo được, vào được trang tủ truyện |
| 7, 31 | Đọc chương 1 truyện 101 (miễn phí); mở chương 2 truyện 102 (trả phí) | Đọc được chương miễn phí; chương trả phí hiện khung "🔒 Chương trả phí", **tab Network không có nội dung chương** |

### Thành viên
| Story | Bước | Mong đợi |
|---|---|---|
| 6, 11 | Đăng nhập sai/đúng mật khẩu; đăng xuất | Báo lỗi tiếng Việt; đăng xuất về trạng thái khách |
| 8, 10 | Theo dõi truyện; đọc dở rồi mở Tủ truyện | Có trong danh sách theo dõi; "Đọc tiếp" đúng chương |
| 9 | Bình luận, đánh giá sao, xóa bình luận của mình | Hiện ngay; chỉ xóa được của mình |
| 31, 35 | `thanhvien2` mở truyện 102 | Đọc được; trang truyện ghi "đọc được nhờ gói…", **không có nút Mua** |
| 31 | `thanhvien3` (gói hết hạn) và `thanhvien1` mở truyện 102 | Bị khóa như khách |
| 32, 33 | `thanhvien1`: Gói đọc → chọn gói → Thanh toán → cổng giả lập "thành công" | Đơn `paid`; đọc được truyện trả phí; mua lại cùng gói thì nút **Gia hạn**, thời hạn nối tiếp |
| 32 | Cổng giả lập "thất bại" | Đơn `failed`, không cấp quyền |
| 34, 35 | `thanhvien1` mua lẻ truyện 102; rồi vào `checkout.html?story=102` | Mua được; lần sau báo "không cần thanh toán lại" |
| 36 | Mở Tủ truyện › Gói & giao dịch | Gói đang dùng + ngày hết hạn, truyện đã mua, lịch sử đơn (thành công/thất bại) |
| 37 | Mở chương đọc được, gửi thảo luận; đăng nhập người không có quyền chương trả phí | Thảo luận hiện ở chương đó; người không có quyền không thấy/không viết được |
| 38 | Bấm Báo cáo ở bình luận người khác; báo cáo lần hai | Thông báo đã gửi; lần hai báo "đã báo cáo rồi"; không có nút Báo cáo ở bình luận của mình |
| 39 | Theo dõi truyện 101; `tacgia1` đăng chương mới | Chuông có số; bấm vào mở đúng chương, số giảm |
| 40 | Mở chương 8 giây | `view_count` tăng 1; mở rồi thoát ngay không tăng; chương bị khóa không tăng |
| 41 | Cài PWA ("Thêm vào màn hình chính") hoặc mở bản Capacitor (`mobile/README.md`); lặp lại đăng nhập → duyệt → đọc → mua | Các bước chạy như web; sau thanh toán quay lại ứng dụng vẫn đăng nhập |

### Tác giả
| Story | Bước | Mong đợi |
|---|---|---|
| 12, 13 | Tạo truyện (chữ và tranh), thêm/sửa/xóa chương | Truyện chờ duyệt; nội dung lưu/sửa đúng |
| 14 | Mở thống kê | Lượt xem khớp thực tế |
| 20 | Đăng chương **hẹn giờ**; đổi tiến độ truyện sang Hoàn thành | Khách không thấy chương tới giờ; tác giả thấy nhãn ⏰; tiến độ hiện ở trang truyện |

### Quản trị viên
| Story | Bước | Mong đợi |
|---|---|---|
| 15, 23 | Khóa/mở khóa người dùng; hạn chế bình luận 7 ngày rồi gỡ | Người bị khóa/hạn chế không bình luận được, hiện lý do; không tác động được admin |
| 16 | Duyệt/gỡ truyện chờ duyệt | Trạng thái đổi; truyện gỡ biến khỏi danh sách |
| 17, 18 | Thêm/sửa/xóa thể loại; ẩn bình luận | Áp dụng ngay |
| 19 | Chính sách truy cập: đổi truyện sang kết hợp, tick chương đọc thử | Khách thấy thay đổi ngay |
| 21 | Thêm gói, ngừng bán, xóa gói đã có người mua | Gói ngừng bán biến khỏi trang mua nhưng người đã mua vẫn dùng; xóa gói đã bán bị chặn |
| 22 | Đặt/đổi giá bán lẻ | Nút Mua hiện giá mới; đơn cũ giữ giá cũ |
| 23 | Báo cáo → Ẩn / Bỏ qua; tab Nhật ký kiểm duyệt | Bình luận ẩn với người khác; nhật ký ghi ai làm gì |
| 24 | Giao dịch: xử lý 4 loại bất thường (seed 5) | Cấp lại quyền/hủy/xác nhận thủ công (bắt buộc ghi chú)/bỏ qua; đơn hết bất thường |
| 25 | Thống kê thành viên, đổi ngày/tháng | Tổng khớp số tài khoản; mới/gia hạn đúng định nghĩa |
| 26, 27 | Doanh thu: gói và theo truyện, lọc một truyện, Xuất CSV | Tổng = tổng đơn `paid` trong khoảng; CSV mở được bằng Excel, tiếng Việt đúng |
| 28 | Thống kê nội dung | Top xem/theo dõi/chương/thảo luận/thể loại; **không** lẫn truyện chưa duyệt |

## 3. Kiểm tra phi chức năng trước khi nộp
- [ ] Mở từng trang ở màn hình điện thoại (≈390px) và máy tính: không tràn ngang, thanh dưới không che nội dung.
- [ ] Tắt mạng giữa chừng: có thông báo lỗi tiếng Việt, không trắng trang.
- [ ] Mở tab Network khi đọc chương trả phí bằng khách: không có nội dung; thử gọi trực tiếp `POST /rest/v1/orders` bằng token thành viên: bị từ chối.
- [ ] Không còn `PAYMENT_PROVIDER=mock` ở bản triển khai chính thức (xem `db/README.md`).
- [ ] `git status` sạch, `config.js` (khóa Supabase) **không** bị commit.
