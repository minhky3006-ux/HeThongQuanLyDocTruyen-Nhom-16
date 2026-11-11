# TruyệnXanh — Hệ thống quản lý đọc truyện (Nhóm 16)

Khung giao diện HTML/CSS/JS thuần, responsive: mobile hiển thị tab bar dưới (như app), desktop hiển thị menu trên. Có `manifest.json` nên thêm vào màn hình chính như app (PWA).

## Chạy thử
Làm theo `db/README.md` (mục Cài đặt) để nối Supabase + R2, rồi mở bằng Live Server. Chưa cấu hình thì trang hiện thông báo nhắc.

## Cấu trúc thư mục
```
truyen-xanh/
├── index.html              Trang chủ
├── manifest.json           Cấu hình PWA (dùng như app)
├── sw.js                   Service worker (cài được như app, mở khung khi mất mạng)
├── mobile/                 Vỏ ứng dụng Android/iOS (Capacitor), xem mobile/README.md
├── assets/
│   ├── css/style.css       Màu, font, component dùng chung (sửa token ở :root)
│   ├── js/api.js           MỌI truy vấn Supabase + upload ảnh R2 (API.xxx)
│   ├── js/ui.js            Hàm dựng HTML dùng chung, esc() chống XSS
│   ├── js/layout.js        Header + tab bar + nút đăng xuất (+ mục Quản trị cho admin)
│   ├── js/admin.js         Kiểm tra quyền admin + menu con cho trang quản trị
│   ├── js/config.example.js  Mẫu cấu hình (copy thành config.js, không commit)
│   └── img/                Ảnh, icon
├── pages/
│   ├── stories/            list, detail, reader
│   ├── auth/               login, register
│   ├── author/             dashboard (đăng truyện, quản lý chương)
│   ├── member/             library (theo dõi, lịch sử đọc, đăng xuất), checkout, billing, mock-gateway (cổng giả lập))
│   └── admin/              users, stories, genres, comments, access, plans, reports, orders, members, revenue, content
├── db/                     Schema PostgreSQL, seed, dev.sql, hướng dẫn Supabase + R2
├── supabase/functions/     r2-upload-url, create-payment, payment-webhook, _shared
├── templates/page.html     File mẫu để copy khi làm trang mới
└── docs/                   Tài liệu bài thực hành, case study
```
`data-root` trong thẻ `<body>` là đường đi từ trang về thư mục gốc (`""` ở gốc, `"../../"` trong `pages/<nhóm>/`).


## Phân công Sprint 1 (theo Product Backlog)
| Người | Story | File |
|---|---|---|
| Lê Quốc Thắng | 1, 2, 5, 6 | index, stories/list, auth/register, auth/login |
| Phạm Thanh Bình | 3, 4, 7 | stories/detail, stories/list (tìm kiếm), stories/reader |
| Đỗ Minh Kỳ | 12, 13 | author/dashboard (+ trang đăng truyện, quản lý chương) |

## Phân công Sprint 2 (tuần 3–4, 22 điểm)
| Người | Story | File |
|---|---|---|
| Lê Quốc Thắng | 11 | member/library (nút Đăng xuất), layout.js |
| Phạm Thanh Bình | 8, 9, 10 | stories/detail (theo dõi, đánh giá, bình luận), member/library, stories/reader (lưu lịch sử) |
| Đỗ Minh Kỳ | 14, 15, 16, 17, 18 | author/stats, admin/users, admin/stories, admin/genres, admin/comments |

## Cập nhật nhanh DB lên bản Sprint 6
Dán và chạy **một file** `db/migrations/ALL_sprint3-6.sql` trong Supabase SQL Editor (sao lưu trước; chạy lại được). Dữ liệu thử: `db/seed_test_ALL.sql`. Kiểm tra: `db/tests/regression.sql` (0 lỗi). Hàm thanh toán: xem `db/README.md` mục 5c.

## Phân công Sprint 6 (tuần 11–12, 23 điểm)
| Người | Story | File |
|---|---|---|
| Đỗ Minh Kỳ | 26, 27 | admin/revenue (doanh thu gói và theo truyện), db/migrations/005 |
| Lê Quốc Thắng | 28 | admin/content (thống kê nội dung) |
| Phạm Thanh Bình | 41 | mobile/ (vỏ Capacitor), sw.js (PWA), docs/API-REST.md |
| Cả nhóm | Kiểm thử tích hợp | db/tests/regression.sql, docs/TEST-PLAN.md |

