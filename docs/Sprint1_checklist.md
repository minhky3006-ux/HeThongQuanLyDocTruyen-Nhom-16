# Sprint 1 — Đối chiếu Product Backlog (27 điểm)

| ID | Story | Trang / hàm | Cách kiểm tra |
|---|---|---|---|
| 1 | Xem trang chủ (2) | `index.html` · `API.listStories` | Thấy mục "Đang được đọc nhiều" và "Mới cập nhật" |
| 2 | Xem danh sách truyện (2) | `stories/list.html` | Cuộn, bấm "Xem thêm" khi >20 truyện, đổi sắp xếp |
| 3 | Xem chi tiết truyện/chương (3) | `stories/detail.html` · `getStory`, `listChapters` | Thấy bìa, tác giả, thể loại, mô tả, danh sách chương |
| 4 | Tìm kiếm truyện (3) | `stories/list.html` | Gõ tên truyện hoặc tên tác giả; bấm chip thể loại |
| 5 | Đăng ký tài khoản (2) | `auth/register.html` · `signUp` | Đăng ký, kiểm tra bảng `profiles` có dòng mới |
| 6 | Đăng nhập (2) | `auth/login.html` · `signIn` | Đăng nhập đúng/sai, thấy nút "Đăng xuất" |
| 7 | Đọc nội dung chương (3) | `stories/reader.html` · `getChapter` | Đọc chương chữ và chương tranh, nút chương trước/sau |
| 12 | Đăng truyện mới (5) | `author/dashboard.html` · `createStory`, `uploadCover` | Đăng truyện kèm bìa, trạng thái "Chờ duyệt" |
| 13 | Quản lý chương (5) | `author/chapters.html` · `addChapter`, `addComicChapter`, `updateChapter`, `deleteChapter` | Thêm/sửa/xóa chương chữ; đăng chương tranh nhiều ảnh |

Truyện chỉ hiện cho khách sau khi admin duyệt (story 16, Sprint 2). Trong lúc đó dùng `db/dev.sql`.
Làm thêm sớm (không nằm trong Sprint 1): theo dõi truyện, đọc tiếp từ chương dở, đăng xuất.
