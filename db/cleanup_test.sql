-- Xóa toàn bộ DỮ LIỆU TEST (6 tài khoản @example.com và các truyện của họ). Không đụng tới dữ liệu thật của người khác.
-- Ảnh test trong R2 (covers/101..105*, s104/, s105/) bạn tự xóa trên dashboard Cloudflare nếu muốn.
delete from stories where id between 101 and 106 or id between 201 and 225
   or author_id in (select id from auth.users where email in ('admin@example.com','tacgia1@example.com','tacgia2@example.com','thanhvien1@example.com','thanhvien2@example.com','thanhvien3@example.com'));
delete from auth.users where email in ('admin@example.com','tacgia1@example.com','tacgia2@example.com','thanhvien1@example.com','thanhvien2@example.com','thanhvien3@example.com');   -- kéo theo profiles, theo dõi, bình luận, đánh giá, lịch sử