Chi tiết: **`docs/SPRINT6.md`**. DB cũ: chạy `db/migrations/ALL_sprint3-6.sql`. Trước khi nộp: chạy `db/tests/regression.sql` (0 lỗi) và làm theo `docs/TEST-PLAN.md`.

## Phân công Sprint 5 (tuần 9–10, 23 điểm)
| Người | Story | File |
|---|---|---|
| Đỗ Minh Kỳ | 24, 23 | admin/orders (đối soát), admin/reports (xử lý báo cáo), admin/users (hạn chế), db/migrations/004 |
| Phạm Thanh Bình | 37, 39 | stories/reader (thảo luận chương), member/notifications + chuông trong layout.js |
| Lê Quốc Thắng | 38, 25 | nút Báo cáo (ui.js, stories/detail, stories/reader), admin/members (thống kê) |

Chi tiết và kịch bản thử: **`docs/SPRINT5.md`**. DB cũ: chạy `db/migrations/ALL_sprint3-6.sql`.

## Phân công Sprint 4 (tuần 7–8, 25 điểm)
| Người | Story | File |
|---|---|---|
| Đỗ Minh Kỳ | 22, 20 | admin/access (giá bán lẻ), author/chapters (hẹn giờ), author/edit (tiến độ truyện), db/migrations/003 |
| Phạm Thanh Bình | 33, 34 | member/checkout (gia hạn, mua lẻ), supabase/functions/create-payment, stories/detail + reader (nút mua) |
| Lê Quốc Thắng | 35, 36, 40 | stories/detail (quyền gộp), member/billing (lịch sử), track_view + reader (lượt đọc) |

Chi tiết và kịch bản thử: **`docs/SPRINT4.md`**. DB cũ: chạy `db/migrations/ALL_sprint3-6.sql` rồi deploy lại `create-payment`.

## Phân công Sprint 3 (tuần 5–6, 25 điểm)
| Người | Story | File |
|---|---|---|
| Đỗ Minh Kỳ | 19, 21 | admin/access, admin/plans, db/migrations/002 |
| Phạm Thanh Bình | 31, 32 | stories/reader (khung mua gói), member/checkout, supabase/functions/create-payment + payment-webhook |
| Lê Quốc Thắng | 29, 30 | index, stories/list, stories/detail (nhãn miễn phí/trả phí) |

Chi tiết, thứ tự làm, kịch bản thử và tiêu chí hoàn thành: **`docs/SPRINT3.md`**. DB cũ phải chạy `db/migrations/ALL_sprint3-6.sql` (xóa cột `chapters.content`, sao lưu trước).

Đây là khung đã nối sẵn với `API.xxx()`; chưa kiểm thử với dữ liệu thật. Quyền admin: chạy lệnh 1 trong `db/dev.sql` để tài khoản của bạn thành admin.

## Quy trình Git
- `main`: bản ổn định, chỉ merge từ `develop` cuối sprint
- `develop`: nhánh chung
- Mỗi story một nhánh: `feature/<id>-<ten-ngan>`, ví dụ `feature/7-doc-chuong`

```bash
git clone <url-repo> && cd truyen-xanh
git checkout develop && git pull
git checkout -b feature/7-doc-chuong
# ... code ...
git add . && git commit -m "feat(7): đọc nội dung chương"
git push -u origin feature/7-doc-chuong   # rồi tạo Pull Request vào develop
```
Quy ước commit: `feat(id)`, `fix(id)`, `style`, `docs`. Nhớ `git pull` trước khi bắt đầu làm mỗi ngày. Hạn chế sửa `style.css` cùng lúc — báo nhóm trước.

## Thiết lập VS Code
1. Cài VS Code, Git (git-scm.com), mở thư mục `truyen-xanh` bằng *File > Open Folder*.
2. Bấm **Install** khi VS Code hỏi cài các extension khuyên dùng (Live Server, Prettier, GitLens...).
3. Chuột phải `index.html` > **Open with Live Server** (http://127.0.0.1:5500), lưu file là trình duyệt tự tải lại.
4. Giả lập điện thoại: F12 > biểu tượng thiết bị (Ctrl+Shift+M).
