-- Lệnh tiện dụng khi phát triển (chạy trong Supabase SQL Editor). Sprint 2 sẽ có trang admin thay cho các lệnh này.
-- 1) Biến tài khoản của bạn thành admin (thay email):
update profiles set role='admin' where id=(select id from auth.users where email='email-cua-ban@gmail.com');
-- 2) Duyệt tất cả truyện đang chờ duyệt (story 16) để chúng hiện ra cho khách:
update stories set status='published' where status='pending';
-- 3) Xem nhanh dữ liệu:
select id,title,status,chapter_count,view_count from stories order by id desc;
