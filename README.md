# TruyệnXanh — Hệ thống quản lý đọc truyện (Nhóm 16)

Khung giao diện HTML/CSS/JS thuần, responsive: mobile hiển thị tab bar dưới (như app), desktop hiển thị menu trên. Có `manifest.json` nên thêm vào màn hình chính như app (PWA).

## Chạy thử
Làm theo `db/README.md` (mục Cài đặt) để nối Supabase + R2, rồi mở bằng Live Server. Chưa cấu hình thì trang hiện thông báo nhắc.

## Cấu trúc thư mục
```
truyen-xanh/
├── index.html              Trang chủ
├── manifest.json           Cấu hình PWA (dùng như app)
├── assets/
│   ├── css/style.css       Màu, font, component dùng chung (sửa token ở :root)
│   ├── js/api.js           MỌI truy vấn Supabase + upload ảnh R2 (API.xxx)
│   ├── js/ui.js            Hàm dựng HTML dùng chung, esc() chống XSS
│   ├── js/layout.js        Header + tab bar + nút đăng xuất
│   ├── js/config.example.js  Mẫu cấu hình (copy thành config.js, không commit)
│   └── img/                Ảnh, icon
├── pages/
│   ├── stories/            list, detail, reader
│   ├── auth/               login, register
│   ├── author/             dashboard (đăng truyện, quản lý chương)
│   ├── member/             (Sprint 2) yêu thích, lịch sử, bình luận
│   └── admin/              (Sprint 2) người dùng, duyệt truyện, thể loại
├── db/                     Schema PostgreSQL, seed, dev.sql, hướng dẫn Supabase + R2
├── supabase/functions/     Hàm cấp link upload ảnh lên R2
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
